import XCTest
@testable import AIMeetingCopilotCore

final class CalendarProfileSuggesterTests: XCTestCase {
    func testDetectsInterviewCandidate() {
        XCTAssertEqual(
            CalendarProfileSuggester.suggestedProfileID(for: "HR Interview: Senior iOS Candidate"),
            "interview_candidate"
        )
    }

    func testDetectsTechSync() {
        XCTAssertEqual(
            CalendarProfileSuggester.suggestedProfileID(for: "Incident Sync: API latency regression"),
            "tech_sync"
        )
    }

    func testReturnsNilForGenericTitle() {
        XCTAssertNil(CalendarProfileSuggester.suggestedProfileID(for: "Weekly catch up"))
    }
}
