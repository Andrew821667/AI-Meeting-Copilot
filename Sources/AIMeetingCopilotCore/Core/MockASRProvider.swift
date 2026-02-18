import Foundation
import QuartzCore

@MainActor
public final class MockASRProvider: ASRProvider {
    public var segments: AsyncStream<TranscriptSegment>

    private let seqGenerator = SequenceNumberGenerator()
    private var continuation: AsyncStream<TranscriptSegment>.Continuation?
    private var streamTask: Task<Void, Never>?
    private var startedAt: TimeInterval = 0
    private let script: [String]

    public init(script: [String] = [
        "Коллеги, по дедлайну у нас остаётся три дня.",
        "Если переносим срок, появится штраф в договоре.",
        "Последнее предложение по цене действует до пятницы."
    ]) {
        self.script = script
        var continuationRef: AsyncStream<TranscriptSegment>.Continuation?
        self.segments = AsyncStream { continuation in
            continuationRef = continuation
        }
        self.continuation = continuationRef
    }

    public func startStream() async throws {
        stopStreamInternal()
        seqGenerator.reset()
        startedAt = CACurrentMediaTime()

        streamTask = Task { [weak self] in
            guard let self else { return }

            for (index, text) in self.script.enumerated() {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 900_000_000)

                let utteranceId = UUID().uuidString
                let tsStart = CACurrentMediaTime() - self.startedAt
                let partial = TranscriptSegment(
                    seq: self.seqGenerator.next(),
                    utteranceId: utteranceId,
                    isFinal: false,
                    speaker: "THEM",
                    text: String(text.prefix(max(10, text.count / 2))),
                    tsStart: tsStart,
                    tsEnd: tsStart + 0.3,
                    speakerConfidence: 0.90
                )
                self.continuation?.yield(partial)

                try? await Task.sleep(nanoseconds: 350_000_000)

                let finalTs = CACurrentMediaTime() - self.startedAt
                let final = TranscriptSegment(
                    seq: self.seqGenerator.next(),
                    utteranceId: utteranceId,
                    isFinal: true,
                    speaker: "THEM",
                    text: text,
                    tsStart: tsStart,
                    tsEnd: finalTs,
                    speakerConfidence: 0.91
                )
                self.continuation?.yield(final)

                if index == self.script.count - 1 {
                    break
                }
            }
        }
    }

    public func stopStream() async {
        stopStreamInternal()
    }

    public func reset() async {
        stopStreamInternal()
        seqGenerator.reset()
    }

    private func stopStreamInternal() {
        streamTask?.cancel()
        streamTask = nil
    }
}
