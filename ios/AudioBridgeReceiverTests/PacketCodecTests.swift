import XCTest
@testable import AudioBridgeReceiver

final class PacketCodecTests: XCTestCase {
    func testAudioPacketRoundTrip() throws {
        let payload = Data(repeating: 0x5A, count: AudioBridgeProtocol.audioPayloadSize)
        let encoded = PacketCodec.encode(
            type: .audio,
            flags: 7,
            sequence: 42,
            timestamp: 12_345,
            payload: payload
        )

        let decoded = try PacketCodec.decode(encoded)

        XCTAssertEqual(decoded.type, .audio)
        XCTAssertEqual(decoded.flags, 7)
        XCTAssertEqual(decoded.sequence, 42)
        XCTAssertEqual(decoded.timestamp, 12_345)
        XCTAssertEqual(decoded.payload, payload)
    }

    func testRejectsInvalidMagic() {
        var data = PacketCodec.encode(type: .ping)
        data[0] = 0

        XCTAssertThrowsError(try PacketCodec.decode(data)) { error in
            XCTAssertEqual(error as? PacketCodecError, .invalidMagic)
        }
    }

    func testHelloPacketMatchesCrossPlatformKnownVector() {
        let encoded = PacketCodec.encodeHello(pairingCode: "043921", preset: .balanced)
        let hex = encoded.map { String(format: "%02X", $0) }.joined()

        XCTAssertEqual(
            hex,
            "41425231010100000000000000000000000000000000BB800205000A06303433393231"
        )
    }

    func testRejectsWrongAudioPayloadSize() {
        let encoded = PacketCodec.encode(type: .audio, payload: Data(repeating: 0, count: 12))

        XCTAssertThrowsError(try PacketCodec.decode(encoded)) { error in
            XCTAssertEqual(error as? PacketCodecError, .invalidPayload)
        }
    }
}
