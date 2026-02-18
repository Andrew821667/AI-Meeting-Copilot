import Foundation

public struct ProfileRuntimeSettings: Codable, Equatable, Sendable {
    public var threshold: Double
    public var cooldownSec: Double
    public var maxCardsPer10Min: Int
    public var minPauseSec: Double
    public var minContextMin: Int

    public init(
        threshold: Double,
        cooldownSec: Double,
        maxCardsPer10Min: Int,
        minPauseSec: Double,
        minContextMin: Int
    ) {
        self.threshold = threshold
        self.cooldownSec = cooldownSec
        self.maxCardsPer10Min = maxCardsPer10Min
        self.minPauseSec = minPauseSec
        self.minContextMin = minContextMin
    }

    enum CodingKeys: String, CodingKey {
        case threshold
        case cooldownSec = "cooldown_sec"
        case maxCardsPer10Min = "max_cards_per_10min"
        case minPauseSec = "min_pause_sec"
        case minContextMin = "min_context_min"
    }

    public static func defaults(for profileID: String) -> ProfileRuntimeSettings {
        switch profileID {
        case "negotiation":
            return .init(threshold: 0.60, cooldownSec: 90, maxCardsPer10Min: 4, minPauseSec: 1.5, minContextMin: 2)
        case "interview_candidate":
            return .init(threshold: 0.70, cooldownSec: 90, maxCardsPer10Min: 3, minPauseSec: 1.5, minContextMin: 1)
        case "interview_interviewer":
            return .init(threshold: 0.65, cooldownSec: 90, maxCardsPer10Min: 4, minPauseSec: 1.5, minContextMin: 1)
        case "consulting":
            return .init(threshold: 0.70, cooldownSec: 90, maxCardsPer10Min: 3, minPauseSec: 1.5, minContextMin: 1)
        case "sales":
            return .init(threshold: 0.65, cooldownSec: 90, maxCardsPer10Min: 4, minPauseSec: 1.5, minContextMin: 1)
        case "tech_sync":
            return .init(threshold: 0.65, cooldownSec: 90, maxCardsPer10Min: 5, minPauseSec: 1.5, minContextMin: 1)
        default:
            return .init(threshold: 0.60, cooldownSec: 90, maxCardsPer10Min: 4, minPauseSec: 1.5, minContextMin: 2)
        }
    }
}
