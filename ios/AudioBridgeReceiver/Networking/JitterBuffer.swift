import Foundation

struct BufferedAudioPacket: Equatable {
    let sequence: UInt32
    let timestamp: UInt64
    let payload: Data
}

struct JitterBufferSnapshot: Equatable {
    let depth: Int
    let droppedPackets: UInt64
    let reorderedPackets: UInt64
    let isPrimed: Bool
}

final class JitterBuffer {
    private let lock = NSLock()
    private var packets: [UInt32: BufferedAudioPacket] = [:]
    private var expectedSequence: UInt32?
    private var highestReceivedSequence: UInt32?
    private var primed = false
    private var droppedPackets: UInt64 = 0
    private var reorderedPackets: UInt64 = 0
    private var targetDepth: Int

    init(targetDepth: Int) {
        self.targetDepth = max(2, targetDepth)
    }

    func setTargetDepth(_ targetDepth: Int) {
        lock.withAudioBridgeLock {
            self.targetDepth = max(2, targetDepth)
        }
    }

    @discardableResult
    func push(_ packet: BufferedAudioPacket) -> Bool {
        lock.withAudioBridgeLock {
            guard packets[packet.sequence] == nil else { return false }

            if let highestReceivedSequence, packet.sequence < highestReceivedSequence {
                reorderedPackets += 1
            }
            if highestReceivedSequence == nil || packet.sequence > highestReceivedSequence! {
                highestReceivedSequence = packet.sequence
            }

            packets[packet.sequence] = packet
            if !primed && packets.count >= targetDepth {
                expectedSequence = packets.keys.min()
                primed = true
            }
            return true
        }
    }

    func popReady() -> BufferedAudioPacket? {
        lock.withAudioBridgeLock {
            guard primed, let expected = expectedSequence else { return nil }

            if let packet = packets.removeValue(forKey: expected) {
                expectedSequence = expected &+ 1
                return packet
            }

            let skipThreshold = targetDepth + 2
            guard packets.count >= skipThreshold else { return nil }

            guard let nextSequence = packets.keys.min(by: {
                ($0 &- expected) < ($1 &- expected)
            }) else { return nil }

            let skipped = nextSequence &- expected
            guard skipped < UInt32.max / 2 else { return nil }
            droppedPackets += UInt64(skipped)
            expectedSequence = nextSequence &+ 1
            return packets.removeValue(forKey: nextSequence)
        }
    }

    func snapshot() -> JitterBufferSnapshot {
        lock.withAudioBridgeLock {
            JitterBufferSnapshot(
                depth: packets.count,
                droppedPackets: droppedPackets,
                reorderedPackets: reorderedPackets,
                isPrimed: primed
            )
        }
    }

    func reset() {
        lock.withAudioBridgeLock {
            packets.removeAll(keepingCapacity: true)
            expectedSequence = nil
            highestReceivedSequence = nil
            primed = false
            droppedPackets = 0
            reorderedPackets = 0
        }
    }
}

private extension NSLock {
    func withAudioBridgeLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
