using AudioBridge.Protocol;
using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace AudioBridge.Sender.Audio;

public sealed class SystemAudioCapture : IAsyncDisposable
{
    private readonly object _sync = new();
    private WasapiLoopbackCapture? _capture;
    private BufferedWaveProvider? _buffer;
    private MediaFoundationResampler? _resampler;
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
        _resampler = new MediaFoundationResampler(
            _buffer,
            new WaveFormat(ProtocolConstants.SampleRate, 16, ProtocolConstants.ChannelCount))
        {
            ResamplerQuality = 30,
        };

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
                    read = _resampler?.Read(frame, filled, frame.Length - filled) ?? 0;
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
        _resampler?.Dispose();
        _capture.Dispose();
        _lifetime?.Dispose();
        _capture = null;
        _buffer = null;
        _resampler = null;
        _lifetime = null;
        _pumpTask = null;
    }

    public async ValueTask DisposeAsync() => await StopAsync().ConfigureAwait(false);
}
