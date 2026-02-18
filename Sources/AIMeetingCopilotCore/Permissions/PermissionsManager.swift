import Foundation
import AVFoundation
import CoreGraphics

public struct OnboardingChecklistState {
    public var microphonePermissionGranted: Bool
    public var screenRecordingPermissionGranted: Bool
    public var oneTimeAcknowledgementAccepted: Bool

    public init(
        microphonePermissionGranted: Bool,
        screenRecordingPermissionGranted: Bool,
        oneTimeAcknowledgementAccepted: Bool
    ) {
        self.microphonePermissionGranted = microphonePermissionGranted
        self.screenRecordingPermissionGranted = screenRecordingPermissionGranted
        self.oneTimeAcknowledgementAccepted = oneTimeAcknowledgementAccepted
    }

    public var isReadyForCapture: Bool {
        microphonePermissionGranted && screenRecordingPermissionGranted && oneTimeAcknowledgementAccepted
    }
}

@MainActor
public final class PermissionsManager: ObservableObject {
    public static let currentConsentVersion = 2

    @Published public private(set) var checklist: OnboardingChecklistState

    private let consentVersionDefaultsKey = "consent_ack_version"
    private let legacyConsentDefaultsKey = "consent_ack_v1"
    private let defaults: UserDefaults
    private let microphoneStatusProvider: () -> AVAuthorizationStatus
    private let screenRecordingStatusProvider: () -> Bool

    public init(
        defaults: UserDefaults = .standard,
        microphoneStatusProvider: @escaping () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .audio) },
        screenRecordingStatusProvider: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() }
    ) {
        self.defaults = defaults
        self.microphoneStatusProvider = microphoneStatusProvider
        self.screenRecordingStatusProvider = screenRecordingStatusProvider
        self.checklist = OnboardingChecklistState(
            microphonePermissionGranted: false,
            screenRecordingPermissionGranted: false,
            oneTimeAcknowledgementAccepted: false
        )
        refresh()
    }

    public func refresh() {
        migrateLegacyConsentIfNeeded()
        let micStatus = microphoneStatusProvider()
        let micGranted = (micStatus == .authorized)
        let screenGranted = screenRecordingStatusProvider()
        let consent = defaults.integer(forKey: consentVersionDefaultsKey) >= Self.currentConsentVersion

        checklist = OnboardingChecklistState(
            microphonePermissionGranted: micGranted,
            screenRecordingPermissionGranted: screenGranted,
            oneTimeAcknowledgementAccepted: consent
        )
    }

    @discardableResult
    public func requestMicrophonePermission() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        refresh()
        return granted
    }

    @discardableResult
    public func requestScreenRecordingPermission() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        refresh()
        return granted
    }

    public func acceptOneTimeAcknowledgement() {
        defaults.set(Self.currentConsentVersion, forKey: consentVersionDefaultsKey)
        defaults.set(true, forKey: legacyConsentDefaultsKey)
        refresh()
    }

    private func migrateLegacyConsentIfNeeded() {
        let acceptedVersion = defaults.integer(forKey: consentVersionDefaultsKey)
        if acceptedVersion > 0 {
            return
        }

        if defaults.bool(forKey: legacyConsentDefaultsKey) {
            defaults.set(1, forKey: consentVersionDefaultsKey)
        }
    }
}
