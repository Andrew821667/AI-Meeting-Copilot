import Foundation

public struct SessionHistoryItem: Identifiable, Hashable {
    public let id: String
    public let profileID: String
    public let startedAt: Date
    public let endedAt: Date
    public let totalCards: Int
    public let fallbackCards: Int
    public let exportPath: String

    public init(
        id: String,
        profileID: String,
        startedAt: Date,
        endedAt: Date,
        totalCards: Int,
        fallbackCards: Int,
        exportPath: String
    ) {
        self.id = id
        self.profileID = profileID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.totalCards = totalCards
        self.fallbackCards = fallbackCards
        self.exportPath = exportPath
    }
}
