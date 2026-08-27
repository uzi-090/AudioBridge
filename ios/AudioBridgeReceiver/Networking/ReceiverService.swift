import Foundation
import Network

protocol ReceiverServiceDelegate: AnyObject {
    func receiverServiceDidChangeState(_ state: ReceiverConnectionState)
    func receiverServiceDidUpdateMetrics(_ metrics: ReceiverMetrics)
    func receiverServiceDidChangeRoute(_ routeName: String)
    func receiverServiceDidLog(_ message: String)
}

final class ReceiverService {
    weak var delegate: ReceiverServiceDelegate?

    private let networkQueue = DispatchQueue(label: "com.audiobridge.network", qos: .userInitiated)
    private let audioSession = AudioSessionController()
    private var playbackEngine: PCMPlaybackEngine?
    private var connection: NWConnection?
    private var heartbeatTimer: DispatchSourceTimer?
    private var metricsTimer: DispatchSourceTimer?
    private var jitterBuffer = JitterBuffer(targetDepth: BufferPreset.balanced.targetPacketCount)
    private var pendingPlaybackData = Data()
    private var configuration: ReceiverConfiguration?
    private var metrics = ReceiverMetrics.zero
    private var packetsInCurrentSecond = 0
    private var lastPacketArrival: TimeInterval?
    private var lastValidPacketAt: TimeInterval = 0
    private var calculatedJitter: Double = 0
    private var hasAcknowledgement = false
    private var hasPlayedAudio = false
    private var helloAttempts = 0

    init() {
        audioSession.onRouteChanged = { [weak self] routeName in
            self?.notifyRoute(routeName)
        }
    }

    func connect(configuration: ReceiverConfiguration) {
        networkQueue.async { [weak self] in
            guard let self else { return }
            self.disconnectInternal(notify: false)
            self.configuration = configuration
            self.jitterBuffer = JitterBuffer(targetDepth: configuration.bufferPreset.targetPacketCount)
            self.metrics = .zero
            self.pendingPlaybackData.removeAll(keepingCapacity: true)
            self.hasAcknowledgement = false
            self.hasPlayedAudio = false
            self.helloAttempts = 0
            self.notifyState(.connecting)

            guard let port = NWEndpoint.Port(rawValue: configuration.port) else {
                self.notifyState(.failed("The Windows port number is invalid."))
                return
            }

            let connection = NWConnection(
                host: NWEndpoint.Host(configuration.host),
                port: port,
                using: .udp
            )
            self.connection = connection
            connection.stateUpdateHandler = { [weak self] state in
                self?.networkQueue.async {
                    self?.handleConnectionState(state)
                }
            }
            connection.start(queue: self.networkQueue)
        }
    }

    func updateBufferPreset(_ preset: BufferPreset) {
        networkQueue.async { [weak self] in
            self?.jitterBuffer.setTargetDepth(preset.targetPacketCount)
        }
    }

    func disconnect() {
        networkQueue.async { [weak self] in
            self?.disconnectInternal(notify: true)
        }
    }

