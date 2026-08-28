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

    func testRecoversFromMissingPacketOnceBufferRefills() {
        let buffer = JitterBuffer(targetDepth: 2)
        let payload = Data(repeating: 0, count: AudioBridgeProtocol.audioPayloadSize)

        for sequence in [10, 11, 13, 14, 15, 16] {
            buffer.push(BufferedAudioPacket(sequence: UInt32(sequence), timestamp: UInt64(sequence), payload: payload))
        }

        XCTAssertEqual(buffer.popReady()?.sequence, 10)
        XCTAssertEqual(buffer.popReady()?.sequence, 11)
        XCTAssertEqual(buffer.popReady()?.sequence, 13)
        XCTAssertEqual(buffer.snapshot().droppedPackets, 1)
    }

    func testRecoversFromConsecutiveMissingPacketsInOneStep() {
        let buffer = JitterBuffer(targetDepth: 2)
        let payload = Data(repeating: 0, count: AudioBridgeProtocol.audioPayloadSize)

        for sequence in [20, 21, 25, 26, 27, 28] {
            buffer.push(BufferedAudioPacket(sequence: UInt32(sequence), timestamp: UInt64(sequence), payload: payload))
        }

        XCTAssertEqual(buffer.popReady()?.sequence, 20)
        XCTAssertEqual(buffer.popReady()?.sequence, 21)
        XCTAssertEqual(buffer.popReady()?.sequence, 25)
        XCTAssertEqual(buffer.snapshot().droppedPackets, 3)
    }
}
