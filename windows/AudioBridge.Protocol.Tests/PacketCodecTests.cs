using AudioBridge.Protocol;

namespace AudioBridge.Protocol.Tests;

public sealed class PacketCodecTests
{
    [Fact]
    public void AudioPacketRoundTrips()
    {
        var payload = Enumerable.Range(0, ProtocolConstants.AudioPayloadSize)
            .Select(index => (byte)(index % 251))
            .ToArray();

        var encoded = PacketCodec.EncodeAudio(42, 10_080, payload);

        Assert.True(PacketCodec.TryDecode(encoded, out var decoded));
        Assert.NotNull(decoded);
        Assert.Equal(AudioBridgePacketType.Audio, decoded.Type);
        Assert.Equal((uint)42, decoded.Sequence);
        Assert.Equal((ulong)10_080, decoded.Timestamp);
        Assert.Equal(payload, decoded.Payload);
    }

    [Fact]
    public void HelloPacketRoundTrips()
    {
        var encoded = PacketCodec.EncodeHello("043921", 10);

        Assert.True(PacketCodec.TryDecode(encoded, out var packet));
        Assert.NotNull(packet);
        Assert.True(PacketCodec.TryDecodeHelloPayload(packet.Payload, out var hello));
        Assert.NotNull(hello);
        Assert.Equal((uint)48_000, hello.SampleRate);
        Assert.Equal((byte)2, hello.Channels);
        Assert.Equal((byte)5, hello.FrameMilliseconds);
        Assert.Equal((ushort)10, hello.TargetBufferPackets);
        Assert.Equal("043921", hello.PairingCode);
    }

    [Fact]
    public void HelloPacketMatchesCrossPlatformKnownVector()
    {
        var encoded = PacketCodec.EncodeHello("043921", 10);

        Assert.Equal(
            "41425231010100000000000000000000000000000000BB800205000A06303433393231",
            Convert.ToHexString(encoded));
    }

    [Fact]
    public void InvalidMagicIsRejected()
    {
        var encoded = PacketCodec.Encode(AudioBridgePacketType.Ping);
        encoded[0] ^= 0xFF;
        Assert.False(PacketCodec.TryDecode(encoded, out _));
    }

    [Fact]
    public void IncorrectAudioPayloadSizeIsRejected()
    {
        var encoded = PacketCodec.Encode(AudioBridgePacketType.Audio, payload: new byte[12]);
        Assert.False(PacketCodec.TryDecode(encoded, out _));
    }
}
