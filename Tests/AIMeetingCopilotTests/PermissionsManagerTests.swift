import XCTest
import AVFoundation
@testable import AIMeetingCopilotCore

@MainActor
final class PermissionsManagerTests: XCTestCase {
    func testConsentVersionMustMatchCurrentVersion() {
        let suiteName = "PermissionsManagerTests.v2.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(1, forKey: "consent_ack_version")

        let manager = PermissionsManager(
            defaults: defaults,
            microphoneStatusProvider: { .authorized },
            screenRecordingStatusProvider: { true }
        )

        XCTAssertFalse(manager.checklist.oneTimeAcknowledgementAccepted)
    }

    func testAcceptAcknowledgementMarksChecklistAsReady() {
        let suiteName = "PermissionsManagerTests.accept.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let manager = PermissionsManager(
            defaults: defaults,
            microphoneStatusProvider: { .authorized },
            screenRecordingStatusProvider: { true }
        )

        XCTAssertFalse(manager.checklist.oneTimeAcknowledgementAccepted)
        manager.acceptOneTimeAcknowledgement()

        XCTAssertTrue(manager.checklist.oneTimeAcknowledgementAccepted)
        XCTAssertEqual(defaults.integer(forKey: "consent_ack_version"), PermissionsManager.currentConsentVersion)
    }
}
