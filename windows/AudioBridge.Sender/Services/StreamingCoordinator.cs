using System.Buffers.Binary;
using System.Threading.Channels;
using AudioBridge.Protocol;
using AudioBridge.Sender.Audio;
using AudioBridge.Sender.Networking;

namespace AudioBridge.Sender.Services;

public enum StreamSource
{
    None,
    SystemAudio,
    TestTone,
}

public sealed record SenderMetrics(
    StreamSource Source,
    ulong PacketsSent,
    ulong BytesSent,
    double PeakLevel,
    bool IsPaired);

public sealed class StreamingCoordinator : IAsyncDisposable
{
    private readonly PairingServer _server;
    private readonly Channel<byte[]> _frames = Channel.CreateBounded<byte[]>(
        new BoundedChannelOptions(128)
        {
            FullMode = BoundedChannelFullMode.DropOldest,
            SingleReader = true,
            SingleWriter = false,
        });

    private CancellationTokenSource? _lifetime;
    private Task? _producerTask;
    private Task? _senderTask;
    private SystemAudioCapture? _capture;
    private long _packetsSent;
    private long _bytesSent;
    private double _peakLevel;
    private uint _nextSequence;
    private ulong _nextTimestamp;

    public StreamingCoordinator(PairingServer server)
    {
        _server = server;
    }

    public StreamSource Source { get; private set; }
    public event Action<string>? Log;

    public SenderMetrics Metrics => new(
        Source,
        unchecked((ulong)Interlocked.Read(ref _packetsSent)),
        unchecked((ulong)Interlocked.Read(ref _bytesSent)),
        Volatile.Read(ref _peakLevel),
        _server.IsPaired);

    public async Task StartAsync(StreamSource source)
    {
        if (source == StreamSource.None)
        {
            throw new ArgumentOutOfRangeException(nameof(source));
        }

        await StopAsync().ConfigureAwait(false);
        Interlocked.Exchange(ref _packetsSent, 0);
        Interlocked.Exchange(ref _bytesSent, 0);
        Volatile.Write(ref _peakLevel, 0);

        Source = source;
        _lifetime = new CancellationTokenSource();
        _senderTask = SendLoopAsync(_lifetime.Token);

        if (source == StreamSource.SystemAudio)
        {
            _capture = new SystemAudioCapture();
            _capture.FrameReady += CaptureOnFrameReady;
            _capture.Faulted += CaptureOnFaulted;
            _capture.Start();
            Log?.Invoke("Streaming the Windows default playback device.");
        }
        else
        {
            _producerTask = ProduceTestToneAsync(_lifetime.Token);
            Log?.Invoke("Streaming a 440 Hz test tone.");
        }
    }

    private void CaptureOnFrameReady(byte[] frame) => _frames.Writer.TryWrite(frame);

    private void CaptureOnFaulted(Exception exception) =>
        Log?.Invoke($"Audio capture error: {exception.Message}");

    private async Task ProduceTestToneAsync(CancellationToken cancellationToken)
    {
        var tone = new TestToneGenerator();
        using var timer = new PeriodicTimer(TimeSpan.FromMilliseconds(ProtocolConstants.FrameMilliseconds));

        try
        {
            while (await timer.WaitForNextTickAsync(cancellationToken).ConfigureAwait(false))
            {
                _frames.Writer.TryWrite(tone.NextFrame());
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
    }

    private async Task SendLoopAsync(CancellationToken cancellationToken)
    {
        try
        {
            await foreach (var frame in _frames.Reader.ReadAllAsync(cancellationToken).ConfigureAwait(false))
            {
                Volatile.Write(ref _peakLevel, CalculatePeak(frame));
                await _server.SendAudioAsync(_nextSequence, _nextTimestamp, frame, cancellationToken).ConfigureAwait(false);

                if (_server.IsPaired)
                {
                    Interlocked.Increment(ref _packetsSent);
                    Interlocked.Add(ref _bytesSent, frame.Length);
                }

                _nextSequence++;
                _nextTimestamp += ProtocolConstants.FramesPerPacket;
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
    }

    private static double CalculatePeak(ReadOnlySpan<byte> pcm)
    {
        var peak = 0;
        for (var offset = 0; offset + 1 < pcm.Length; offset += 2)
        {
            var magnitude = Math.Abs((int)BinaryPrimitives.ReadInt16LittleEndian(pcm[offset..]));
            peak = Math.Max(peak, magnitude);
        }

        return peak / 32768.0;
    }

    public async Task StopAsync()
    {
        if (_lifetime is null)
        {
            Source = StreamSource.None;
            return;
        }

        await _lifetime.CancelAsync().ConfigureAwait(false);
        if (_capture is not null)
        {
            _capture.FrameReady -= CaptureOnFrameReady;
            _capture.Faulted -= CaptureOnFaulted;
            await _capture.DisposeAsync().ConfigureAwait(false);
            _capture = null;
        }

        foreach (var task in new[] { _producerTask, _senderTask })
        {
            if (task is null)
            {
                continue;
            }

            try
            {
                await task.ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
            }
        }

        _lifetime.Dispose();
        _lifetime = null;
        _producerTask = null;
        _senderTask = null;
        while (_frames.Reader.TryRead(out _))
        {
        }
        Source = StreamSource.None;
        Log?.Invoke("Audio streaming stopped.");
    }

    public async ValueTask DisposeAsync() => await StopAsync().ConfigureAwait(false);
}