    private func handleConnectionState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            log("UDP connection is ready.")
            sendHello()
            receiveNextMessage()
            startTimers()
        case .waiting(let error):
            log("Network is waiting: \(error.localizedDescription)")
            notifyState(.reconnecting)
        case .failed(let error):
            fail("Could not reach the Windows sender: \(error.localizedDescription)")
        case .cancelled:
            break
        default:
            break
        }
    }

    private func sendHello() {
        guard let configuration else { return }
        helloAttempts += 1
        let data = PacketCodec.encodeHello(
            pairingCode: configuration.pairingCode,
            preset: configuration.bufferPreset
        )
        send(data)
        log("Pairing request sent to \(configuration.host):\(configuration.port).")
    }

    private func send(_ data: Data) {
        connection?.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.networkQueue.async {
                    self?.log("Send failed: \(error.localizedDescription)")
                }
            }
        })
    }

    private func receiveNextMessage() {
        connection?.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            self.networkQueue.async {
                if let data {
                    self.handleIncoming(data)
                }
                if let error {
                    self.log("Receive error: \(error.localizedDescription)")
                }
                if self.connection != nil {
                    self.receiveNextMessage()
                }
            }
        }
    }

    private func handleIncoming(_ data: Data) {
        do {
            let packet = try PacketCodec.decode(data)
            lastValidPacketAt = ProcessInfo.processInfo.systemUptime
            switch packet.type {
            case .helloAcknowledgement:
                handleAcknowledgement()
            case .audio:
                handleAudio(packet)
            case .ping:
                send(PacketCodec.encode(type: .pong, timestamp: packet.timestamp))
            case .pong:
                break
            case .stop:
                notifyState(.waitingForAudio)
            case .hello:
                break
            }
        } catch {
            log("Ignored invalid packet: \(error.localizedDescription)")
        }
    }

    private func handleAcknowledgement() {
        guard !hasAcknowledgement else { return }
        hasAcknowledgement = true
        do {
            let engine = try PCMPlaybackEngine(audioSession: audioSession)
            try engine.start()
            playbackEngine = engine
            notifyRoute(audioSession.currentRouteName)
            notifyState(.waitingForAudio)
            log("Pairing accepted. Audio output is ready.")
        } catch {
            fail("The iPhone audio engine could not start: \(error.localizedDescription)")
        }
    }

    private func handleAudio(_ packet: AudioBridgePacket) {
        guard hasAcknowledgement else { return }

        let now = ProcessInfo.processInfo.systemUptime
        if let lastPacketArrival {
            let observedInterval = (now - lastPacketArrival) * 1_000
            let deviation = abs(observedInterval - Double(AudioBridgeProtocol.frameMilliseconds))
            calculatedJitter += (deviation - calculatedJitter) / 16
        }
        lastPacketArrival = now

        let inserted = jitterBuffer.push(
            BufferedAudioPacket(
                sequence: packet.sequence,
                timestamp: packet.timestamp,
                payload: packet.payload
            )
        )
        guard inserted else { return }

        metrics.packetsReceived += 1
        packetsInCurrentSecond += 1
        drainJitterBuffer()

        if !hasPlayedAudio {
            hasPlayedAudio = true
            notifyState(.playing)
            log("First audio packet is playing.")
        }
    }

    private func drainJitterBuffer() {
        let chunkBytes = AudioBridgeProtocol.audioPayloadSize * AudioBridgeProtocol.playbackChunkPackets
        while let packet = jitterBuffer.popReady() {
            pendingPlaybackData.append(packet.payload)
            while pendingPlaybackData.count >= chunkBytes {
                let chunk = pendingPlaybackData.prefix(chunkBytes)
                pendingPlaybackData.removeFirst(chunkBytes)
                playbackEngine?.enqueue(pcm16LittleEndian: Data(chunk))
            }
        }
    }

    private func startTimers() {
        heartbeatTimer?.cancel()
        let heartbeat = DispatchSource.makeTimerSource(queue: networkQueue)
        heartbeat.schedule(deadline: .now() + 2, repeating: 2)
        heartbeat.setEventHandler { [weak self] in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            self.send(PacketCodec.encode(type: .ping, timestamp: UInt64(now * 1_000)))
            if !self.hasAcknowledgement {
                if self.helloAttempts >= 3 {
                    self.fail("Windows did not accept the connection. Check the address, pairing code, and firewall.")
                } else {
                    self.sendHello()
                }
            } else if now - self.lastValidPacketAt > 6 {
                self.hasPlayedAudio = false
                self.notifyState(.reconnecting)
                self.sendHello()
            }
        }
        heartbeat.resume()
        heartbeatTimer = heartbeat

        metricsTimer?.cancel()
        let metricTimer = DispatchSource.makeTimerSource(queue: networkQueue)
        metricTimer.schedule(deadline: .now() + 1, repeating: 1)
        metricTimer.setEventHandler { [weak self] in
            self?.publishMetrics()
        }
        metricTimer.resume()
        metricsTimer = metricTimer
    }

    private func publishMetrics() {
        let snapshot = jitterBuffer.snapshot()
        metrics.packetsPerSecond = packetsInCurrentSecond
        metrics.packetsDropped = snapshot.droppedPackets
        metrics.packetsReordered = snapshot.reorderedPackets
        metrics.bufferDepth = snapshot.depth
        metrics.jitterMilliseconds = calculatedJitter
        metrics.estimatedLatencyMilliseconds = (configuration?.bufferPreset.targetMilliseconds ?? 0)
            + audioSession.outputLatencyMilliseconds
            + (AudioBridgeProtocol.frameMilliseconds * AudioBridgeProtocol.playbackChunkPackets)
        packetsInCurrentSecond = 0

        let metrics = metrics
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.receiverServiceDidUpdateMetrics(metrics)
        }
    }

    private func disconnectInternal(notify: Bool) {
        if hasAcknowledgement {
            send(PacketCodec.encode(type: .stop))
        }
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        metricsTimer?.cancel()
        metricsTimer = nil
        playbackEngine?.stop()
        playbackEngine = nil
        jitterBuffer.reset()
        pendingPlaybackData.removeAll(keepingCapacity: false)
        configuration = nil
        hasAcknowledgement = false
        hasPlayedAudio = false
        helloAttempts = 0
        lastPacketArrival = nil
        lastValidPacketAt = 0
        calculatedJitter = 0
        metrics = .zero
        packetsInCurrentSecond = 0
        if notify {
            notifyState(.idle)
            publishZeroMetrics()
            log("Disconnected.")
        }
    }

    private func fail(_ message: String) {
        log(message)
        disconnectInternal(notify: false)
        notifyState(.failed(message))
    }

    private func notifyState(_ state: ReceiverConnectionState) {
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.receiverServiceDidChangeState(state)
        }
    }

    private func notifyRoute(_ routeName: String) {
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.receiverServiceDidChangeRoute(routeName)
        }
    }

    private func publishZeroMetrics() {
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.receiverServiceDidUpdateMetrics(.zero)
        }
    }

    private func log(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.receiverServiceDidLog(message)
        }
    }
}
