import Foundation

enum BufferPreset: String, CaseIterable, Identifiable {
    case lowDelay = "Low Delay"
    case balanced = "Balanced"
    case stable = "Stable"

    var id: String { rawValue }

    var targetPacketCount: Int {
        switch self {
        case .lowDelay: 6
        case .balanced: 10
        case .stable: 18
        }
    }

    var targetMilliseconds: Int {
        targetPacketCount * AudioBridgeProtocol.frameMilliseconds
    }

    var explanation: String {
        switch self {
        case .lowDelay:
            "Small buffer for clean 5 GHz Wi-Fi."
        case .balanced:
            "Recommended balance of delay and stability."
        case .stable:
            "More protection against congested Wi-Fi."
        }
    }
}

