import Foundation

#if canImport(WhisperKit)
import WhisperKit
#endif

@MainActor
public final class WhisperKitProvider: ASRProvider {
    public var segments: AsyncStream<TranscriptSegment> {
        fallback.segments
    }

    private let fallback = MockASRProvider()

    public init() {}

    public func startStream() async throws {
#if canImport(WhisperKit)
        // Stage 1: provider boundary is fixed. WhisperKit runtime wiring is added in Stage 2.
#endif
        try await fallback.startStream()
    }

    public func stopStream() async {
        await fallback.stopStream()
    }

    public func reset() async {
        await fallback.reset()
    }
}
