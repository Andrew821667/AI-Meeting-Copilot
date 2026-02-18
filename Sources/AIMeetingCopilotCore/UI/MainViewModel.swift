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

    @Published public private(set) var lastSessionSummary: SessionSummary?
    @Published public private(set) var sessionHistory: [SessionHistoryItem] = []
    @Published public private(set) var excludedPhrases: [String] = []
    @Published public private(set) var runtimeWarningMessage: String?
    @Published public var errorMessage: String?
    @Published public private(set) var calendarStatusText: String = "Календарь: не проверен"
    @Published public private(set) var calendarSuggestedProfileID: String?

    @Published public var selectedProfileID: String = "negotiation"
    @Published public var selectedASRProviderID: String = ASRProviderOption.whisperKit.id
    @Published public var profileSettings: ProfileRuntimeSettings = .defaults(for: "negotiation")

    public let availableProfiles: [ProfileOption] = ProfileOption.all
    public let availableASRProviders: [ASRProviderOption] = ASRProviderOption.all
    public let permissionsManager: PermissionsManager

    private let stateMachine = SessionStateMachine()
    private let micCaptureService = MicrophoneCaptureService()
    private let systemAudioService = SystemAudioCaptureService()
    private var asrProvider: ASRProvider
    private let hallucinationFilter = HallucinationFilter()

    private let backendProcessManager = BackendProcessManager()
    private let udsClient = UDSEventClient()
    private let historyStore = SessionHistoryStore()
    private let excludePhraseStore = ExcludePhraseStore()
    private let calendarSuggester = CalendarProfileSuggester()

    private var transcriptTask: Task<Void, Never>?
    private var systemStateTask: Task<Void, Never>?
    private var sessionStartTime: TimeInterval = CACurrentMediaTime()
    private var currentSessionID: UUID?
    private var cancellables = Set<AnyCancellable>()

    private var lastAudioLevelSentAt: TimeInterval = 0
    private var lastThermalState: ProcessInfo.ThermalState = .nominal
    private let telemetrySeq = SequenceNumberGenerator(startAt: 100_000)
    private var isApplyingCalendarSuggestion = false
    private var hasManualProfileSelection = false

    public init(asrProvider: ASRProvider = WhisperKitProvider(), permissionsManager: PermissionsManager = PermissionsManager()) {
        self.asrProvider = asrProvider
        self.permissionsManager = permissionsManager

        onboardingReady = permissionsManager.checklist.isReadyForCapture
        profileSettings = .defaults(for: selectedProfileID)
        sessionHistory = historyStore.loadHistory()
        excludedPhrases = excludePhraseStore.load(profileID: selectedProfileID)

        micCaptureService.onMicEvent = { [weak self] event in
            guard let self else { return }
            self.handleMicEvent(event)
        }

        micCaptureService.onAudioLevel = { [weak self] event in
            self?.handleMicAudioLevel(event)
        }

        systemAudioService.onAudioLevel = { [weak self] event in
            self?.handleSystemAudioLevel(event)
        }

        udsClient.onInsightCard = { [weak self] card in
            self?.handleIncomingCard(card)
        }

        udsClient.onSessionSummary = { [weak self] summary in
            self?.lastSessionSummary = summary
            self?.reloadSessionHistory()
        }

        udsClient.onSessionAck = { _ in }

        udsClient.onRuntimeWarning = { [weak self] message in
            self?.showRuntimeWarning(message)
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

        $selectedProfileID
            .dropFirst()
            .sink { [weak self] profileID in
                guard let self else { return }
                if self.sessionState == .capturing || self.sessionState == .paused {
                    return
                }
                if !self.isApplyingCalendarSuggestion {
                    self.hasManualProfileSelection = true
                }
                self.profileSettings = .defaults(for: profileID)
                self.reloadExcludedPhrases()
            }
            .store(in: &cancellables)

        $selectedASRProviderID
            .dropFirst()
            .sink { [weak self] providerID in
                guard let self else { return }
                if self.sessionState == .capturing || self.sessionState == .paused {
                    return
                }
                self.asrProvider = ASRProviderFactory.make(optionID: providerID)
            }
            .store(in: &cancellables)
    }
}

