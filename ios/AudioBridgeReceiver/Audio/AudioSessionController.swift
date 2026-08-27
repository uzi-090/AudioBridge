import AVFAudio
import Foundation

final class AudioSessionController {
    private let session = AVAudioSession.sharedInstance()
    private var routeObserver: NSObjectProtocol?

    var onRouteChanged: ((String) -> Void)?

    init() {
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.onRouteChanged?(self.currentRouteName)
        }
    }

    deinit {
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
        }
    }

    func activate() throws {
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setPreferredSampleRate(Double(AudioBridgeProtocol.sampleRate))
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
        onRouteChanged?(currentRouteName)
    }

    func deactivate() {
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    var currentRouteName: String {
        guard let output = session.currentRoute.outputs.first else {
            return "No output route"
        }
        return output.portName
    }

    var outputLatencyMilliseconds: Int {
        Int((session.outputLatency + session.ioBufferDuration) * 1_000)
    }
}

