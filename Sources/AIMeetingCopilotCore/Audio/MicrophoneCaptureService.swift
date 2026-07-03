import Foundation
import AVFoundation
import CoreMedia
import QuartzCore
import os.log

public enum MicrophoneCaptureError: Error {
    case inputUnavailable
}

/// Захват микрофона через AVCaptureSession.
///
/// Раньше здесь был AVAudioEngine.inputNode — но на некоторых Mac (в т.ч.
/// когда система создаёт CADefaultDeviceAggregate для эхоподавления) он
/// отдаёт сигнал в ~700 раз тише реального (RMS ~0.0008 против ~0.57 через
/// AVCaptureSession на том же микрофоне). Apple Speech при таком уровне
/// считает вход тишиной и роняет распознавание ошибкой 1110 по кругу.
/// AVCaptureSession читает физический микрофон напрямую и даёт нормальный
/// уровень без всяких программных усилений.
public final class MicrophoneCaptureService: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    public var onMicEvent: ((MicEvent) -> Void)?
    public var onAudioLevel: ((AudioLevelEvent) -> Void)?
    /// Callback для передачи аудио-буферов в SpeechASRProvider.
    public var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

    private static let log = Logger(subsystem: "ai.meeting.copilot", category: "MicCapture")
    private let seqGenerator: SequenceNumberGenerator
    private let formatWatchdog = AudioFormatWatchdog()
    // Свежий AVCaptureSession на каждый старт — переиспользование одного
    // экземпляра могло сохранять voice-processing состояние между сессиями.
    private var session: AVCaptureSession?
    private let sampleQueue = DispatchQueue(label: "ai.meeting.copilot.mic-capture")

    // Целевой формат для Speech и записи: 48kHz mono Float32.
    private let targetSampleRate: Double = 48_000
    private var pcmFormat: AVAudioFormat?

    private var sampleClock = SampleClock()
    private var vad = EnergyVAD()
    private var isRunning = false

    public init(seqGenerator: SequenceNumberGenerator = SequenceNumberGenerator()) {
        self.seqGenerator = seqGenerator
        super.init()
        formatWatchdog.onFormatChanged = { format in
            print("[AudioFormatWatchdog] Microphone format changed: \(format.sampleRate) Hz, \(format.channelCount)ch")
        }
    }

    public func startCapture(sessionStartTime: TimeInterval = CACurrentMediaTime()) throws {
        guard !isRunning else { return }

        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw MicrophoneCaptureError.inputUnavailable
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw MicrophoneCaptureError.inputUnavailable
        }

        seqGenerator.reset()
        sampleClock = SampleClock(sessionStartTime: sessionStartTime)
        vad = EnergyVAD()

        Self.log.notice("mic device: \(device.localizedName, privacy: .public) uid=\(device.uniqueID, privacy: .public)")
        if #available(macOS 12.0, *) {
            Self.log.notice("mic mode active=\(AVCaptureDevice.activeMicrophoneMode.rawValue, privacy: .public) preferred=\(AVCaptureDevice.preferredMicrophoneMode.rawValue, privacy: .public)")
        }

        let newSession = AVCaptureSession()
        guard newSession.canAddInput(input) else {
            throw MicrophoneCaptureError.inputUnavailable
        }
        newSession.addInput(input)

        let audioOut = AVCaptureAudioDataOutput()
        // Никаких audioSettings — берём НАТИВНЫЙ формат устройства (Int16 mono
        // на встроенном микрофоне). Именно так проверенный тест дал RMS ~0.57.
        audioOut.setSampleBufferDelegate(self, queue: sampleQueue)
        guard newSession.canAddOutput(audioOut) else {
            throw MicrophoneCaptureError.inputUnavailable
        }
        newSession.addOutput(audioOut)

        newSession.startRunning()
        session = newSession
        isRunning = true
    }

    public func stopCapture() {
        guard isRunning else { return }
        session?.stopRunning()
        session = nil
        isRunning = false
    }

    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let buffer = Self.pcmBuffer(from: sampleBuffer) else { return }
        handleBuffer(buffer)
    }

    /// Конвертирует CMSampleBuffer из AVCaptureAudioDataOutput в
    /// AVAudioPCMBuffer (Float32 mono), который ест SpeechASRProvider и
    /// AudioRecorder. Формат источника читаем из самого sample buffer —
    /// обычно Int16 на встроенном микрофоне.
    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let fmtDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc) else { return nil }
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0 else { return nil }
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }

        var lengthAtOffset = 0
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer) == kCMBlockBufferNoErr,
              let dataPointer else { return nil }

        let sampleRate = asbd.pointee.mSampleRate
        let srcChannels = Int(asbd.pointee.mChannelsPerFrame)
        let isFloat = (asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isNonInterleaved = (asbd.pointee.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let bitsPerChannel = Int(asbd.pointee.mBitsPerChannel)

        // КРИТИЧНО: при non-interleaved формате каналы лежат сплошными
        // блоками (LLLL...RRRR), а не перемежаются (LRLR...). Чтение с шагом
        // i*srcChannels на non-interleaved пропускало каждый второй сэмпл —
        // речь получалась «ускоренной» вдвое, и Speech отвечал вечным 1110
        // "no speech". Доказано перекодировкой записи: данные, подписанные
        // 48kHz, распознаются только как 24kHz.
        let stride = (isNonInterleaved || srcChannels == 1) ? 1 : srcChannels

        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let pcm = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(frames)) else { return nil }
        pcm.frameLength = AVAudioFrameCount(frames)
        guard let dst = pcm.floatChannelData?[0] else { return nil }

        // Разбираем нативный формат в Float32 mono (берём первый канал).
        if isFloat && bitsPerChannel == 32 {
            let src = dataPointer.withMemoryRebound(to: Float.self, capacity: frames * stride) { $0 }
            for i in 0..<frames { dst[i] = src[i * stride] }
        } else if !isFloat && bitsPerChannel == 16 {
            let src = dataPointer.withMemoryRebound(to: Int16.self, capacity: frames * stride) { $0 }
            let scale: Float = 1.0 / 32768.0
            for i in 0..<frames { dst[i] = Float(src[i * stride]) * scale }
        } else if !isFloat && bitsPerChannel == 32 {
            let src = dataPointer.withMemoryRebound(to: Int32.self, capacity: frames * stride) { $0 }
            let scale: Float = 1.0 / 2_147_483_648.0
            for i in 0..<frames { dst[i] = Float(src[i * stride]) * scale }
        } else {
            return nil
        }

        // Санитайзинг: первые буферы сессии иногда приходят с мусором
        // (значения ~1e20 в WAV-записи, max_volume 0 dB). Мусор уходил и в
        // Speech, и в запись. NaN → 0, всё прочее клэмпим в [-1, 1].
        for i in 0..<frames {
            let v = dst[i]
            if v.isNaN || v.isInfinite {
                dst[i] = 0
            } else if v > 1.0 {
                dst[i] = 1.0
            } else if v < -1.0 {
                dst[i] = -1.0
            }
        }
        return pcm
    }

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        formatWatchdog.observe(format: buffer.format)

        // Чистый сигнал напрямую в ASR — никаких программных усилений не нужно,
        // AVCaptureSession даёт нормальный уровень.
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
