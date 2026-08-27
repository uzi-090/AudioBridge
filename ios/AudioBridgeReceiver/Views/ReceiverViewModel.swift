import Combine
import Foundation

final class ReceiverViewModel: ObservableObject {
    @Published var host: String
    @Published var port: String
    @Published var pairingCode: String = ""
    @Published var bufferPreset: BufferPreset = .balanced
    @Published private(set) var state: ReceiverConnectionState = .idle
    @Published private(set) var metrics: ReceiverMetrics = .zero
    @Published private(set) var outputRoute: String = "iPhone output"
    @Published private(set) var logs: [String] = []
    @Published var validationMessage: String?

    private let service: ReceiverService
    private let defaults = UserDefaults.standard

    init(service: ReceiverService = ReceiverService()) {
        self.service = service
        self.host = defaults.string(forKey: "lastWindowsHost") ?? "192.168.1.2"
        self.port = defaults.string(forKey: "lastWindowsPort") ?? "43120"
        service.delegate = self
    }

    var primaryButtonTitle: String {
        state.isConnected || state == .connecting ? "Disconnect" : "Connect"
    }

    var primaryButtonSymbol: String {
        state.isConnected || state == .connecting ? "stop.fill" : "play.fill"
    }

    func primaryAction() {
        if state.isConnected || state == .connecting {
            service.disconnect()
        } else {
            connect()
        }
    }

    func connect() {
        validationMessage = nil
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCode = pairingCode.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanHost.isEmpty else {
            validationMessage = "Enter the Windows address shown by the sender."
            return
        }
        guard let parsedPort = UInt16(port), parsedPort > 0 else {
            validationMessage = "Enter a port between 1 and 65535."
            return
        }
        guard cleanCode.count == 6, cleanCode.allSatisfy(\.isNumber) else {
            validationMessage = "Enter the six-digit pairing code from Windows."
            return
        }

        defaults.set(cleanHost, forKey: "lastWindowsHost")
        defaults.set(String(parsedPort), forKey: "lastWindowsPort")
        service.connect(
            configuration: ReceiverConfiguration(
                host: cleanHost,
                port: parsedPort,
                pairingCode: cleanCode,
                bufferPreset: bufferPreset
            )
        )
    }

    func selectBufferPreset(_ preset: BufferPreset) {
        bufferPreset = preset
        service.updateBufferPreset(preset)
    }
}

extension ReceiverViewModel: ReceiverServiceDelegate {
    func receiverServiceDidChangeState(_ state: ReceiverConnectionState) {
        self.state = state
    }

    func receiverServiceDidUpdateMetrics(_ metrics: ReceiverMetrics) {
        self.metrics = metrics
    }

    func receiverServiceDidChangeRoute(_ routeName: String) {
        outputRoute = routeName
    }

    func receiverServiceDidLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        logs.insert("\(formatter.string(from: Date()))  \(message)", at: 0)
        if logs.count > 30 {
            logs.removeLast(logs.count - 30)
        }
    }
}
