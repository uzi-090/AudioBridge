using AudioBridge.Protocol;
using NAudio.CoreAudioApi;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;

namespace AudioBridge.Sender.Audio;

public sealed class SystemAudioCapture : IAsyncDisposable
{
    private readonly object _sync = new();
    private WasapiLoopbackCapture? _capture;
    private BufferedWaveProvider? _buffer;
    private IWaveProvider? _outputProvider;
    private CancellationTokenSource? _lifetime;
    private Task? _pumpTask;

    public event Action<byte[]>? FrameReady;
    public event Action<Exception>? Faulted;

    public void Start()
    {
        if (_capture is not null)
        {
            return;
        }

        _capture = new WasapiLoopbackCapture();
        _buffer = new BufferedWaveProvider(_capture.WaveFormat)
        {
            BufferDuration = TimeSpan.FromMilliseconds(350),
            DiscardOnBufferOverflow = true,
            ReadFully = false,
        };
        ISampleProvider samples = _buffer.ToSampleProvider();
        if (samples.WaveFormat.Channels != ProtocolConstants.ChannelCount)
        {
            samples = new StereoChannelSampleProvider(samples);
        }

        if (samples.WaveFormat.SampleRate != ProtocolConstants.SampleRate)
        {
            samples = new WdlResamplingSampleProvider(samples, ProtocolConstants.SampleRate);
        }

        _outputProvider = new SampleToWaveProvider16(samples);

        _capture.DataAvailable += CaptureOnDataAvailable;
        _capture.RecordingStopped += CaptureOnRecordingStopped;
        _lifetime = new CancellationTokenSource();
        _capture.StartRecording();
        _pumpTask = PumpAsync(_lifetime.Token);
    }

    private void CaptureOnDataAvailable(object? sender, WaveInEventArgs eventArgs)
    {
        lock (_sync)
        {
            _buffer?.AddSamples(eventArgs.Buffer, 0, eventArgs.BytesRecorded);
        }
    }

    private void CaptureOnRecordingStopped(object? sender, StoppedEventArgs eventArgs)
    {
        if (eventArgs.Exception is not null)
        {
            Faulted?.Invoke(eventArgs.Exception);
        }
    }

    private async Task PumpAsync(CancellationToken cancellationToken)
    {
        var frame = new byte[ProtocolConstants.AudioPayloadSize];
        var filled = 0;

        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                int read;
                lock (_sync)
                {
                    read = _outputProvider?.Read(frame, filled, frame.Length - filled) ?? 0;
                }

                if (read == 0)
                {
                    await Task.Delay(1, cancellationToken).ConfigureAwait(false);
                    continue;
                }

                filled += read;
                if (filled == frame.Length)
                {
                    FrameReady?.Invoke(frame);
                    frame = new byte[ProtocolConstants.AudioPayloadSize];
                    filled = 0;
                }
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        catch (Exception exception)
        {
            Faulted?.Invoke(exception);
        }
    }

    public async Task StopAsync()
    {
        if (_capture is null)
        {
            return;
        }

        if (_lifetime is not null)
        {
            await _lifetime.CancelAsync().ConfigureAwait(false);
        }

        _capture.StopRecording();
        if (_pumpTask is not null)
        {
            try
            {
                await _pumpTask.ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
            }
        }

        _capture.DataAvailable -= CaptureOnDataAvailable;
        _capture.RecordingStopped -= CaptureOnRecordingStopped;
        _capture.Dispose();
        _lifetime?.Dispose();
        _capture = null;
        _buffer = null;
        _outputProvider = null;
        _lifetime = null;
        _pumpTask = null;
    }

    public async ValueTask DisposeAsync() => await StopAsync().ConfigureAwait(false);

    private sealed class StereoChannelSampleProvider : ISampleProvider
    {
        private readonly ISampleProvider _source;
        private readonly int _inputChannels;
        private float[] _sourceBuffer = [];

        public StereoChannelSampleProvider(ISampleProvider source)
        {
            _source = source;
            _inputChannels = source.WaveFormat.Channels;
            if (_inputChannels < 1)
            {
                throw new ArgumentException("The Windows output device has no audio channels.", nameof(source));
            }

            WaveFormat = WaveFormat.CreateIeeeFloatWaveFormat(source.WaveFormat.SampleRate, ProtocolConstants.ChannelCount);
        }

        public WaveFormat WaveFormat { get; }

        public int Read(float[] buffer, int offset, int count)
        {
            var requestedFrames = count / ProtocolConstants.ChannelCount;
            if (requestedFrames == 0)
            {
                return 0;
            }

            var requestedSourceSamples = requestedFrames * _inputChannels;
            if (_sourceBuffer.Length < requestedSourceSamples)
            {
                _sourceBuffer = new float[requestedSourceSamples];
            }

            var sourceSamplesRead = _source.Read(_sourceBuffer, 0, requestedSourceSamples);
            var framesRead = sourceSamplesRead / _inputChannels;
            for (var frame = 0; frame < framesRead; frame++)
            {
                var sourceOffset = frame * _inputChannels;
                var destinationOffset = offset + (frame * ProtocolConstants.ChannelCount);
                var left = _sourceBuffer[sourceOffset];
                var right = _inputChannels > 1 ? _sourceBuffer[sourceOffset + 1] : left;
                buffer[destinationOffset] = left;
                buffer[destinationOffset + 1] = right;
            }

            return framesRead * ProtocolConstants.ChannelCount;
        }
    }
}
