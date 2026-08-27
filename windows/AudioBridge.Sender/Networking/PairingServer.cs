using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using AudioBridge.Protocol;

namespace AudioBridge.Sender.Networking;

public sealed class PairingServer : IAsyncDisposable
{
    private readonly int _port;
    private readonly SemaphoreSlim _sendGate = new(1, 1);
    private UdpClient? _udp;
    private CancellationTokenSource? _lifetime;
    private Task? _receiveTask;
    private IPEndPoint? _client;

    public PairingServer(int port = ProtocolConstants.DefaultPort)
    {
        _port = port;
        PairingCode = GeneratePairingCode();
    }

    public string PairingCode { get; private set; }
    public IPEndPoint? Client => _client;
    public bool IsPaired => _client is not null;

    public event Action<IPEndPoint>? ClientPaired;
    public event Action? ClientDisconnected;
    public event Action<string>? Log;

    public void Start()
    {
        if (_udp is not null)
        {
            return;
        }

        _udp = new UdpClient(new IPEndPoint(IPAddress.Any, _port));
        _lifetime = new CancellationTokenSource();
        _receiveTask = ReceiveLoopAsync(_lifetime.Token);
        Log?.Invoke($"Listening for iPhone on UDP {_port}.");
    }

    public void RegeneratePairingCode()
    {
        PairingCode = GeneratePairingCode();
        DisconnectClient(sendStop: true);
        Log?.Invoke("Created a new pairing code.");
    }

    public async ValueTask SendAudioAsync(
        uint sequence,
        ulong timestamp,
        ReadOnlyMemory<byte> pcm,
        CancellationToken cancellationToken)
    {
        var client = _client;
        if (_udp is null || client is null)
        {
            return;
        }

        var packet = PacketCodec.EncodeAudio(sequence, timestamp, pcm.Span);
        await SendPacketAsync(packet, client, cancellationToken).ConfigureAwait(false);
    }

    private async Task ReceiveLoopAsync(CancellationToken cancellationToken)
    {
        try
        {
            while (!cancellationToken.IsCancellationRequested && _udp is not null)
            {
                var received = await _udp.ReceiveAsync(cancellationToken).ConfigureAwait(false);
                HandleDatagram(received.Buffer, received.RemoteEndPoint, cancellationToken);
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        catch (ObjectDisposedException)
        {
        }
        catch (Exception exception)
        {
            Log?.Invoke($"Receiver error: {exception.Message}");
        }
    }

    private void HandleDatagram(byte[] datagram, IPEndPoint endpoint, CancellationToken cancellationToken)
    {
        if (!PacketCodec.TryDecode(datagram, out var packet) || packet is null)
        {
            return;
        }

        switch (packet.Type)
        {
            case AudioBridgePacketType.Hello:
                HandleHello(packet.Payload, endpoint, cancellationToken);
                break;
            case AudioBridgePacketType.Ping when endpoint.Equals(_client):
                _ = SendPacketAsync(
                    PacketCodec.Encode(AudioBridgePacketType.Pong, packet.Sequence, packet.Timestamp),
                    endpoint,
                    cancellationToken);
                break;
            case AudioBridgePacketType.Stop when endpoint.Equals(_client):
                DisconnectClient(sendStop: false);
                break;
        }
    }

    private void HandleHello(byte[] payload, IPEndPoint endpoint, CancellationToken cancellationToken)
    {
        if (!PacketCodec.TryDecodeHelloPayload(payload, out var hello) || hello is null)
        {
            Log?.Invoke($"Rejected malformed pairing request from {endpoint.Address}.");
            return;
        }

        if (!PairingCodesMatch(hello.PairingCode, PairingCode))
        {
            Log?.Invoke($"Rejected incorrect pairing code from {endpoint.Address}.");
            return;
        }

        if (hello.SampleRate != ProtocolConstants.SampleRate ||
            hello.Channels != ProtocolConstants.ChannelCount ||
            hello.FrameMilliseconds != ProtocolConstants.FrameMilliseconds)
        {
            Log?.Invoke($"Rejected unsupported audio format from {endpoint.Address}.");
            return;
        }

        _client = endpoint;
        _ = SendPacketAsync(PacketCodec.Encode(AudioBridgePacketType.Acknowledgement), endpoint, cancellationToken);
        Log?.Invoke($"Paired with iPhone at {endpoint.Address} (buffer {hello.TargetBufferPackets * 5} ms).");
        ClientPaired?.Invoke(endpoint);
    }

    private async Task SendPacketAsync(byte[] packet, IPEndPoint endpoint, CancellationToken cancellationToken)
    {
        var udp = _udp;
        if (udp is null)
        {
            return;
        }

        var enteredGate = false;
        try
        {
            await _sendGate.WaitAsync(cancellationToken).ConfigureAwait(false);
            enteredGate = true;
            await udp.SendAsync(packet, endpoint, cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        catch (SocketException exception)
        {
            Log?.Invoke($"Network send error: {exception.SocketErrorCode}");
        }
        finally
        {
            if (enteredGate)
            {
                _sendGate.Release();
            }
        }
    }

    private void DisconnectClient(bool sendStop)
    {
        var previous = _client;
        if (previous is null)
        {
            return;
        }

        if (sendStop && _lifetime is not null)
        {
            _ = SendPacketAsync(
                PacketCodec.Encode(AudioBridgePacketType.Stop),
                previous,
                _lifetime.Token);
        }

        _client = null;
        ClientDisconnected?.Invoke();
    }

    private static string GeneratePairingCode() =>
        RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6");

    private static bool PairingCodesMatch(string candidate, string expected)
    {
        var left = Encoding.UTF8.GetBytes(candidate);
        var right = Encoding.UTF8.GetBytes(expected);
        return left.Length == right.Length && CryptographicOperations.FixedTimeEquals(left, right);
    }

    public async ValueTask DisposeAsync()
    {
        if (_client is { } client && _lifetime is { } activeLifetime)
        {
            await SendPacketAsync(
                PacketCodec.Encode(AudioBridgePacketType.Stop),
                client,
                activeLifetime.Token).ConfigureAwait(false);
            _client = null;
            ClientDisconnected?.Invoke();
        }
        if (_lifetime is not null)
        {
            await _lifetime.CancelAsync().ConfigureAwait(false);
        }

        _udp?.Dispose();
        if (_receiveTask is not null)
        {
            try
            {
                await _receiveTask.ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
            }
        }

        _lifetime?.Dispose();
        _sendGate.Dispose();
    }
}
