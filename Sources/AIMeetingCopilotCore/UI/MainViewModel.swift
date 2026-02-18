import Foundation
import SwiftUI
import Combine
import QuartzCore
import AppKit

@MainActor
public final class MainViewModel: ObservableObject {
    @Published public private(set) var sessionState: SessionState = .idle
    @Published public private(set) var captureMode: CaptureMode = .off
    @Published public private(set) var transcript: [TranscriptSegment] = []
    @Published public private(set) var isUserSpeaking = false
    @Published public private(set) var lastMicRms: Float = 0
    @Published public private(set) var lastSystemRms: Float = 0
    @Published public private(set) var onboardingReady = false

    @Published public private(set) var activeCard: InsightCard?
    @Published public private(set) var recentCards: [InsightCard] = []
    @Published public private(set) var isCardCollapsed = false

    @Published public var errorMessage: String?

    public let permissionsManager: PermissionsManager

    private let stateMachine = SessionStateMachine()
    private let micCaptureService = MicrophoneCaptureService()
    private let systemAudioService = SystemAudioCaptureService()
    private let asrProvider: ASRProvider
    private let hallucinationFilter = HallucinationFilter()

    private let backendProcessManager = BackendProcessManager()
    private let udsClient = UDSEventClient()

    private var transcriptTask: Task<Void, Never>?
    private var sessionStartTime: TimeInterval = CACurrentMediaTime()
    private var currentSessionID: UUID?
    private var cancellables = Set<AnyCancellable>()

    public init(asrProvider: ASRProvider = WhisperKitProvider(), permissionsManager: PermissionsManager = PermissionsManager()) {
        self.asrProvider = asrProvider
        self.permissionsManager = permissionsManager

        onboardingReady = permissionsManager.checklist.isReadyForCapture

        micCaptureService.onMicEvent = { [weak self] event in
            guard let self else { return }
            self.handleMicEvent(event)
        }

        micCaptureService.onAudioLevel = { [weak self] event in
            self?.lastMicRms = event.micRms
        }

        systemAudioService.onAudioLevel = { [weak self] event in
            self?.lastSystemRms = event.systemRms
        }

        udsClient.onInsightCard = { [weak self] card in
            self?.handleIncomingCard(card)
        }

        udsClient.onError = { [weak self] message in
            DispatchQueue.main.async {
                self?.errorMessage = message
            }
        }

        permissionsManager.$checklist
            .receive(on: DispatchQueue.main)
            .sink { [weak self] checklist in
                self?.onboardingReady = checklist.isReadyForCapture
            }
            .store(in: &cancellables)
    }
}

private struct SessionControlPayload: Codable {
    let event: String
    let session_id: String
    let profile: String
}

private struct PanicPayload: Codable {
    let ts: Double
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
        activeCard = nil
        recentCards.removeAll(keepingCapacity: true)
        isCardCollapsed = false
        sessionStartTime = CACurrentMediaTime()

        Task {
            do {
                let sessionID = try await stateMachine.startCapture()
                currentSessionID = sessionID
                sessionState = .capturing

                let socketPath = try await backendProcessManager.start()
                try await udsClient.connect(path: socketPath)
                try await udsClient.send(
                    type: "session_control",
                    payload: SessionControlPayload(
                        event: "start",
                        session_id: sessionID.uuidString,
                        profile: "negotiation"
                    )
                )

                captureMode = .screenCaptureKit
                try micCaptureService.startCapture(sessionStartTime: sessionStartTime)
                systemAudioService.startCapture(mode: captureMode, sessionStartTime: sessionStartTime)

                transcriptTask?.cancel()
                transcriptTask = Task {
                    do {
                        try await asrProvider.startStream()
                        for await segment in asrProvider.segments {
                            guard let filteredText = hallucinationFilter.apply(text: segment.text, vadDetectedSpeech: true) else {
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

                            do {
                                try await udsClient.send(type: "transcript_segment", payload: normalized)
                            } catch {
                                await MainActor.run {
                                    self.errorMessage = "Ошибка отправки transcript: \(error.localizedDescription)"
                                }
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

            if let currentSessionID {
                try? await udsClient.send(
                    type: "session_control",
                    payload: SessionControlPayload(
                        event: "end",
                        session_id: currentSessionID.uuidString,
                        profile: "negotiation"
                    )
                )
            }

            udsClient.disconnect()
            await backendProcessManager.stop()

            do {
                try await stateMachine.endCapture()
            } catch {
                errorMessage = "Ошибка остановки сессии: \(error.localizedDescription)"
            }

            sessionState = .ended
            captureMode = .off
            isUserSpeaking = false
            isCardCollapsed = false
        }
    }

    func togglePinActiveCard() {
        guard var card = activeCard else { return }
        card.pinned.toggle()
        activeCard = card
        if card.pinned {
            isCardCollapsed = false
        }
        replaceRecent(card)
    }

    func dismissActiveCard() {
        guard var card = activeCard else { return }
        card.dismissed = true
        activeCard = nil
        isCardCollapsed = false
        replaceRecent(card)
    }

    func copyActiveReply() {
        guard let card = activeCard else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(card.replyConfident, forType: .string)
    }

    func triggerPanicCapture() {
        Task {
            do {
                try await udsClient.send(type: "panic_capture", payload: PanicPayload(ts: CACurrentMediaTime()))
            } catch {
                await MainActor.run {
                    self.errorMessage = "Не удалось отправить panic capture: \(error.localizedDescription)"
                }
            }
        }
    }
}

private extension MainViewModel {
    func handleMicEvent(_ event: MicEvent) {
        isUserSpeaking = event.eventType != .speechEnd

        if event.eventType == .speechStart {
            if let card = activeCard, !card.pinned {
                isCardCollapsed = true
            }
        } else if event.eventType == .speechEnd {
            isCardCollapsed = false
        }

        Task {
            do {
                try await udsClient.send(type: "mic_event", payload: event)
            } catch {
                await MainActor.run {
                    self.errorMessage = "Ошибка отправки mic_event: \(error.localizedDescription)"
                }
            }
        }
    }

    func handleIncomingCard(_ card: InsightCard) {
        activeCard = card
        isCardCollapsed = false

        recentCards.insert(card, at: 0)
        if recentCards.count > 3 {
            recentCards = Array(recentCards.prefix(3))
        }
    }

    func replaceRecent(_ card: InsightCard) {
        if let idx = recentCards.firstIndex(where: { $0.id == card.id }) {
            recentCards[idx] = card
        }
    }
}
