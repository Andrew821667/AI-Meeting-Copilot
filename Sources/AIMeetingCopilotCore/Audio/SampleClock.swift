import Foundation
import QuartzCore

public final class SampleClock: @unchecked Sendable {
    private let lock = NSLock()

    public let sessionStartTime: TimeInterval
    public private(set) var totalSamplesProcessed: UInt64 = 0

    public init(sessionStartTime: TimeInterval = CACurrentMediaTime()) {
        self.sessionStartTime = sessionStartTime
    }

    @discardableResult
    public func advance(frames: Int, sampleRate: Double) -> TimeInterval {
        lock.lock()
        totalSamplesProcessed += UInt64(max(frames, 0))
        let ts = sessionStartTime + (Double(totalSamplesProcessed) / max(sampleRate, 1))
        lock.unlock()
        return ts
    }

    public func relativeTimestamp() -> TimeInterval {
        lock.lock()
        let ts = CACurrentMediaTime() - sessionStartTime
        lock.unlock()
        return ts
    }
}
