import Foundation

public enum SessionState: String, Codable {
    case idle = "IDLE"
    case capturing = "CAPTURING"
    case paused = "PAUSED"
    case ended = "ENDED"
}

public enum SessionTransitionError: Error {
    case invalidTransition(from: SessionState, to: SessionState)
}

public actor SessionStateMachine {
    public private(set) var state: SessionState = .idle
    public private(set) var sessionID: UUID?
    private var seq: UInt64 = 0

    public init() {}

    @discardableResult
    public func startCapture() throws -> UUID {
        guard state == .idle || state == .ended else {
            throw SessionTransitionError.invalidTransition(from: state, to: .capturing)
        }
        let id = UUID()
        sessionID = id
        seq = 0
        state = .capturing
        return id
    }

    public func pauseCapture() throws {
        guard state == .capturing else {
            throw SessionTransitionError.invalidTransition(from: state, to: .paused)
        }
        state = .paused
    }

    public func resumeCapture() throws {
        guard state == .paused else {
            throw SessionTransitionError.invalidTransition(from: state, to: .capturing)
        }
        state = .capturing
    }

    public func endCapture() throws {
        guard state == .capturing || state == .paused else {
            throw SessionTransitionError.invalidTransition(from: state, to: .ended)
        }
        state = .ended
    }

    public func nextSeq() -> UInt64 {
        seq += 1
        return seq
    }
}
