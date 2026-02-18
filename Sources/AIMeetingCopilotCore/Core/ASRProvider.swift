import Foundation

@MainActor
public protocol ASRProvider: AnyObject {
    var segments: AsyncStream<TranscriptSegment> { get }
    func startStream() async throws
    func stopStream() async
    func reset() async
}
