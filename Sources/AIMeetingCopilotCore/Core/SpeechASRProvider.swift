import Foundation
import AVFoundation
import Speech
import QuartzCore
import os.log

private final class RecognitionRequestBridge: @unchecked Sendable {
    private static let log = Logger(subsystem: "ai.meeting.copilot", category: "SpeechASRBridge")
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var bufferCount = 0
    private var droppedCount = 0
    private var lastLogAt = CACurrentMediaTime()

    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    func append(buffer: AVAudioPCMBuffer) {
        lock.lock()
        let request = self.request
        if request != nil { bufferCount += 1 } else { droppedCount += 1 }
        let now = CACurrentMediaTime()
        let shouldLog = now - lastLogAt >= 2.0
        if shouldLog { lastLogAt = now }
        let bc = bufferCount, dc = droppedCount
        lock.unlock()

        request?.append(buffer)

        if shouldLog {
            let fmt = buffer.format
            let rms = Self.rms(buffer)
            Self.log.notice("bridge: fed=\(bc, privacy: .public) dropped=\(dc, privacy: .public) fmt=\(fmt.sampleRate, privacy: .public)Hz/\(fmt.channelCount, privacy: .public)ch frames=\(buffer.frameLength, privacy: .public) rms=\(rms, privacy: .public)")
        }
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let ch = buffer.floatChannelData else { return -1 }  // -1 = не float формат
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var s: Float = 0
        for i in 0..<n { let v = ch[0][i]; s += v * v }
        return (s / Float(n)).squareRoot()
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
    static let log = Logger(subsystem: "ai.meeting.copilot", category: "SpeechASR")

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
    /// Накопленный текст, перенесённый через рестарты распознавания.
    /// Apple Speech перезапускается на паузах и теряет предыдущий текст —
    /// без переноса транскрипт "прыгает" по одному слову ("Какой"→"Какие"→"Они").
    private var carryOverText: String = ""
    /// Время последнего рестарта — троттл против busy-loop, когда on-device
    /// распознаватель мгновенно отдаёт 1110 сразу после создания task.
    private var lastRestartAt: TimeInterval = 0
    /// Время последнего partial-обновления — по нему детектим паузу речи.
    private var lastPartialAt: TimeInterval = 0
    /// Пауза, после которой считаем фразу законченной. Серверный Speech при
    /// непрерывном стриме почти не выдаёт isFinal — без собственной
    /// сегментации весь разговор слипается в одну бесконечную строку.
    private let utteranceSilenceSec: TimeInterval = 1.8
    private var silenceMonitor: Task<Void, Never>?

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
        carryOverText = ""
        seqGenerator.reset(to: 50_000)
        isRunning = true

        try startRecognitionTask(using: recognizer)

        // Монитор пауз: закрывает фразу финалом после utteranceSilenceSec
        // без новых partial'ов.
        silenceMonitor?.cancel()
        silenceMonitor = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard let self, self.isRunning else { break }
                self.finalizeUtteranceIfSilent()
            }
        }
    }

    private func finalizeUtteranceIfSilent() {
        guard isRunning, !lastPartialText.isEmpty else { return }
        let now = CACurrentMediaTime()
        guard now - lastPartialAt >= utteranceSilenceSec else { return }

        // Закрываем фразу финальным сегментом.
        let text = lastPartialText
        let approxEndTs = max(0, now - startedAt)
        let segment = TranscriptSegment(
            seq: seqGenerator.next(),
            utteranceId: currentUtteranceID,
            isFinal: true,
            speaker: "ME",
            text: text,
            tsStart: max(0, min(lastFinalTs, approxEndTs)),
            tsEnd: approxEndTs,
            speakerConfidence: 1.0
        )
        continuation?.yield(segment)

        lastFinalTs = approxEndTs
        carryOverText = ""
        lastPartialText = ""
        currentUtteranceID = UUID().uuidString

        // Перезапускаем распознавание, чтобы следующая фраза начиналась с
        // чистого листа (иначе серверный Speech продолжит дописывать старую).
        Task { @MainActor [weak self] in
            await self?.rotateRecognitionTask()
        }
    }

    private func rotateRecognitionTask() async {
        guard isRunning, !isRestartingRecognition, let recognizer, recognizer.isAvailable else { return }
        isRestartingRecognition = true
        defer { isRestartingRecognition = false }

        let newRequest = makeRequest(using: recognizer)
        requestBridge.set(newRequest)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = newRequest
        lastRestartAt = CACurrentMediaTime()
        recognitionTask = makeTask(for: newRequest, using: recognizer)
    }

    private func startRecognitionTask(using recognizer: SFSpeechRecognizer) throws {
        // Первый старт: старого task нет. Закрываем на всякий случай и ставим свежий.
        recognitionTask?.cancel()
        recognitionTask = nil
        guard recognizer.isAvailable else {
            throw SpeechASRError.recognizerUnavailable
        }
        let request = makeRequest(using: recognizer)
        requestBridge.set(request)
        recognitionRequest = request
        recognitionTask = makeTask(for: request, using: recognizer)
    }

    private func makeRequest(using recognizer: SFSpeechRecognizer) -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }
        // Серверное распознавание по умолчанию: on-device ru-RU на текущей
        // macOS капризнее. Вернуть on-device: AIMC_ASR_ON_DEVICE=1.
        if ProcessInfo.processInfo.environment["AIMC_ASR_ON_DEVICE"] == "1",
           recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else {
            request.requiresOnDeviceRecognition = false
        }
        return request
    }

    private func makeTask(for request: SFSpeechAudioBufferRecognitionRequest, using recognizer: SFSpeechRecognizer) -> SFSpeechRecognitionTask {
        // weak request: когда мы заменяем request (rotate/restart), старый
        // освобождается, и события от его task'а гарантированно отсекаются.
        recognizer.recognitionTask(with: request) { [weak self, weak request] result, error in
            if let result {
                Task { @MainActor [weak self] in
                    guard let self, let request, request === self.recognitionRequest else { return }
                    self.emit(result: result)
                }
            }
            if let error {
                Task { @MainActor [weak self] in
                    // События от устаревшего task'а (мы сами его отменили при
                    // rotate/restart) игнорируем — иначе его "canceled"-ошибка
                    // запускает лишний рестарт, тот отменяет свежий task, и
                    // получается бесконечная карусель, в которой распознавание
                    // "зависает" после первой же паузы.
                    guard let self, let request, request === self.recognitionRequest else { return }
                    let ns = error as NSError
                    Self.log.error("recognitionTask error: domain=\(ns.domain, privacy: .public) code=\(ns.code, privacy: .public) desc=\(ns.localizedDescription, privacy: .public)")
                    await self.handleRecognitionFailure(error)
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
        defer { isRestartingRecognition = false }

        // Переносим накопленный текст, чтобы транскрипт продолжал расти,
        // а не начинался с нуля после рестарта.
        if !lastPartialText.isEmpty {
            carryOverText = lastPartialText
        }
        lastPartialText = ""

        // ПОРЯДОК КРИТИЧЕН. SFSpeechRecognizer ведёт только ОДИН активный
        // task: если создать новый до отмены старого, они конфликтуют, новый
        // мгновенно падает, и цикл рестартов рубит речь на однословные
        // обрывки (проверено стрим-тестом: без рестартов тот же аудиопоток
        // распознаётся идеально).
        //
        // 1) Новый request СРАЗУ в bridge — микрофонные буферы копятся в нём
        //    даже пока task ещё не создан. SFSpeechAudioBufferRecognitionRequest
        //    аккумулирует аудио — ничего не теряется, включая троттл-паузу.
        let newRequest = makeRequest(using: recognizer)
        requestBridge.set(newRequest)

        // 2) Старый task закрываем ДО создания нового.
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = newRequest

        // 3) Троттл против busy-loop (1110 на тишине приходит мгновенно).
        //    Аудио в это время копится в newRequest — потерь нет.
        let now = CACurrentMediaTime()
        let sinceLast = now - lastRestartAt
        if sinceLast < 0.6 {
            let waitNs = UInt64((0.6 - sinceLast) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: waitNs)
            guard isRunning else { return }
        }
        lastRestartAt = CACurrentMediaTime()

        // 4) Новый task на request с уже накопленным аудио.
        guard recognizer.isAvailable else { return }
        recognitionTask = makeTask(for: newRequest, using: recognizer)
    }

    private func emit(result: SFSpeechRecognitionResult) {
        let rawText = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else { return }

        // Дописываем перенесённый текст, чтобы фраза росла непрерывно.
        let text: String
        if carryOverText.isEmpty {
            text = rawText
        } else {
            text = carryOverText + " " + rawText
        }

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
            carryOverText = ""
            currentUtteranceID = UUID().uuidString
            lastPartialText = ""
        } else {
            lastPartialText = text
            lastPartialAt = CACurrentMediaTime()
        }
    }

    private func stopInternal() {
        silenceMonitor?.cancel()
        silenceMonitor = nil
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
