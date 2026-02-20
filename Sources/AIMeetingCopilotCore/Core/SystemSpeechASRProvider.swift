import Foundation
import Speech
import QuartzCore
import CoreMedia

#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

private final class RecognitionRequestBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    func append(sampleBuffer: CMSampleBuffer) {
        lock.lock()
        let request = self.request
        lock.unlock()
        request?.appendAudioSampleBuffer(sampleBuffer)
    }
}

public enum SystemSpeechASRError: LocalizedError {
    case unsupportedOS
    case recognizerUnavailable
    case authorizationDenied
    case sourceUnavailable
    case startCaptureFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "Для онлайн-транскрипции собеседника нужен macOS 13+."
        case .recognizerUnavailable:
            return "Локальный распознаватель речи недоступен."
        case .authorizationDenied:
            return "Нет доступа к распознаванию речи. Разрешите его в Настройках macOS."
        case .sourceUnavailable:
            return "Не удалось получить источник системного аудио."
        case .startCaptureFailed(let reason):
            return "Не удалось запустить захват системного аудио: \(reason)"
        }
    }
}

@MainActor
public final class SystemSpeechASRProvider: ASRProvider {
    public var segments: AsyncStream<TranscriptSegment> {
        stream
    }

    private let stream: AsyncStream<TranscriptSegment>
    private var continuation: AsyncStream<TranscriptSegment>.Continuation?
    private let seqGenerator = SequenceNumberGenerator(startAt: 80_000)
    private let requestBridge = RecognitionRequestBridge()

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let recognizer: SFSpeechRecognizer?
    private var systemInput: ScreenAudioInput?
    private var isRestartingRecognition = false

    /// Callback для получения сырого CMSampleBuffer системного аудио (для записи и диаризации).
    public var onRawSystemAudioBuffer: (@Sendable (CMSampleBuffer) -> Void)?

    private var startedAt: TimeInterval = 0
    private var currentUtteranceID = UUID().uuidString
    private var lastFinalTs: Double = 0
    private var lastPartialText: String = ""
    private var isRunning = false

    public init(localeIdentifier: String = "ru-RU") {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        var continuationRef: AsyncStream<TranscriptSegment>.Continuation?
        stream = AsyncStream { continuation in
            continuationRef = continuation
        }
        continuation = continuationRef
    }

    public func startStream() async throws {
        await stopInternal()

        guard #available(macOS 13.0, *) else {
            throw SystemSpeechASRError.unsupportedOS
        }

        guard recognizer != nil else {
            throw SystemSpeechASRError.recognizerUnavailable
        }

        let auth = await Self.resolveSpeechAuthorization()
        guard auth == .authorized else {
            throw SystemSpeechASRError.authorizationDenied
        }

        guard let recognizer, recognizer.isAvailable else {
            throw SystemSpeechASRError.recognizerUnavailable
        }

        startedAt = CACurrentMediaTime()
        currentUtteranceID = UUID().uuidString
        lastFinalTs = 0
        lastPartialText = ""
        seqGenerator.reset(to: 80_000)
        isRunning = true
        try startRecognitionTask(using: recognizer)

        let input = ScreenAudioInput(requestBridge: requestBridge)
        input.onRawSampleBuffer = onRawSystemAudioBuffer
        do {
            try await input.start()
        } catch {
            await stopInternal()
            throw SystemSpeechASRError.startCaptureFailed(error.localizedDescription)
        }
        systemInput = input
    }

    public func stopStream() async {
        await stopInternal()
    }

    public func reset() async {
        await stopInternal()
        seqGenerator.reset(to: 80_000)
    }

    private func startRecognitionTask(using recognizer: SFSpeechRecognizer) throws {
        guard recognizer.isAvailable else {
            throw SystemSpeechASRError.recognizerUnavailable
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }
        // Для долгого потока собеседника стабильнее network + local fallback,
        // поэтому не форсируем on-device режим.
        request.requiresOnDeviceRecognition = false

        recognitionRequest = request
        requestBridge.set(request)

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                Task { @MainActor [weak self] in
                    self?.emit(result: result)
                }
            }
            if let error {
                Task { @MainActor [weak self] in
                    await self?.handleRecognitionFailure(error)
                }
            }
        }
    }

    private func handleRecognitionFailure(_ error: Error) async {
        guard isRunning else { return }
        guard !Task.isCancelled else { return }
        guard !isRestartingRecognition else { return }
        guard let recognizer else { return }

        isRestartingRecognition = true
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        requestBridge.set(nil)

        try? await Task.sleep(nanoseconds: 250_000_000)
        guard isRunning else {
            isRestartingRecognition = false
            return
        }

        do {
            try startRecognitionTask(using: recognizer)
        } catch {
            // Пробуем повторить позже, не роняя сессию.
        }
        isRestartingRecognition = false
        _ = error
    }

    private func emit(result: SFSpeechRecognitionResult) {
        let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if !result.isFinal && text == lastPartialText {
            return
        }

        let approxEndTs = max(0, CACurrentMediaTime() - startedAt)
        let tsEnd = result.bestTranscription.segments.last.map { $0.timestamp + $0.duration } ?? approxEndTs
        let normalizedTsEnd = max(tsEnd, approxEndTs)
        let tsStart = max(0, min(lastFinalTs, normalizedTsEnd))

        let segment = TranscriptSegment(
            seq: seqGenerator.next(),
            utteranceId: currentUtteranceID,
            isFinal: result.isFinal,
            speaker: "THEM",
            text: text,
            tsStart: tsStart,
            tsEnd: normalizedTsEnd,
            speakerConfidence: 0.9
        )
        continuation?.yield(segment)

        if result.isFinal {
            lastFinalTs = normalizedTsEnd
            currentUtteranceID = UUID().uuidString
            lastPartialText = ""
        } else {
            lastPartialText = text
        }
    }

    private func stopInternal() async {
        isRunning = false
        isRestartingRecognition = false

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        requestBridge.set(nil)

        if let systemInput {
            await systemInput.stop()
            self.systemInput = nil
        }
    }

    nonisolated private static func resolveSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current != .notDetermined {
            return current
        }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

#if canImport(ScreenCaptureKit)
@available(macOS 13.0, *)
private final class ScreenAudioInput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let requestBridge: RecognitionRequestBridge
    private let queue = DispatchQueue(label: "ai.meeting.copilot.system-speech-input")
    private var stream: SCStream?

    /// Callback для передачи сырого CMSampleBuffer наружу (запись, диаризация).
    var onRawSampleBuffer: (@Sendable (CMSampleBuffer) -> Void)?

    init(requestBridge: RecognitionRequestBridge) {
        self.requestBridge = requestBridge
        super.init()
    }

    func start() async throws {
        let shareable = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = shareable.displays.first else {
            throw SystemSpeechASRError.sourceUnavailable
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = max(display.width, 2)
        config.height = max(display.height, 2)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 3
        config.capturesAudio = true
        config.sampleRate = 16_000
        config.channelCount = 1
        config.excludesCurrentProcessAudio = true

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        if let stream {
            try? await stream.stopCapture()
            self.stream = nil
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard CMSampleBufferIsValid(sampleBuffer), CMSampleBufferDataIsReady(sampleBuffer) else { return }
        requestBridge.append(sampleBuffer: sampleBuffer)
        onRawSampleBuffer?(sampleBuffer)
    }
}
#else
private final class ScreenAudioInput: @unchecked Sendable {
    init(requestBridge: RecognitionRequestBridge) {}

    func start() async throws {
        throw SystemSpeechASRError.unsupportedOS
    }

    func stop() async {}
}
#endif
