using System.Buffers.Binary;
using AudioBridge.Protocol;

namespace AudioBridge.Sender.Audio;

public sealed class TestToneGenerator
{
    private const double Frequency = 440.0;
    private const double Amplitude = 0.18;
    private double _phase;

    public byte[] NextFrame()
    {
        var output = new byte[ProtocolConstants.AudioPayloadSize];
        for (var frame = 0; frame < ProtocolConstants.FramesPerPacket; frame++)
        {
            var sample = (short)(Math.Sin(_phase) * short.MaxValue * Amplitude);
            _phase += 2.0 * Math.PI * Frequency / ProtocolConstants.SampleRate;
            if (_phase >= 2.0 * Math.PI)
            {
                _phase -= 2.0 * Math.PI;
            }

            var offset = frame * 4;
            BinaryPrimitives.WriteInt16LittleEndian(output.AsSpan(offset, 2), sample);
            BinaryPrimitives.WriteInt16LittleEndian(output.AsSpan(offset + 2, 2), sample);
        }

        return output;
    }
}
