import Foundation

struct ReceiverMetrics: Equatable {
    var packetsReceived: UInt64 = 0
    var packetsDropped: UInt64 = 0
    var packetsReordered: UInt64 = 0
    var packetsPerSecond: Int = 0
    var jitterMilliseconds: Double = 0
    var bufferDepth: Int = 0
    var estimatedLatencyMilliseconds: Int = 0

    static let zero = ReceiverMetrics()
}

