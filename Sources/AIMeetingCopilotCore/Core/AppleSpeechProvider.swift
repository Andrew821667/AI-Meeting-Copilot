import Foundation

/// Локальное распознавание речи через Apple Speech Framework
/// (`SFSpeechRecognizer` / `SFSpeechAudioBufferRecognitionRequest`).
///
/// Раньше класс назывался `WhisperKitProvider` — это было лживо: WhisperKit
/// никогда не был подключён, под капотом всегда работал Apple Speech.
/// Имя осталось только в типе AsRProviderOption.id="whisperkit" ради
/// обратной совместимости с уже сохранёнными в UserDefaults селекшенами.
@MainActor
public final class AppleSpeechProvider: ASRProvider {
    public var segments: AsyncStream<TranscriptSegment> {
        activeProvider.segments
    }

    private let activeProvider: ASRProvider

    /// Доступ к внутреннему SpeechASRProvider для передачи аудио-буферов.
    public var speechProvider: SpeechASRProvider? {
        activeProvider as? SpeechASRProvider
    }

    public init() {
        if ProcessInfo.processInfo.environment["AIMC_ASR_MOCK"] == "1" {
            activeProvider = MockASRProvider()
        } else {
            activeProvider = SpeechASRProvider()
        }
    }

    public func startStream() async throws {
        try await activeProvider.startStream()
    }

    public func stopStream() async {
        await activeProvider.stopStream()
    }

    public func reset() async {
        await activeProvider.reset()
    }
}

/// Старое имя — оставляем как typealias, чтобы внешний код, ссылающийся на
/// `WhisperKitProvider`, продолжал компилироваться. Новый код использует
/// `AppleSpeechProvider` напрямую.
@available(*, deprecated, renamed: "AppleSpeechProvider")
public typealias WhisperKitProvider = AppleSpeechProvider
