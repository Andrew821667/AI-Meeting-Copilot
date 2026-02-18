import Foundation

public struct InsightCard: Codable, Identifiable {
    public let id: String
    public let scenario: String
    public let cardMode: String
    public let triggerReason: String
    public let insight: String
    public var replyCautious: String
    public var replyConfident: String
    public var severity: String
    public let timestamp: Double
    public let speaker: String
    public var isFallback: Bool
    public var dismissed: Bool
    public var pinned: Bool
    public var excluded: Bool

    public init(
        id: String,
        scenario: String,
        cardMode: String,
        triggerReason: String,
        insight: String,
        replyCautious: String,
        replyConfident: String,
        severity: String,
        timestamp: Double,
        speaker: String,
        isFallback: Bool = false,
        dismissed: Bool = false,
        pinned: Bool = false,
        excluded: Bool = false
    ) {
        self.id = id
        self.scenario = scenario
        self.cardMode = cardMode
        self.triggerReason = triggerReason
        self.insight = insight
        self.replyCautious = replyCautious
        self.replyConfident = replyConfident
        self.severity = severity
        self.timestamp = timestamp
        self.speaker = speaker
        self.isFallback = isFallback
        self.dismissed = dismissed
        self.pinned = pinned
        self.excluded = excluded
    }

    enum CodingKeys: String, CodingKey {
        case id
        case scenario
        case cardMode = "card_mode"
        case triggerReason = "trigger_reason"
        case insight
        case replyCautious = "reply_cautious"
        case replyConfident = "reply_confident"
        case severity
        case timestamp
        case speaker
        case isFallback = "is_fallback"
        case dismissed
        case pinned
        case excluded
    }
}
