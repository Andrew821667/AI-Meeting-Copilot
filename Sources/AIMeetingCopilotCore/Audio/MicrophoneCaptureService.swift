import Foundation
import AVFoundation
import QuartzCore

public enum MicrophoneCaptureError: Error {
    case inputUnavailable
}

public final class MicrophoneCaptureService {
    public var onMicEvent: ((MicEvent) -> Void)?
    public var onAudioLevel: ((AudioLevelEvent) -> Void)?
    /// Callback для передачи аудио-буферов в SpeechASRProvider
    public var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

    private let engine = AVAudioEngine()
    private let seqGenerator: SequenceNumberGenerator
    private let formatWatchdog = AudioFormatWatchdog()

    private var sampleClock = SampleClock()
    private var vad = EnergyVAD()
    private var isRunning = false

    public init(seqGenerator: SequenceNumberGenerator = SequenceNumberGenerator()) {
        self.seqGenerator = seqGenerator
        formatWatchdog.onFormatChanged = { format in
            print("[AudioFormatWatchdog] Microphone format changed: \(format.sampleRate) Hz, \(format.channelCount)ch")
        }
    }

    public func startCapture(sessionStartTime: TimeInterval = CACurrentMediaTime()) throws {
        guard !isRunning else { return }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            throw MicrophoneCaptureError.inputUnavailable
        }

        seqGenerator.reset()
        sampleClock = SampleClock(sessionStartTime: sessionStartTime)
        vad = EnergyVAD()

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.handleBuffer(buffer)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    public func stopCapture() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        formatWatchdog.observe(format: buffer.format)

        // Передаём буфер в ASR-провайдер для распознавания речи
        onAudioBuffer?(buffer)

        let rms = Self.calculateRMS(buffer: buffer)
        let timestamp = sampleClock.advance(frames: Int(buffer.frameLength), sampleRate: buffer.format.sampleRate) - sampleClock.sessionStartTime

        let levelEvent = AudioLevelEvent(
            seq: seqGenerator.next(),
            timestamp: timestamp,
            micRms: rms,
            systemRms: 0
        )
        onAudioLevel?(levelEvent)

        guard let eventType = vad.process(rms: rms, timestamp: timestamp) else { return }

        let duration = eventType == .speechEnd ? vad.currentSpeechDuration(at: timestamp) : 0
        let event = MicEvent(
            seq: seqGenerator.next(),
            eventType: eventType,
            timestamp: timestamp,
            confidence: min(max(rms * 5, 0), 1),
            duration: duration
        )
        onMicEvent?(event)
    }

    private static func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0, channelCount > 0 else { return 0 }

        var sum: Float = 0
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            var channelSum: Float = 0
            for i in 0..<frameLength {
                let sample = samples[i]
                channelSum += sample * sample
            }
            sum += channelSum / Float(frameLength)
        }

        let mean = sum / Float(channelCount)
        return sqrt(mean)
    }
}
