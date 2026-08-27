using System.Buffers.Binary;
using System.Text;

namespace AudioBridge.Protocol;

public static class PacketCodec
{
    public static byte[] Encode(
        AudioBridgePacketType type,
        uint sequence = 0,
        ulong timestamp = 0,
        ReadOnlySpan<byte> payload = default,
        ushort flags = 0)
    {
        var packet = new byte[ProtocolConstants.HeaderSize + payload.Length];
        var span = packet.AsSpan();

        BinaryPrimitives.WriteUInt32BigEndian(span[0..4], ProtocolConstants.Magic);
        span[4] = ProtocolConstants.Version;
        span[5] = (byte)type;
        BinaryPrimitives.WriteUInt16BigEndian(span[6..8], flags);
        BinaryPrimitives.WriteUInt32BigEndian(span[8..12], sequence);
        BinaryPrimitives.WriteUInt64BigEndian(span[12..20], timestamp);
        payload.CopyTo(span[ProtocolConstants.HeaderSize..]);
        return packet;
    }

    public static byte[] EncodeHello(string pairingCode, ushort targetBufferPackets)
    {
        var token = Encoding.UTF8.GetBytes(pairingCode);
        if (token.Length is 0 or > byte.MaxValue)
        {
            throw new ArgumentException("Pairing code must contain 1 to 255 UTF-8 bytes.", nameof(pairingCode));
        }

        var payload = new byte[9 + token.Length];
        BinaryPrimitives.WriteUInt32BigEndian(payload.AsSpan(0, 4), ProtocolConstants.SampleRate);
        payload[4] = ProtocolConstants.ChannelCount;
        payload[5] = ProtocolConstants.FrameMilliseconds;
        BinaryPrimitives.WriteUInt16BigEndian(payload.AsSpan(6, 2), targetBufferPackets);
        payload[8] = (byte)token.Length;
        token.CopyTo(payload.AsSpan(9));
        return Encode(AudioBridgePacketType.Hello, payload: payload);
    }

    public static byte[] EncodeAudio(uint sequence, ulong timestamp, ReadOnlySpan<byte> pcm)
    {
        if (pcm.Length != ProtocolConstants.AudioPayloadSize)
        {
            throw new ArgumentException(
                $"Audio payload must be exactly {ProtocolConstants.AudioPayloadSize} bytes.",
                nameof(pcm));
        }

        return Encode(AudioBridgePacketType.Audio, sequence, timestamp, pcm);
    }

    public static bool TryDecode(ReadOnlySpan<byte> datagram, out AudioBridgePacket? packet)
    {
        packet = null;
        if (datagram.Length < ProtocolConstants.HeaderSize ||
            BinaryPrimitives.ReadUInt32BigEndian(datagram[0..4]) != ProtocolConstants.Magic ||
            datagram[4] != ProtocolConstants.Version ||
            !Enum.IsDefined(typeof(AudioBridgePacketType), datagram[5]))
        {
            return false;
        }

        var type = (AudioBridgePacketType)datagram[5];
        var payload = datagram[ProtocolConstants.HeaderSize..].ToArray();
        if (type == AudioBridgePacketType.Audio && payload.Length != ProtocolConstants.AudioPayloadSize)
        {
            return false;
        }

        packet = new AudioBridgePacket(
            type,
            BinaryPrimitives.ReadUInt16BigEndian(datagram[6..8]),
            BinaryPrimitives.ReadUInt32BigEndian(datagram[8..12]),
            BinaryPrimitives.ReadUInt64BigEndian(datagram[12..20]),
            payload);
        return true;
    }

    public static bool TryDecodeHelloPayload(ReadOnlySpan<byte> payload, out HelloPayload? hello)
    {
        hello = null;
        if (payload.Length < 10)
        {
            return false;
        }

        var tokenLength = payload[8];
        if (tokenLength == 0 || payload.Length != 9 + tokenLength)
        {
            return false;
        }

        try
        {
            hello = new HelloPayload(
                BinaryPrimitives.ReadUInt32BigEndian(payload[0..4]),
                payload[4],
                payload[5],
                BinaryPrimitives.ReadUInt16BigEndian(payload[6..8]),
                new UTF8Encoding(false, true).GetString(payload[9..]));
            return true;
        }
        catch (DecoderFallbackException)
        {
            return false;
        }
    }
}
