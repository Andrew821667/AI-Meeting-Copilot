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
    @Published public private(set) var checklist: OnboardingChecklistState

    private let consentDefaultsKey = "consent_ack_v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.checklist = OnboardingChecklistState(
            microphonePermissionGranted: false,
            screenRecordingPermissionGranted: false,
            oneTimeAcknowledgementAccepted: defaults.bool(forKey: consentDefaultsKey)
        )
        refresh()
    }

    public func refresh() {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let micGranted = (micStatus == .authorized)
        let screenGranted = CGPreflightScreenCaptureAccess()
        let consent = defaults.bool(forKey: consentDefaultsKey)

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
        defaults.set(true, forKey: consentDefaultsKey)
        refresh()
    }
}
