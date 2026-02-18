import Foundation
import EventKit

public struct CalendarProfileSuggestion: Equatable {
    public let eventTitle: String
    public let eventStart: Date
    public let profileID: String
}

public enum CalendarSuggestionResult: Equatable {
    case suggestion(CalendarProfileSuggestion)
    case permissionDenied
    case noUpcomingEvents
    case noProfileMatch
}

public final class CalendarProfileSuggester {
    private let eventStore: EKEventStore

    public init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    public func fetchNearestSuggestion(now: Date = Date()) async -> CalendarSuggestionResult {
        let accessGranted = await ensureCalendarAccess()
        guard accessGranted else {
            return .permissionDenied
        }

        let start = now.addingTimeInterval(-30 * 60)
        let end = now.addingTimeInterval(8 * 60 * 60)
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = eventStore.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }

        guard !events.isEmpty else {
            return .noUpcomingEvents
        }

        for event in events {
            let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            guard let profileID = Self.suggestedProfileID(for: title) else { continue }

            return .suggestion(
                CalendarProfileSuggestion(
                    eventTitle: title,
                    eventStart: event.startDate,
                    profileID: profileID
                )
            )
        }

        return .noProfileMatch
    }

    public static func suggestedProfileID(for meetingTitle: String) -> String? {
        let title = normalizedTitle(meetingTitle)

        if containsAny(title, keywords: ["interviewer", "интервьюер", "hiring panel", "нанимаем", "оценка кандидата"]) {
            return "interview_interviewer"
        }

        if containsAny(title, keywords: ["interview", "собеседован", "candidate", "кандидат", "hr screen", "technical interview"]) {
            return "interview_candidate"
        }

        if containsAny(title, keywords: ["standup", "sync", "incident", "postmortem", "hotfix", "regression", "latency", "тех", "техничес", "инцидент"]) {
            return "tech_sync"
        }

        if containsAny(title, keywords: ["sales", "demo", "discovery", "лид", "продаж", "демо", "презентац", "пресейл"]) {
            return "sales"
        }

        if containsAny(title, keywords: ["consult", "консультац", "аудит", "брейншторм", "воркшоп"]) {
            return "consulting"
        }

        if containsAny(title, keywords: ["negotiation", "переговор", "contract", "договор", "условия", "pricing", "цена", "коммерческое предложение"]) {
            return "negotiation"
        }

        return nil
    }

    private func ensureCalendarAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if hasAccess(status) {
            return true
        }

        if status == .denied || status == .restricted {
            return false
        }

        if #available(macOS 14.0, *) {
            return (try? await eventStore.requestFullAccessToEvents()) ?? false
        }

        return await withCheckedContinuation { continuation in
            eventStore.requestAccess(to: .event) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    private func hasAccess(_ status: EKAuthorizationStatus) -> Bool {
        if #available(macOS 14.0, *) {
            return status == .fullAccess || status == .authorized
        }
        return status == .authorized
    }

    private static func normalizedTitle(_ raw: String) -> String {
        raw
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
    }

    private static func containsAny(_ haystack: String, keywords: [String]) -> Bool {
        keywords.contains(where: { haystack.contains($0) })
    }
}
