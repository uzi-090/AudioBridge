import XCTest
@testable import AudioBridgeReceiver

final class JitterBufferTests: XCTestCase {
    func testPrimesAtTargetDepthAndPopsInSequenceOrder() {
        let buffer = JitterBuffer(targetDepth: 3)
        let payload = Data(repeating: 1, count: AudioBridgeProtocol.audioPayloadSize)

        buffer.push(BufferedAudioPacket(sequence: 12, timestamp: 12, payload: payload))
        buffer.push(BufferedAudioPacket(sequence: 10, timestamp: 10, payload: payload))
        XCTAssertNil(buffer.popReady())
        buffer.push(BufferedAudioPacket(sequence: 11, timestamp: 11, payload: payload))

        XCTAssertEqual(buffer.popReady()?.sequence, 10)
        XCTAssertEqual(buffer.popReady()?.sequence, 11)
        XCTAssertEqual(buffer.popReady()?.sequence, 12)
    }

    func testDuplicatePacketIsRejected() {
        let buffer = JitterBuffer(targetDepth: 2)
        let packet = BufferedAudioPacket(
            sequence: 1,
            timestamp: 1,
            payload: Data(repeating: 0, count: AudioBridgeProtocol.audioPayloadSize)
        )

        XCTAssertTrue(buffer.push(packet))
        XCTAssertFalse(buffer.push(packet))
    }
}

