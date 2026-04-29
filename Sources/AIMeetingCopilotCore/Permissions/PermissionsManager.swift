import Foundation
import AVFoundation
import CoreGraphics
import Speech
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

public struct OnboardingChecklistState {
    public var microphonePermissionGranted: Bool
    public var speechRecognitionPermissionGranted: Bool
    public var screenRecordingPermissionGranted: Bool
    public var oneTimeAcknowledgementAccepted: Bool

    public init(
        microphonePermissionGranted: Bool,
        speechRecognitionPermissionGranted: Bool,
        screenRecordingPermissionGranted: Bool,
        oneTimeAcknowledgementAccepted: Bool
    ) {
        self.microphonePermissionGranted = microphonePermissionGranted
        self.speechRecognitionPermissionGranted = speechRecognitionPermissionGranted
        self.screenRecordingPermissionGranted = screenRecordingPermissionGranted
        self.oneTimeAcknowledgementAccepted = oneTimeAcknowledgementAccepted
    }

    public var isReadyForCapture: Bool {
        microphonePermissionGranted && speechRecognitionPermissionGranted && oneTimeAcknowledgementAccepted
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
    private let speechRecognitionStatusProvider: () -> SFSpeechRecognizerAuthorizationStatus
    private let screenRecordingStatusProvider: () -> Bool
    /// In-memory только. CGPreflightScreenCaptureAccess() известен тем, что
    /// возвращает false до первого реального вызова screen capture API, даже
    /// если permission в System Settings выдан. Поэтому держим кэш результата
    /// последней успешной глубокой проверки (через SCShareableContent или
    /// CGRequestScreenCaptureAccess). При перезапуске .app кэш сбрасывается —
    /// это лучше, чем persist в UserDefaults (тот раньше залипал в true).
    private var screenPermissionOverride: Bool = false

    public init(
        defaults: UserDefaults = .standard,
        microphoneStatusProvider: @escaping () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .audio) },
        speechRecognitionStatusProvider: @escaping () -> SFSpeechRecognizerAuthorizationStatus = { SFSpeechRecognizer.authorizationStatus() },
        screenRecordingStatusProvider: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() }
    ) {
        self.defaults = defaults
        self.microphoneStatusProvider = microphoneStatusProvider
        self.speechRecognitionStatusProvider = speechRecognitionStatusProvider
        self.screenRecordingStatusProvider = screenRecordingStatusProvider
        self.checklist = OnboardingChecklistState(
            microphonePermissionGranted: false,
            speechRecognitionPermissionGranted: false,
            screenRecordingPermissionGranted: false,
            oneTimeAcknowledgementAccepted: false
        )
        refresh()
    }

    public func refresh() {
        migrateLegacyConsentIfNeeded()
        let micStatus = microphoneStatusProvider()
        let micGranted = (micStatus == .authorized)
        let speechGranted = (speechRecognitionStatusProvider() == .authorized)
        let preflightGranted = screenRecordingStatusProvider()
        // Override = кэш ПРАВДЫ, полученной через SCShareableContent или
        // CGRequestScreenCaptureAccess. Используем как ИЛИ-фолбэк, когда
        // preflight врёт (а он часто врёт после grant без перезапуска .app).
        // Сбрасывается на каждом старте приложения и при явной отрицательной
        // глубокой проверке.
        if preflightGranted {
            screenPermissionOverride = true
        }
        let screenGranted = preflightGranted || screenPermissionOverride
        let consent = defaults.integer(forKey: consentVersionDefaultsKey) >= Self.currentConsentVersion

        checklist = OnboardingChecklistState(
            microphonePermissionGranted: micGranted,
            speechRecognitionPermissionGranted: speechGranted,
            screenRecordingPermissionGranted: screenGranted,
            oneTimeAcknowledgementAccepted: consent
        )
    }

    @discardableResult
    public func requestMicrophonePermission() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        refresh()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            refresh()
        }
        return granted
    }

    @discardableResult
    public func requestSpeechRecognitionPermission() async -> Bool {
        let status = await Self.resolveSpeechAuthorization()
        refresh()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            refresh()
        }
        return status == .authorized
    }

    @discardableResult
    public func requestScreenRecordingPermission() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        if granted {
            screenPermissionOverride = true
        }
        refresh()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            refresh()
        }
        return granted
    }

    public func acceptOneTimeAcknowledgement() {
        defaults.set(Self.currentConsentVersion, forKey: consentVersionDefaultsKey)
        defaults.set(true, forKey: legacyConsentDefaultsKey)
        refresh()
    }

    public func refreshScreenRecordingViaProbe() async {
        if screenRecordingStatusProvider() {
            setScreenPermissionOverride(true)
            refresh()
            return
        }

        // Ручная "глубокая" проверка по кнопке "Обновить статус":
        // если доступ уже выдан в системе, метод вернет true и не покажет лишний диалог.
        let requestGranted = CGRequestScreenCaptureAccess()
        if requestGranted {
            setScreenPermissionOverride(true)
            refresh()
            return
        }

#if canImport(ScreenCaptureKit)
        if #available(macOS 13.0, *) {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                setScreenPermissionOverride(true)
                refresh()
                return
            } catch {
                // fallback к обновлению ниже
            }
        }
#endif

        if !screenRecordingStatusProvider() {
            setScreenPermissionOverride(false)
        }
        refresh()
    }

    public func synchronizeScreenRecordingPermission() {
        let preflightGranted = screenRecordingStatusProvider()
        if preflightGranted {
            setScreenPermissionOverride(true)
            refresh()
            return
        }

        // Важный шаг: sync-check через request API на MainActor.
        // Если доступ уже выдан в системных настройках, здесь получаем true.
        let requestGranted = CGRequestScreenCaptureAccess()
        if requestGranted {
            setScreenPermissionOverride(true)
        }
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

    nonisolated private static func resolveSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current != .notDetermined {
            return current
        }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func setScreenPermissionOverride(_ granted: Bool) {
        // In-memory only — никакого UserDefaults. См. комментарий у поля.
        screenPermissionOverride = granted
    }

}
