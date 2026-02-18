import Foundation
import SwiftUI
import Combine
import QuartzCore

@MainActor
public final class MainViewModel: ObservableObject {
    @Published public private(set) var sessionState: SessionState = .idle
    @Published public private(set) var captureMode: CaptureMode = .off
    @Published public private(set) var transcript: [TranscriptSegment] = []
    @Published public private(set) var isUserSpeaking = false
    @Published public private(set) var lastMicRms: Float = 0
    @Published public private(set) var lastSystemRms: Float = 0
    @Published public private(set) var onboardingReady = false
    @Published public var errorMessage: String?

    public let permissionsManager: PermissionsManager

    private let stateMachine = SessionStateMachine()
    private let micCaptureService = MicrophoneCaptureService()
    private let systemAudioService = SystemAudioCaptureService()
    private let asrProvider: ASRProvider
    private let hallucinationFilter = HallucinationFilter()

    private var transcriptTask: Task<Void, Never>?
    private var sessionStartTime: TimeInterval = CACurrentMediaTime()

    public init(asrProvider: ASRProvider = WhisperKitProvider(), permissionsManager: PermissionsManager = PermissionsManager()) {
        self.asrProvider = asrProvider
        self.permissionsManager = permissionsManager

        onboardingReady = permissionsManager.checklist.isReadyForCapture

        micCaptureService.onMicEvent = { [weak self] event in
            guard let self else { return }
            self.isUserSpeaking = event.eventType != .speechEnd
        }

        micCaptureService.onAudioLevel = { [weak self] event in
            self?.lastMicRms = event.micRms
        }

        systemAudioService.onAudioLevel = { [weak self] event in
            self?.lastSystemRms = event.systemRms
        }

        permissionsManager.$checklist
            .receive(on: DispatchQueue.main)
            .sink { [weak self] checklist in
                self?.onboardingReady = checklist.isReadyForCapture
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()
}

public extension MainViewModel {
    func refreshPermissions() {
        permissionsManager.refresh()
    }

    func acceptAcknowledgement() {
        permissionsManager.acceptOneTimeAcknowledgement()
    }

    func requestMicPermission() async {
        _ = await permissionsManager.requestMicrophonePermission()
    }

    func requestScreenPermission() {
        _ = permissionsManager.requestScreenRecordingPermission()
    }

    func startCapture() {
        guard onboardingReady else {
            errorMessage = "Завершите onboarding перед стартом захвата"
            return
        }

        errorMessage = nil
        transcript.removeAll(keepingCapacity: true)
        sessionStartTime = CACurrentMediaTime()

        Task {
            do {
                _ = try await stateMachine.startCapture()
                sessionState = .capturing

                captureMode = .screenCaptureKit
                try micCaptureService.startCapture(sessionStartTime: sessionStartTime)
                systemAudioService.startCapture(mode: captureMode, sessionStartTime: sessionStartTime)

                transcriptTask?.cancel()
                transcriptTask = Task {
                    do {
                        try await asrProvider.startStream()
                        for await segment in asrProvider.segments {
                            let vadGate = true
                            guard let filteredText = hallucinationFilter.apply(text: segment.text, vadDetectedSpeech: vadGate) else {
                                continue
                            }
                            let normalized = TranscriptSegment(
                                schemaVersion: segment.schemaVersion,
                                seq: segment.seq,
                                utteranceId: segment.utteranceId,
                                isFinal: segment.isFinal,
                                speaker: segment.speaker,
                                text: filteredText,
                                tsStart: segment.tsStart,
                                tsEnd: segment.tsEnd,
                                speakerConfidence: segment.speakerConfidence
                            )
                            await MainActor.run {
                                self.transcript.append(normalized)
                            }
                        }
                    } catch {
                        await MainActor.run {
                            self.errorMessage = "ASR stream error: \(error.localizedDescription)"
                        }
                    }
                }
            } catch {
                errorMessage = "Не удалось запустить сессию: \(error.localizedDescription)"
            }
        }
    }

    func stopCapture() {
        Task {
            transcriptTask?.cancel()
            transcriptTask = nil

            await asrProvider.stopStream()
            micCaptureService.stopCapture()
            systemAudioService.stopCapture()

            do {
                try await stateMachine.endCapture()
            } catch {
                errorMessage = "Ошибка остановки сессии: \(error.localizedDescription)"
            }

            sessionState = .ended
            captureMode = .off
            isUserSpeaking = false
        }
    }
}
