import Foundation

public struct ProfileOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    public static let all: [ProfileOption] = [
        .init(id: "negotiation", title: "Деловые переговоры"),
        .init(id: "interview_candidate", title: "Собеседование: я кандидат"),
        .init(id: "interview_interviewer", title: "Собеседование: я интервьюер"),
        .init(id: "consulting", title: "Консультация"),
        .init(id: "sales", title: "Продажа / демо"),
        .init(id: "tech_sync", title: "Технический созвон")
    ]

    public static func title(for id: String) -> String {
        all.first(where: { $0.id == id })?.title ?? id
    }
}
