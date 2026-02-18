import Foundation

@MainActor
public final class Qwen3ASRProvider: ASRProvider {
    public var segments: AsyncStream<TranscriptSegment> {
        fallback.segments
    }

    private let fallback = MockASRProvider(
        script: [
            "Давайте сверим SLA и latency по API перед релизом.",
            "По логам видно regression после последнего hotfix.",
            "Нужен быстрый план диагностики и владельцы задач."
        ]
    )

    public init() {}

    public func startStream() async throws {
        // Stage 14: provider boundary + UI switch. Runtime integration with mlx-qwen3-asr is planned later.
        try await fallback.startStream()
    }

    public func stopStream() async {
        await fallback.stopStream()
    }

    public func reset() async {
        await fallback.reset()
    }
}
