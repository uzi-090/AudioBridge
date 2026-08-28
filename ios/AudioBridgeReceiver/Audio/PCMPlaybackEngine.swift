import AVFAudio
import Foundation

enum PCMPlaybackError: LocalizedError {
    case formatUnavailable
    case bufferAllocationFailed

    var errorDescription: String? {
        switch self {
        case .formatUnavailable: "The iPhone could not create the required 48 kHz stereo audio format."
        case .bufferAllocationFailed: "The iPhone could not allocate an audio playback buffer."
        }
    }
}

final class PCMPlaybackEngine {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let queue = DispatchQueue(label: "com.audiobridge.playback", qos: .userInteractive)
    private let audioSession: AudioSessionController
    private let format: AVAudioFormat
    private var isConfigured = false
    private var scheduledBufferCount = 0
    private var playbackGeneration: UInt64 = 0

    init(audioSession: AudioSessionController) throws {
        self.audioSession = audioSession
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(AudioBridgeProtocol.sampleRate),
            channels: AVAudioChannelCount(AudioBridgeProtocol.channelCount),
            interleaved: false
        ) else {
            throw PCMPlaybackError.formatUnavailable
        }
        self.format = format
    }

    func start() throws {
        guard !isConfigured else { return }
        try audioSession.activate()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        isConfigured = true
    }

    func enqueue(pcm16LittleEndian data: Data) {
        queue.async { [weak self] in
            guard let self, self.isConfigured else { return }
            let bytesPerFrame = Int(AudioBridgeProtocol.channelCount) * AudioBridgeProtocol.bytesPerSample
            let frameCount = data.count / bytesPerFrame
            guard
                frameCount > 0,
                let buffer = AVAudioPCMBuffer(
                    pcmFormat: self.format,
                    frameCapacity: AVAudioFrameCount(frameCount)
                ),
                let channels = buffer.floatChannelData
            else {
                return
            }

            buffer.frameLength = AVAudioFrameCount(frameCount)
            data.withUnsafeBytes { rawBuffer in
                guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
                for frame in 0..<frameCount {
                    let sourceOffset = frame * bytesPerFrame
                    for channel in 0..<Int(AudioBridgeProtocol.channelCount) {
                        let sampleOffset = sourceOffset + channel * 2
                        let sampleBits = UInt16(bytes[sampleOffset]) | (UInt16(bytes[sampleOffset + 1]) << 8)
                        let sample = Int16(bitPattern: sampleBits)
                        channels[channel][frame] = Float(sample) / Float(Int16.max)
                    }
                }
            }

            self.scheduledBufferCount += 1
            let generation = self.playbackGeneration
            self.playerNode.scheduleBuffer(buffer) { [weak self] in
                self?.queue.async { [weak self] in
                    guard let self, self.playbackGeneration == generation else { return }
                    self.scheduledBufferCount = max(0, self.scheduledBufferCount - 1)
                }
            }
            if !self.playerNode.isPlaying {
                self.playerNode.play()
            }
        }
    }

    func needsRecovery(maxScheduledBuffers: Int) -> Bool {
        queue.sync {
            guard isConfigured else { return false }
            return scheduledBufferCount > maxScheduledBuffers
                || (scheduledBufferCount > 0 && !playerNode.isPlaying)
        }
    }

    func stop() {
        queue.sync {
            playbackGeneration &+= 1
            scheduledBufferCount = 0
            playerNode.stop()
            if engine.isRunning {
                engine.stop()
            }
            if isConfigured {
                engine.disconnectNodeOutput(playerNode)
                engine.detach(playerNode)
            }
            isConfigured = false
            audioSession.deactivate()
        }
    }
}
