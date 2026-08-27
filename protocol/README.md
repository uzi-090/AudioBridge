# AudioBridge protocol v1

AudioBridge v1 uses one authenticated UDP session on the local network. Audio is uncompressed stereo PCM so the first version has no native codec dependency and is easy to diagnose.

## Audio format

- 48,000 samples/second
- 2 channels, interleaved stereo
- signed 16-bit little-endian samples
- 5 ms per datagram (240 frames)
- 960 audio payload bytes per datagram
- approximately 1.54 Mbit/s of audio payload, or about 1.6 Mbit/s including headers

All multi-byte header and control-payload numbers use network byte order (big-endian). Only PCM sample bytes are little-endian.

## Datagram header

Every datagram starts with this 20-byte header:

| Offset | Size | Field | Value |
|---:|---:|---|---|
| 0 | 4 | Magic | `0x41425231` (`ABR1`) |
| 4 | 1 | Version | `1` |
| 5 | 1 | Type | See below |
| 6 | 2 | Flags | Reserved; `0` in v1 |
| 8 | 4 | Sequence | Packet sequence number |
| 12 | 8 | Timestamp | Source frame timestamp |
| 20 | n | Payload | Type-specific |

Packet types are `HELLO=1`, `ACK=2`, `AUDIO=3`, `PING=4`, `PONG=5`, and `STOP=6`.

## Pairing

The iPhone sends `HELLO` with this payload:

| Offset | Size | Field |
|---:|---:|---|
| 0 | 4 | Sample rate |
| 4 | 1 | Channel count |
| 5 | 1 | Frame duration in ms |
| 6 | 2 | Requested jitter-buffer packet count |
| 8 | 1 | UTF-8 pairing-code length |
| 9 | n | Pairing code |

Windows validates the six-digit code and audio format, remembers the sender endpoint, then returns `ACK`. The code prevents accidental local connections; v1 is not encrypted and must not be exposed to the public internet.

## Audio and liveness

`AUDIO` contains exactly 960 bytes. Windows keeps sequence and timestamp counters monotonic while switching sources. The iPhone reorders packets in a bounded jitter buffer and schedules four packets (20 ms) per AVAudioEngine buffer.

Either peer can send `PING`; the other returns `PONG`. `STOP` indicates an intentional disconnect.
