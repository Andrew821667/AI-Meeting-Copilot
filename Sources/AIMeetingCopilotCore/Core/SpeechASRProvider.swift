import Foundation
import AVFoundation
import Speech
import QuartzCore

private final class SpeechTapProxy {
    private let request: SFSpeechAudioBufferRecognitionRequest

    init(request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func makeTapBlock() -> AVAudioNodeTapBlock {
        { [weak self] buffer, _ in
            self?.request.append(buffer)
        }
    }
}

public enum SpeechASRError: LocalizedError {
    case recognizerUnavailable
    case authorizationDenied
    case inputNodeUnavailable
    case engineStartFailed(String)

    public var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Локальный распознаватель речи недоступен."
        case .authorizationDenied:
            return "Нет доступа к распознаванию речи. Разрешите его в Настройках macOS."
        case .inputNodeUnavailable:
            return "Не удалось получить аудиовход для распознавания."
        case .engineStartFailed(let reason):
            return "Не удалось запустить распознавание речи: \(reason)"
        }
    }
}

@MainActor
public final class SpeechASRProvider: ASRProvider {
    public var segments: AsyncStream<TranscriptSegment> {
        stream
    }

    private let stream: AsyncStream<TranscriptSegment>
    private var continuation: AsyncStream<TranscriptSegment>.Continuation?
    private let seqGenerator = SequenceNumberGenerator(startAt: 50_000)

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var tapProxy: SpeechTapProxy?
    private let recognizer: SFSpeechRecognizer?

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
        stopInternal()

        guard recognizer != nil else {
            throw SpeechASRError.recognizerUnavailable
        }

        let auth = await Self.resolveSpeechAuthorization()
        guard auth == .authorized else {
            throw SpeechASRError.authorizationDenied
        }

        guard let recognizer, recognizer.isAvailable else {
            throw SpeechASRError.recognizerUnavailable
        }

        startedAt = CACurrentMediaTime()
        currentUtteranceID = UUID().uuidString
        lastFinalTs = 0
        lastPartialText = ""
        seqGenerator.reset(to: 50_000)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            throw SpeechASRError.inputNodeUnavailable
        }

        inputNode.removeTap(onBus: 0)
        let tapProxy = SpeechTapProxy(request: request)
        self.tapProxy = tapProxy
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: tapProxy.makeTapBlock())

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            throw SpeechASRError.engineStartFailed(error.localizedDescription)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                Task { @MainActor [weak self] in
                    self?.emit(result: result)
                }
            }
            if error != nil {
                Task { @MainActor [weak self] in
                    self?.stopInternal()
                }
            }
        }

        isRunning = true
    }

    public func stopStream() async {
        stopInternal()
    }

    public func reset() async {
        stopInternal()
        seqGenerator.reset(to: 50_000)
    }

    private func emit(result: SFSpeechRecognitionResult) {
        let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Частичные результаты приходят часто; дубли не отправляем.
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
            speaker: "ME",
            text: text,
            tsStart: tsStart,
            tsEnd: normalizedTsEnd,
            speakerConfidence: 1.0
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

    private func stopInternal() {
        guard isRunning else { return }
        isRunning = false

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        tapProxy = nil
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
