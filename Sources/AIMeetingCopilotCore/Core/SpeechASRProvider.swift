import Foundation
import AVFoundation
import Speech
import QuartzCore
import os.log

private let asrLog = OSLog(subsystem: "com.andrew821667.ai-meeting-copilot", category: "asr")

private func logASR(_ message: String) {
    os_log("%{public}@", log: asrLog, type: .default, message)
    let line = "\(Date()) [ASR] \(message)\n"
    let path = "/tmp/aimc_debug.log"
    if let fh = FileHandle(forWritingAtPath: path) {
        fh.seekToEndOfFile()
        fh.write(line.data(using: .utf8)!)
        fh.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
    }
}

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
        logASR("startStream called")
        stopInternal()

        guard recognizer != nil else {
            logASR("ERROR: recognizer is nil")
            throw SpeechASRError.recognizerUnavailable
        }

        let auth = await Self.resolveSpeechAuthorization()
        logASR("auth status: \(auth.rawValue)")
        guard auth == .authorized else {
            logASR("ERROR: auth denied (\(auth.rawValue))")
            throw SpeechASRError.authorizationDenied
        }

        guard let recognizer, recognizer.isAvailable else {
            logASR("ERROR: recognizer not available")
            throw SpeechASRError.recognizerUnavailable
        }
        logASR("recognizer available, supportsOnDevice=\(recognizer.supportsOnDeviceRecognition)")

        startedAt = CACurrentMediaTime()
        currentUtteranceID = UUID().uuidString
        lastFinalTs = 0
        lastPartialText = ""
        seqGenerator.reset(to: 50_000)
        isRunning = true

        try startRecognitionTask(using: recognizer)
        logASR("recognition task started, waiting for audio buffers from MicrophoneCaptureService...")
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

        logASR("creating recognitionTask...")
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
        logASR("recognitionTask created")
    }

    public func stopStream() async {
        stopInternal()
    }

    public func reset() async {
        stopInternal()
        seqGenerator.reset(to: 50_000)
    }

    private func handleRecognitionFailure(_ error: Error) async {
        logASR("recognition failure: \(error)")
        guard isRunning else { logASR("  → not running, ignoring"); return }
        guard !Task.isCancelled else { logASR("  → task cancelled, ignoring"); return }
        guard !isRestartingRecognition else { logASR("  → already restarting, ignoring"); return }
        guard let recognizer else { logASR("  → no recognizer, ignoring"); return }

        isRestartingRecognition = true

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        requestBridge.set(nil)

        // Новый utterance после перезапуска
        currentUtteranceID = UUID().uuidString
        lastPartialText = ""

        // Даём больше времени перед перезапуском, чтобы не зацикливаться
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 секунда

        guard isRunning else {
            isRestartingRecognition = false
            return
        }

        do {
            try startRecognitionTask(using: recognizer)
            logASR("recognition restarted after failure")
        } catch {
            logASR("ERROR: restart failed: \(error)")
        }
        isRestartingRecognition = false
    }

    private func emit(result: SFSpeechRecognitionResult) {
        let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
        logASR("emit: isFinal=\(result.isFinal) text=\"\(text.prefix(80))\"")
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
