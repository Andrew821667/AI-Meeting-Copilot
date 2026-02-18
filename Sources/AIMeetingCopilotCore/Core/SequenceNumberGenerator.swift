import Foundation

public final class SequenceNumberGenerator: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64

    public init(startAt value: UInt64 = 0) {
        self.value = value
    }

    public func reset(to newValue: UInt64 = 0) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    public func next() -> UInt64 {
        lock.lock()
        value += 1
        let current = value
        lock.unlock()
        return current
    }
}
