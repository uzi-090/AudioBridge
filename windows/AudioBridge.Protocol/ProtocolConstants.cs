namespace AudioBridge.Protocol;

public static class ProtocolConstants
{
    public const uint Magic = 0x41425231; // ABR1
    public const byte Version = 1;
    public const int HeaderSize = 20;
    public const int SampleRate = 48_000;
    public const int ChannelCount = 2;
    public const int FrameMilliseconds = 5;
    public const int FramesPerPacket = 240;
    public const int BytesPerSample = 2;
    public const int AudioPayloadSize = FramesPerPacket * ChannelCount * BytesPerSample;
    public const int DefaultPort = 43_120;
}
