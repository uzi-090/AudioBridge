namespace AudioBridge.Protocol;

public enum AudioBridgePacketType : byte
{
    Hello = 1,
    Acknowledgement = 2,
    Audio = 3,
    Ping = 4,
    Pong = 5,
    Stop = 6,
}
