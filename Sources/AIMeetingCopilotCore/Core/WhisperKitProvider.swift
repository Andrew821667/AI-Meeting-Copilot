import Foundation

#if canImport(WhisperKit)
import WhisperKit
#endif

@MainActor
public final class WhisperKitProvider: ASRProvider {
    public var segments: AsyncStream<TranscriptSegment> {
        activeProvider.segments
    }

    private let activeProvider: ASRProvider

    public init() {
        // В локальном контуре используем реальное распознавание через Speech framework.
        // Мок-режим можно включить вручную переменной окружения AIMC_ASR_MOCK=1.
        if ProcessInfo.processInfo.environment["AIMC_ASR_MOCK"] == "1" {
            activeProvider = MockASRProvider()
        } else {
            activeProvider = SpeechASRProvider()
        }
    }

    public func startStream() async throws {
#if canImport(WhisperKit)
        // Stage 1: provider boundary is fixed. WhisperKit runtime wiring is added in Stage 2.
#endif
        try await activeProvider.startStream()
    }

    public func stopStream() async {
        await activeProvider.stopStream()
    }

    public func reset() async {
        await activeProvider.reset()
    }
}