private struct SessionControlPayload: Codable {
    let event: String
    let sessionID: String
    let profile: String
    let profileOverrides: ProfileRuntimeSettings?

    enum CodingKeys: String, CodingKey {
        case event
        case sessionID = "session_id"
        case profile
        case profileOverrides = "profile_overrides"
    }
}

private struct PanicPayload: Codable {
    let ts: Double
}

private struct CardFeedbackPayload: Codable {
    let sessionID: String
    let cardID: String
    let useful: Bool
    let excluded: Bool
    let triggerReason: String
    let insight: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case cardID = "card_id"
        case useful
        case excluded
        case triggerReason = "trigger_reason"
        case insight
    }
}

private struct ExcludePhrasePayload: Codable {
    let sessionID: String
    let phrase: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case phrase
    }
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

    func reloadSessionHistory() {
        sessionHistory = historyStore.loadHistory()
    }

    func reloadExcludedPhrases() {
        excludedPhrases = excludePhraseStore.load(profileID: selectedProfileID)
    }

    func addManualExcludedPhrase(_ phrase: String) {
        let ok = excludePhraseStore.add(profileID: selectedProfileID, phrase: phrase)
        if ok {
            reloadExcludedPhrases()
        } else {
            errorMessage = "Не удалось добавить исключение: фраза слишком короткая или недоступна база."
        }
    }

    func removeManualExcludedPhrase(_ phrase: String) {
        let ok = excludePhraseStore.remove(profileID: selectedProfileID, phrase: phrase)
        if ok {
            reloadExcludedPhrases()
        } else {
            errorMessage = "Не удалось удалить исключение."
        }
    }

    func resetProfileSettingsToDefaults() {
        profileSettings = .defaults(for: selectedProfileID)
    }

    func refreshCalendarSuggestion(autoApply: Bool = false) {
        Task {
            let result = await calendarSuggester.fetchNearestSuggestion()
            await MainActor.run {
                switch result {
                case .permissionDenied:
                    self.calendarSuggestedProfileID = nil
                    self.calendarStatusText = "Календарь: доступ не предоставлен"
                case .noUpcomingEvents:
                    self.calendarSuggestedProfileID = nil
                    self.calendarStatusText = "Календарь: ближайших встреч не найдено"
                case .noProfileMatch:
                    self.calendarSuggestedProfileID = nil
                    self.calendarStatusText = "Календарь: профиль для встречи не определен"
                case .suggestion(let suggestion):
                    self.calendarSuggestedProfileID = suggestion.profileID
                    let profileTitle = ProfileOption.title(for: suggestion.profileID)
                    self.calendarStatusText = "Календарь: «\(suggestion.eventTitle)» -> \(profileTitle)"
                    if autoApply {
                        self.applyCalendarSuggestedProfile(automatic: true)
                    }
                }
            }
        }
    }

    func applyCalendarSuggestedProfile() {
        applyCalendarSuggestedProfile(automatic: false)
    }

    func startCapture() {
        guard onboardingReady else {
            errorMessage = "Завершите первичную настройку перед запуском захвата"
            return
        }

        errorMessage = nil
        transcript.removeAll(keepingCapacity: true)
        activeCard = nil
        recentCards.removeAll(keepingCapacity: true)
        isCardCollapsed = false
        lastSessionSummary = nil
        sessionStartTime = CACurrentMediaTime()
        telemetrySeq.reset(to: 100_000)

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
                        sessionID: sessionID.uuidString,
                        profile: selectedProfileID,
                        profileOverrides: profileSettings
                    )
                )

                captureMode = .screenCaptureKit
                try micCaptureService.startCapture(sessionStartTime: sessionStartTime)
                systemAudioService.startCapture(mode: captureMode, sessionStartTime: sessionStartTime)

                startSystemStateLoop()
                startASRStreamingTask()
            } catch {
                errorMessage = "Не удалось запустить сессию: \(error.localizedDescription)"
            }
        }
    }

    func pauseCapture() {
        Task {
            guard sessionState == .capturing else { return }
            do {
                try await stateMachine.pauseCapture()

                if let currentSessionID {
                    try await udsClient.send(
                        type: "session_control",
                        payload: SessionControlPayload(
                            event: "pause",
                            sessionID: currentSessionID.uuidString,
                            profile: selectedProfileID,
                            profileOverrides: nil
                        )
                    )
                }

                await asrProvider.stopStream()
                transcriptTask?.cancel()
                transcriptTask = nil

                micCaptureService.stopCapture()
                systemAudioService.stopCapture()
                stopSystemStateLoop()

                sessionState = .paused
                captureMode = .off
            } catch {
                errorMessage = "Ошибка перехода в паузу: \(error.localizedDescription)"
            }
        }
    }

    func resumeCapture() {
        Task {
            guard sessionState == .paused else { return }
            do {
                try await stateMachine.resumeCapture()

                if let currentSessionID {
                    try await udsClient.send(
                        type: "session_control",
                        payload: SessionControlPayload(
                            event: "resume",
                            sessionID: currentSessionID.uuidString,
                            profile: selectedProfileID,
                            profileOverrides: nil
                        )
                    )
                }

                await asrProvider.reset()
                captureMode = .screenCaptureKit
                try micCaptureService.startCapture(sessionStartTime: sessionStartTime)
                systemAudioService.startCapture(mode: captureMode, sessionStartTime: sessionStartTime)

                startSystemStateLoop()
                startASRStreamingTask()

                sessionState = .capturing
            } catch {
                errorMessage = "Ошибка возобновления сессии: \(error.localizedDescription)"
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
            stopSystemStateLoop()

            if let currentSessionID {
                try? await udsClient.send(
                    type: "session_control",
                    payload: SessionControlPayload(
                        event: "end",
                        sessionID: currentSessionID.uuidString,
                        profile: selectedProfileID,
                        profileOverrides: nil
                    )
                )
            }

            try? await Task.sleep(nanoseconds: 200_000_000)

            udsClient.disconnect()
            await backendProcessManager.stop()

            do {
                try await stateMachine.endCapture()
            } catch {
                errorMessage = "Ошибка завершения сессии: \(error.localizedDescription)"
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
                    self.errorMessage = "Не удалось отправить ручной захват: \(error.localizedDescription)"
                }
            }
        }
    }

    func markActiveCardUseful() {
        sendActiveCardFeedback(useful: true, excluded: false)
    }

    func markActiveCardUseless() {
        sendActiveCardFeedback(useful: false, excluded: false)
    }

    func excludeActiveCardPattern() {
        guard var card = activeCard, let sessionID = currentSessionID else { return }

        card.excluded = true
        activeCard = card
        replaceRecent(card)

        let phrase = extractExcludePhrase(from: card)
        _ = excludePhraseStore.add(profileID: selectedProfileID, phrase: phrase)
        reloadExcludedPhrases()
        Task {
            do {
                try await udsClient.send(
                    type: "exclude_phrase",
                    payload: ExcludePhrasePayload(sessionID: sessionID.uuidString, phrase: phrase)
                )
                try await udsClient.send(
                    type: "card_feedback",
                    payload: CardFeedbackPayload(
                        sessionID: sessionID.uuidString,
                        cardID: card.id,
                        useful: false,
                        excluded: true,
                        triggerReason: card.triggerReason,
                        insight: card.insight
                    )
                )
            } catch {
                await MainActor.run {
                    self.errorMessage = "Не удалось сохранить исключение: \(error.localizedDescription)"
                }
            }
        }
    }
}

