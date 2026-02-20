import Foundation
import AVFoundation
import Speech
import QuartzCore

private final class RecognitionRequestBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    func append(buffer: AVAudioPCMBuffer) {
        lock.lock()
        let request = self.request
        lock.unlock()
        request?.append(buffer)
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

/// ASR-провайдер на базе Apple Speech Framework.
/// Не создаёт свой AVAudioEngine — получает аудио-буферы извне через `feedAudioBuffer(_:)`.
/// Это позволяет использовать единый AVAudioEngine из MicrophoneCaptureService.
@MainActor
public final class SpeechASRProvider: ASRProvider {
    public var segments: AsyncStream<TranscriptSegment> {
        stream
    }

    private let stream: AsyncStream<TranscriptSegment>
    private var continuation: AsyncStream<TranscriptSegment>.Continuation?
    private let seqGenerator = SequenceNumberGenerator(startAt: 50_000)

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let requestBridge = RecognitionRequestBridge()
    private let recognizer: SFSpeechRecognizer?
    private var isRestartingRecognition = false

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

    /// Передать аудио-буфер из внешнего AVAudioEngine в распознавание.
    /// Вызывается из MicrophoneCaptureService на каждый буфер.
    public nonisolated func feedAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        requestBridge.append(buffer: buffer)
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
        isRunning = true

        try startRecognitionTask(using: recognizer)
    }

    private func startRecognitionTask(using recognizer: SFSpeechRecognizer) throws {
        guard recognizer.isAvailable else {
            throw SpeechASRError.recognizerUnavailable
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

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

    public func stopStream() async {
        stopInternal()
    }

    public func reset() async {
        stopInternal()
        seqGenerator.reset(to: 50_000)
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

        currentUtteranceID = UUID().uuidString
        lastPartialText = ""

        try? await Task.sleep(nanoseconds: 1_000_000_000)

        guard isRunning else {
            isRestartingRecognition = false
            return
        }

        do {
            try startRecognitionTask(using: recognizer)
        } catch {
            // Не роняем сессию — попробуем при следующем сбое
        }
        isRestartingRecognition = false
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
        isRestartingRecognition = false

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        requestBridge.set(nil)
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
