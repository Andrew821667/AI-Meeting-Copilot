import Foundation

public struct EnergyVAD {
    public var threshold: Float
    public var minSilenceDurationSec: Double
    public private(set) var isSpeechActive: Bool = false

    private var lastSpeechTimestamp: TimeInterval = 0
    private var speechStartTimestamp: TimeInterval = 0

    public init(
        threshold: Float = 0.02,
        minSilenceDurationSec: Double = 0.30
    ) {
        self.threshold = threshold
        self.minSilenceDurationSec = minSilenceDurationSec
    }

    public mutating func process(rms: Float, timestamp: TimeInterval) -> MicEventType? {
        if rms >= threshold {
            lastSpeechTimestamp = timestamp
            if !isSpeechActive {
                isSpeechActive = true
                speechStartTimestamp = timestamp
                return .speechStart
            }
            return .speechState
        }

        if isSpeechActive && (timestamp - lastSpeechTimestamp) >= minSilenceDurationSec {
            isSpeechActive = false
            return .speechEnd
        }

        return nil
    }

    public func currentSpeechDuration(at timestamp: TimeInterval) -> TimeInterval {
        guard isSpeechActive else { return 0 }
        return max(0, timestamp - speechStartTimestamp)
    }
}
