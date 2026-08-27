import Foundation

enum AudioBridgeProtocol {
    static let magic: UInt32 = 0x41425231
    static let version: UInt8 = 1
    static let headerSize = 20
    static let sampleRate: UInt32 = 48_000
    static let channelCount: UInt8 = 2
    static let frameMilliseconds = 5
    static let framesPerPacket = 240
    static let bytesPerSample = 2
    static let audioPayloadSize = framesPerPacket * Int(channelCount) * bytesPerSample
    static let playbackChunkPackets = 4
}

enum AudioBridgePacketType: UInt8 {
    case hello = 1
    case helloAcknowledgement = 2
    case audio = 3
    case ping = 4
    case pong = 5
    case stop = 6
}

struct AudioBridgePacket: Equatable {
    let type: AudioBridgePacketType
    let flags: UInt16
    let sequence: UInt32
    let timestamp: UInt64
    let payload: Data
}

enum PacketCodecError: LocalizedError, Equatable {
    case packetTooShort
    case invalidMagic
    case unsupportedVersion(UInt8)
    case unknownPacketType(UInt8)
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .packetTooShort: "The received network packet was incomplete."
        case .invalidMagic: "The packet did not come from AudioBridge."
        case .unsupportedVersion(let version): "Protocol version \(version) is not supported."
        case .unknownPacketType(let type): "Packet type \(type) is not supported."
        case .invalidPayload: "The packet payload was invalid."
        }
    }
}

enum PacketCodec {
    static func encode(
        type: AudioBridgePacketType,
        flags: UInt16 = 0,
        sequence: UInt32 = 0,
        timestamp: UInt64 = 0,
        payload: Data = Data()
    ) -> Data {
        var data = Data(capacity: AudioBridgeProtocol.headerSize + payload.count)
        data.appendBigEndian(AudioBridgeProtocol.magic)
        data.append(AudioBridgeProtocol.version)
        data.append(type.rawValue)
        data.appendBigEndian(flags)
        data.appendBigEndian(sequence)
        data.appendBigEndian(timestamp)
        data.append(payload)
        return data
    }

    static func encodeHello(pairingCode: String, preset: BufferPreset) -> Data {
        let token = Data(pairingCode.utf8.prefix(32))
        var payload = Data(capacity: 9 + token.count)
        payload.appendBigEndian(AudioBridgeProtocol.sampleRate)
        payload.append(AudioBridgeProtocol.channelCount)
        payload.append(UInt8(AudioBridgeProtocol.frameMilliseconds))
        payload.appendBigEndian(UInt16(preset.targetPacketCount))
        payload.append(UInt8(token.count))
        payload.append(token)
        return encode(type: .hello, payload: payload)
    }

    static func decode(_ data: Data) throws -> AudioBridgePacket {
        guard data.count >= AudioBridgeProtocol.headerSize else {
            throw PacketCodecError.packetTooShort
        }
        guard let magic = data.readUInt32BigEndian(at: 0), magic == AudioBridgeProtocol.magic else {
            throw PacketCodecError.invalidMagic
        }
        let version = data[4]
        guard version == AudioBridgeProtocol.version else {
            throw PacketCodecError.unsupportedVersion(version)
        }
        guard let type = AudioBridgePacketType(rawValue: data[5]) else {
            throw PacketCodecError.unknownPacketType(data[5])
        }
        guard
            let flags = data.readUInt16BigEndian(at: 6),
            let sequence = data.readUInt32BigEndian(at: 8),
            let timestamp = data.readUInt64BigEndian(at: 12)
        else {
            throw PacketCodecError.packetTooShort
        }

        let payload = data.subdata(in: AudioBridgeProtocol.headerSize..<data.count)
        if type == .audio && payload.count != AudioBridgeProtocol.audioPayloadSize {
            throw PacketCodecError.invalidPayload
        }

        return AudioBridgePacket(
            type: type,
            flags: flags,
            sequence: sequence,
            timestamp: timestamp,
            payload: payload
        )
    }
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt16) {
        var encoded = value.bigEndian
        Swift.withUnsafeBytes(of: &encoded) { append(contentsOf: $0) }
    }

    mutating func appendBigEndian(_ value: UInt32) {
        var encoded = value.bigEndian
        Swift.withUnsafeBytes(of: &encoded) { append(contentsOf: $0) }
    }

    mutating func appendBigEndian(_ value: UInt64) {
        var encoded = value.bigEndian
        Swift.withUnsafeBytes(of: &encoded) { append(contentsOf: $0) }
    }

    func readUInt16BigEndian(at offset: Int) -> UInt16? {
        guard offset >= 0, count >= offset + 2 else { return nil }
        return (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
    }

    func readUInt32BigEndian(at offset: Int) -> UInt32? {
        guard offset >= 0, count >= offset + 4 else { return nil }
        return (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
    }

    func readUInt64BigEndian(at offset: Int) -> UInt64? {
        guard offset >= 0, count >= offset + 8 else { return nil }
        var result: UInt64 = 0
        for index in 0..<8 {
            result = (result << 8) | UInt64(self[offset + index])
        }
        return result
    }
}

