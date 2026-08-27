namespace AudioBridge.Protocol;

public sealed record AudioBridgePacket(
    AudioBridgePacketType Type,
    ushort Flags,
    uint Sequence,
    ulong Timestamp,
    byte[] Payload);

public sealed record HelloPayload(
    uint SampleRate,
    byte Channels,
    byte FrameMilliseconds,
    ushort TargetBufferPackets,
    string PairingCode);
