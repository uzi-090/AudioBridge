using System.Net;
using System.Net.Sockets;
using AudioBridge.Protocol;
using AudioBridge.Sender.Networking;

namespace AudioBridge.Protocol.Tests;

public sealed class PairingServerTests
{
    [Fact]
    public async Task HelloPairsClientAndAudioReturnsToSameEndpoint()
    {
        var port = ReserveAvailableUdpPort();
        await using var server = new PairingServer(port);
        using var client = new UdpClient(new IPEndPoint(IPAddress.Loopback, 0));
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        server.Start();

        var hello = PacketCodec.EncodeHello(server.PairingCode, 10);
        await client.SendAsync(hello, new IPEndPoint(IPAddress.Loopback, port), timeout.Token);
        var acknowledgement = await client.ReceiveAsync(timeout.Token);

        Assert.True(PacketCodec.TryDecode(acknowledgement.Buffer, out var ackPacket));
        Assert.NotNull(ackPacket);
        Assert.Equal(AudioBridgePacketType.Acknowledgement, ackPacket.Type);
        Assert.True(server.IsPaired);

        var pcm = Enumerable.Repeat((byte)0x5A, ProtocolConstants.AudioPayloadSize).ToArray();
        await server.SendAudioAsync(73, 17_520, pcm, timeout.Token);
        var audio = await client.ReceiveAsync(timeout.Token);

        Assert.True(PacketCodec.TryDecode(audio.Buffer, out var audioPacket));
        Assert.NotNull(audioPacket);
        Assert.Equal(AudioBridgePacketType.Audio, audioPacket.Type);
        Assert.Equal((uint)73, audioPacket.Sequence);
        Assert.Equal((ulong)17_520, audioPacket.Timestamp);
        Assert.Equal(pcm, audioPacket.Payload);
    }

    private static int ReserveAvailableUdpPort()
    {
        using var reservation = new UdpClient(new IPEndPoint(IPAddress.Loopback, 0));
        return ((IPEndPoint)reservation.Client.LocalEndPoint!).Port;
    }
}
