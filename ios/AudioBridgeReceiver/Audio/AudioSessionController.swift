import AVFAudio
import Foundation

final class AudioSessionController {
    private let session = AVAudioSession.sharedInstance()
    private var routeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var mediaServicesResetObserver: NSObjectProtocol?

    var onRouteChanged: ((String) -> Void)?
    var onInterruptionEnded: (() -> Void)?
    var onMediaServicesReset: (() -> Void)?

    init() {
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.onRouteChanged?(self.currentRouteName)
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            guard
                let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                AVAudioSession.InterruptionType(rawValue: rawValue) == .ended
            else {
                return
            }
            self?.onInterruptionEnded?()
        }

        mediaServicesResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.onMediaServicesReset?()
        }
    }

    deinit {
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
        }
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let mediaServicesResetObserver {
            NotificationCenter.default.removeObserver(mediaServicesResetObserver)
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
