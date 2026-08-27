import Foundation

enum ReceiverConnectionState: Equatable {
    case idle
    case connecting
    case waitingForAudio
    case playing
    case reconnecting
    case failed(String)

    var title: String {
        switch self {
        case .idle: "Ready to connect"
        case .connecting: "Connecting"
        case .waitingForAudio: "Connected - waiting for audio"
        case .playing: "Listening"
        case .reconnecting: "Reconnecting"
        case .failed: "Connection failed"
        }
    }

    var detail: String {
        switch self {
        case .idle:
            "Enter the address and pairing code shown on the Windows app."
        case .connecting:
            "Contacting the Windows sender on your local network."
        case .waitingForAudio:
            "Start playback on Windows or confirm the sender is not muted."
        case .playing:
            "Windows audio is being routed through this iPhone."
        case .reconnecting:
            "The connection was interrupted. AudioBridge is retrying."
        case .failed(let message):
            message
        }
    }

    var symbolName: String {
        switch self {
        case .idle: "wave.3.right"
        case .connecting, .reconnecting: "arrow.triangle.2.circlepath"
        case .waitingForAudio: "hourglass"
        case .playing: "waveform"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var isConnected: Bool {
        switch self {
        case .waitingForAudio, .playing, .reconnecting: true
        default: false
        }
    }
}