private extension MainViewModel {
    func showRuntimeWarning(_ message: String) {
        runtimeWarningMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            await MainActor.run {
                if self.runtimeWarningMessage == message {
                    self.runtimeWarningMessage = nil
                }
            }
        }
    }

    func applyCalendarSuggestedProfile(automatic: Bool) {
        guard let suggested = calendarSuggestedProfileID else { return }
        guard sessionState != .capturing && sessionState != .paused else { return }

        if automatic {
            if hasManualProfileSelection {
                return
            }
            if selectedProfileID != "negotiation" {
                return
            }
        }

        isApplyingCalendarSuggestion = true
        selectedProfileID = suggested
        profileSettings = .defaults(for: suggested)
        isApplyingCalendarSuggestion = false

        let profileTitle = ProfileOption.title(for: suggested)
        if automatic {
            calendarStatusText = "Календарь: профиль применен автоматически -> \(profileTitle)"
        } else {
            calendarStatusText = "Календарь: профиль применен -> \(profileTitle)"
        }
    }

    func sendActiveCardFeedback(useful: Bool, excluded: Bool) {
        guard let card = activeCard, let sessionID = currentSessionID else { return }

        Task {
            do {
                try await udsClient.send(
                    type: "card_feedback",
                    payload: CardFeedbackPayload(
                        sessionID: sessionID.uuidString,
                        cardID: card.id,
                        useful: useful,
                        excluded: excluded,
                        triggerReason: card.triggerReason,
                        insight: card.insight
                    )
                )
            } catch {
                await MainActor.run {
                    self.errorMessage = "Не удалось отправить обратную связь: \(error.localizedDescription)"
                }
            }
        }
    }

    func extractExcludePhrase(from card: InsightCard) -> String {
        if let range = card.triggerReason.range(of: ":") {
            let candidate = card.triggerReason[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty {
                return String(candidate)
            }
        }

        if let firstSentence = card.insight.split(separator: ".").first, !firstSentence.isEmpty {
            return String(firstSentence).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return card.insight
    }

    func startASRStreamingTask() {
        transcriptTask?.cancel()
        transcriptTask = Task {
            do {
                try await asrProvider.startStream()
                for await segment in asrProvider.segments {
                    guard sessionState == .capturing else { break }
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
                            self.errorMessage = "Ошибка отправки транскрипции: \(error.localizedDescription)"
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Ошибка потока ASR: \(error.localizedDescription)"
                }
            }
        }
    }

    func startSystemStateLoop() {
        stopSystemStateLoop()
        lastThermalState = ProcessInfo.processInfo.thermalState

        systemStateTask = Task {
            while !Task.isCancelled {
                let event = SystemStateEvent(
                    seq: telemetrySeq.next(),
                    timestamp: CACurrentMediaTime() - sessionStartTime,
                    batteryLevel: currentBatteryLevel(),
                    thermalState: thermalStateString(ProcessInfo.processInfo.thermalState)
                )

                do {
                    try await udsClient.send(type: "system_state", payload: event)
                } catch {
                    await MainActor.run {
                        self.errorMessage = "Ошибка отправки системного состояния: \(error.localizedDescription)"
                    }
                }

                let currentThermal = ProcessInfo.processInfo.thermalState
                if currentThermal != lastThermalState {
                    lastThermalState = currentThermal
                    let immediate = SystemStateEvent(
                        seq: telemetrySeq.next(),
                        timestamp: CACurrentMediaTime() - sessionStartTime,
                        batteryLevel: currentBatteryLevel(),
                        thermalState: thermalStateString(currentThermal)
                    )
                    try? await udsClient.send(type: "system_state", payload: immediate)
                }

                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    func stopSystemStateLoop() {
        systemStateTask?.cancel()
        systemStateTask = nil
    }

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
                    self.errorMessage = "Ошибка отправки события микрофона: \(error.localizedDescription)"
                }
            }
        }
    }

    func handleMicAudioLevel(_ event: AudioLevelEvent) {
        lastMicRms = event.micRms
        sendThrottledAudioLevelIfNeeded()
    }

    func handleSystemAudioLevel(_ event: AudioLevelEvent) {
        lastSystemRms = event.systemRms
        sendThrottledAudioLevelIfNeeded()
    }

    func sendThrottledAudioLevelIfNeeded() {
        guard sessionState == .capturing else { return }
        let now = CACurrentMediaTime()
        if (now - lastAudioLevelSentAt) < 1.0 {
            return
        }
        lastAudioLevelSentAt = now

        let payload = AudioLevelEvent(
            seq: telemetrySeq.next(),
            timestamp: now - sessionStartTime,
            micRms: lastMicRms,
            systemRms: lastSystemRms
        )

        Task {
            try? await udsClient.send(type: "audio_level", payload: payload)
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

    func thermalStateString(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "fair"
        }
    }

    func currentBatteryLevel() -> Float {
        return 1.0
    }
}
