import Foundation
import SwiftUI
import Combine
import QuartzCore
import AppKit

public enum CaptureSourceMode: String, CaseIterable, Identifiable, Sendable {
    case meeting = "meeting"
    case micOnly = "mic_only"
    case offlineMeetings = "offline_meetings"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .meeting:
            return "Встреча (собеседник + я)"
        case .micOnly:
            return "Только микрофон (офлайн)"
        case .offlineMeetings:
            return "Офлайн встречи (анализ записи)"
        }
    }

    public var requiresScreenPermission: Bool {
        switch self {
        case .meeting:
            return true
        case .micOnly, .offlineMeetings:
            return false
        }
    }
}

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
    @Published public private(set) var activeCards: [InsightCard] = []
    @Published public private(set) var recentCards: [InsightCard] = []
    @Published public private(set) var isCardCollapsed = false

    @Published public private(set) var lastSessionSummary: SessionSummary?
    @Published public private(set) var sessionHistory: [SessionHistoryItem] = []
    @Published public private(set) var latestSavedCards: [InsightCard] = []
    @Published public private(set) var excludedPhrases: [String] = []
    @Published public private(set) var runtimeWarningMessage: String?
    @Published public var errorMessage: String?
    @Published public private(set) var calendarStatusText: String = "Календарь: не проверен"
    @Published public private(set) var calendarSuggestedProfileID: String?

    @Published public var selectedProfileID: String = "negotiation"
    @Published public var selectedASRProviderID: String = ASRProviderOption.whisperKit.id
    @Published public var selectedCaptureSourceMode: CaptureSourceMode = .meeting
    @Published public var profileSettings: ProfileRuntimeSettings = .defaults(for: "negotiation")

    public let availableProfiles: [ProfileOption] = ProfileOption.all
    public let availableASRProviders: [ASRProviderOption] = ASRProviderOption.all
    public let availableCaptureSourceModes: [CaptureSourceMode] = CaptureSourceMode.allCases
    public let permissionsManager: PermissionsManager

    private let stateMachine = SessionStateMachine()
    private let micCaptureService = MicrophoneCaptureService()
    private let systemAudioService = SystemAudioCaptureService()
    private var asrProvider: ASRProvider
    private var micASRProvider: ASRProvider?
    private let hallucinationFilter = HallucinationFilter()

    private let backendProcessManager = BackendProcessManager()
    private let udsClient = UDSEventClient()
    private let historyStore = SessionHistoryStore()
    private let savedCardStore = SavedCardStore()
    private let excludePhraseStore = ExcludePhraseStore()
    private let calendarSuggester = CalendarProfileSuggester()
    private let detachedCardWindowManager = DetachedCardWindowManager()

    private var transcriptTask: Task<Void, Never>?
    private var micTranscriptTask: Task<Void, Never>?
    private var systemStateTask: Task<Void, Never>?
    private var sessionStartTime: TimeInterval = CACurrentMediaTime()
    private var currentSessionID: UUID?
    private var cancellables = Set<AnyCancellable>()

    private var lastAudioLevelSentAt: TimeInterval = 0
    private var lastThermalState: ProcessInfo.ThermalState = .nominal
    private let telemetrySeq = SequenceNumberGenerator(startAt: 100_000)
    private var isApplyingCalendarSuggestion = false
    private var hasManualProfileSelection = false
    private var permissionBurstTask: Task<Void, Never>?
    private let forceModeDefaultsKeyPrefix = "ai.meeting.copilot.force_mode."
    private var cardReanalysisContinuations: [String: CheckedContinuation<String, Never>] = [:]

    public init(asrProvider: ASRProvider = WhisperKitProvider(), permissionsManager: PermissionsManager = PermissionsManager()) {
        self.asrProvider = asrProvider
        self.permissionsManager = permissionsManager

        onboardingReady = false
        profileSettings = .defaults(for: selectedProfileID)
        profileSettings.forceAnswerMode = loadPersistedForceMode(for: selectedProfileID)
        sessionHistory = historyStore.loadHistory()
        latestSavedCards = savedCardStore.loadLatest(limit: 50)
        excludedPhrases = excludePhraseStore.load(profileID: selectedProfileID)
        recomputeOnboardingReadiness()

        micCaptureService.onMicEvent = { [weak self] event in
            DispatchQueue.main.async { [weak self] in
                self?.handleMicEvent(event)
            }
        }

        micCaptureService.onAudioLevel = { [weak self] event in
            DispatchQueue.main.async { [weak self] in
                self?.handleMicAudioLevel(event)
            }
        }

        systemAudioService.onAudioLevel = { [weak self] event in
            DispatchQueue.main.async { [weak self] in
                self?.handleSystemAudioLevel(event)
            }
        }

        systemAudioService.onCaptureModeChanged = { [weak self] mode, reason in
            DispatchQueue.main.async { [weak self] in
                self?.captureMode = mode
                self?.errorMessage = reason
            }
        }

        udsClient.onInsightCard = { [weak self] card in
            DispatchQueue.main.async { [weak self] in
                self?.handleIncomingCard(card)
            }
        }

        udsClient.onSessionSummary = { [weak self] summary in
            DispatchQueue.main.async { [weak self] in
                self?.lastSessionSummary = summary
                self?.reloadSessionHistory()
            }
        }

        udsClient.onSessionAck = { _ in }

        udsClient.onRuntimeWarning = { [weak self] message in
            DispatchQueue.main.async { [weak self] in
                self?.showRuntimeWarning(message)
            }
        }

        udsClient.onCardReanalysisReply = { [weak self] reply in
            DispatchQueue.main.async { [weak self] in
                self?.handleCardReanalysisReply(reply)
            }
        }

        udsClient.onError = { [weak self] message in
            DispatchQueue.main.async {
                self?.errorMessage = message
            }
        }

        permissionsManager.$checklist
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recomputeOnboardingReadiness()
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
                self.profileSettings.forceAnswerMode = self.loadPersistedForceMode(for: profileID)
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
                self.asrProvider = self.makeASRProvider(optionID: providerID, captureMode: self.selectedCaptureSourceMode)
                self.recomputeOnboardingReadiness()
            }
            .store(in: &cancellables)

        $selectedCaptureSourceMode
            .dropFirst()
            .sink { [weak self] mode in
                guard let self else { return }
                if self.sessionState != .capturing && self.sessionState != .paused {
                    self.asrProvider = self.makeASRProvider(optionID: self.selectedASRProviderID, captureMode: mode)
                }
                self.recomputeOnboardingReadiness()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.refreshPermissionsOnAppActivated()
            }
            .store(in: &cancellables)

        self.asrProvider = makeASRProvider(optionID: selectedASRProviderID, captureMode: selectedCaptureSourceMode)
    }
}

private struct SessionControlPayload: Codable, Sendable {
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

private struct PanicPayload: Codable, Sendable {
    let ts: Double
}

private struct CardFeedbackPayload: Codable, Sendable {
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

private struct ExcludePhrasePayload: Codable, Sendable {
    let sessionID: String
    let phrase: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case phrase
    }
}

private struct CardReanalysisPayload: Codable, Sendable {
    let requestID: String
    let sessionID: String
    let profile: String
    let cardID: String
    let agentName: String
    let triggerReason: String
    let insight: String
    let replyCautious: String
    let replyConfident: String
    let userQuery: String

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case sessionID = "session_id"
        case profile
        case cardID = "card_id"
        case agentName = "agent_name"
        case triggerReason = "trigger_reason"
        case insight
        case replyCautious = "reply_cautious"
        case replyConfident = "reply_confident"
        case userQuery = "user_query"
    }
}

public extension MainViewModel {
    var microphonePermissionGranted: Bool {
        permissionsManager.checklist.microphonePermissionGranted
    }

    var speechPermissionGranted: Bool {
        permissionsManager.checklist.speechRecognitionPermissionGranted
    }

    var screenPermissionGranted: Bool {
        permissionsManager.checklist.screenRecordingPermissionGranted
    }

    var consentAccepted: Bool {
        permissionsManager.checklist.oneTimeAcknowledgementAccepted
    }

    var hasPendingPermissionItems: Bool {
        !microphonePermissionGranted || !speechPermissionGranted || !consentAccepted || (requiresScreenPermission && !screenPermissionGranted)
    }

    var requiresScreenPermission: Bool {
        selectedCaptureSourceMode.requiresScreenPermission
    }

    var requiresSpeechPermission: Bool {
        selectedASRProviderID == ASRProviderOption.whisperKit.id
    }

    var speechPermissionMissingForSelectedASR: Bool {
        requiresSpeechPermission && !permissionsManager.checklist.speechRecognitionPermissionGranted
    }

    var screenPermissionMissingForMeetingMode: Bool {
        selectedCaptureSourceMode == .meeting && !permissionsManager.checklist.screenRecordingPermissionGranted
    }

    var startGuideText: String {
        let checklist = permissionsManager.checklist
        if onboardingReady {
            switch selectedCaptureSourceMode {
            case .meeting:
                return "Готово: нажмите «Начать захват», чтобы анализировать встречу в реальном времени."
            case .micOnly:
                return "Готово: нажмите «Начать захват» для офлайн-режима только через микрофон."
            case .offlineMeetings:
                return "Готово: нажмите «Начать захват» и говорите в микрофон для анализа офлайн-встречи."
            }
        }

        var missing: [String] = []
        if !checklist.microphonePermissionGranted {
            missing.append("доступ к микрофону")
        }
        if requiresSpeechPermission && !checklist.speechRecognitionPermissionGranted {
            missing.append("доступ к распознаванию речи")
        }
        if requiresScreenPermission && !checklist.screenRecordingPermissionGranted {
            missing.append("доступ к записи экрана (аудио собеседника)")
        }
        if !checklist.oneTimeAcknowledgementAccepted {
            missing.append("подтверждение права на анализ")
        }
        if missing.isEmpty {
            return "Проверьте выбранный режим и нажмите «Начать захват»."
        }
        return "Перед запуском нужно: \(missing.joined(separator: ", "))."
    }

    var startButtonTitle: String {
        "Начать захват"
    }

    var answerModeButtonTitle: String {
        profileSettings.forceAnswerMode ? "Ответы: ВКЛ" : "Ответы: ВЫКЛ"
    }

    func toggleForceAnswerMode() {
        profileSettings.forceAnswerMode.toggle()
        persistForceMode(profileSettings.forceAnswerMode, for: selectedProfileID)
        sendProfileOverridesUpdateIfNeeded()
    }

    func refreshPermissions() {
        permissionsManager.refresh()
    }

    func refreshPermissionsWithProbe() {
        permissionsManager.refresh()
        guard requiresScreenPermission else { return }
        guard !permissionsManager.checklist.screenRecordingPermissionGranted else { return }
        permissionsManager.synchronizeScreenRecordingPermission()
        guard !permissionsManager.checklist.screenRecordingPermissionGranted else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.permissionsManager.refreshScreenRecordingViaProbe()
        }
    }

    func acceptAcknowledgement() {
        permissionsManager.acceptOneTimeAcknowledgement()
    }

    func requestMicPermission() async {
        _ = await permissionsManager.requestMicrophonePermission()
    }

    func requestSpeechPermission() async {
        _ = await permissionsManager.requestSpeechRecognitionPermission()
    }

    func requestScreenPermission() {
        _ = permissionsManager.requestScreenRecordingPermission()
    }

    func openSystemSettingsMicrophone() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(url)
        schedulePermissionRefreshBurst()
    }

    func openSystemSettingsScreenRecording() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
        schedulePermissionRefreshBurst()
    }

    func openSystemSettingsSpeechRecognition() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") else {
            return
        }
        NSWorkspace.shared.open(url)
        schedulePermissionRefreshBurst()
    }

    func reloadSessionHistory() {
        sessionHistory = historyStore.loadHistory()
    }

    func reloadLatestSavedCards() {
        latestSavedCards = savedCardStore.loadLatest(limit: 50)
    }

    func loadSessionCards(item: SessionHistoryItem) -> [InsightCard] {
        savedCardStore.loadBySessionOrImport(sessionID: item.id, exportPath: item.exportPath)
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
        profileSettings.forceAnswerMode = loadPersistedForceMode(for: selectedProfileID)
    }

    func refreshCalendarSuggestion(autoApply: Bool = false) {
        Task { @MainActor in
            let result = await calendarSuggester.fetchNearestSuggestion()
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

    func applyCalendarSuggestedProfile() {
        applyCalendarSuggestedProfile(automatic: false)
    }

    func startCapture() {
        guard onboardingReady else {
            errorMessage = startGuideText
            return
        }

        errorMessage = nil
        transcript.removeAll(keepingCapacity: true)
        activeCard = nil
        activeCards.removeAll(keepingCapacity: true)
        recentCards.removeAll(keepingCapacity: true)
        isCardCollapsed = false
        lastSessionSummary = nil
        detachedCardWindowManager.closeAll()
        sessionStartTime = CACurrentMediaTime()
        telemetrySeq.reset(to: 100_000)

        Task {
            do {
                asrProvider = makeASRProvider(optionID: selectedASRProviderID, captureMode: selectedCaptureSourceMode)
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

                captureMode = selectedCaptureSourceMode == .meeting ? .screenCaptureKit : .micOnly
                try micCaptureService.startCapture(sessionStartTime: sessionStartTime)
                systemAudioService.startCapture(mode: captureMode, sessionStartTime: sessionStartTime)

                // В meeting-режиме запускаем второй ASR для транскрипции микрофона (ME)
                if selectedCaptureSourceMode == .meeting {
                    micASRProvider = SpeechASRProvider()
                } else {
                    micASRProvider = nil
                }

                startSystemStateLoop()
                startASRStreamingTask()
                startMicASRStreamingTaskIfNeeded()
            } catch {
                transcriptTask?.cancel()
                transcriptTask = nil
                micTranscriptTask?.cancel()
                micTranscriptTask = nil
                stopSystemStateLoop()
                micCaptureService.stopCapture()
                systemAudioService.stopCapture()
                udsClient.disconnect()
                await backendProcessManager.stop()
                try? await stateMachine.endCapture()
                currentSessionID = nil
                sessionState = .idle
                captureMode = .off
                isUserSpeaking = false
                activeCard = nil
                activeCards.removeAll(keepingCapacity: true)
                detachedCardWindowManager.closeAll()

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

                await micASRProvider?.stopStream()
                micTranscriptTask?.cancel()
                micTranscriptTask = nil

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
                await micASRProvider?.reset()
                captureMode = selectedCaptureSourceMode == .meeting ? .screenCaptureKit : .micOnly
                try micCaptureService.startCapture(sessionStartTime: sessionStartTime)
                systemAudioService.startCapture(mode: captureMode, sessionStartTime: sessionStartTime)

                startSystemStateLoop()
                startASRStreamingTask()
                startMicASRStreamingTaskIfNeeded()

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
            micTranscriptTask?.cancel()
            micTranscriptTask = nil

            await asrProvider.stopStream()
            await micASRProvider?.stopStream()
            micASRProvider = nil
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
            activeCard = nil
            activeCards.removeAll(keepingCapacity: true)
            detachedCardWindowManager.closeAll()
        }
    }

    func togglePinActiveCard() {
        guard let id = activeCard?.id else { return }
        togglePin(cardID: id)
    }

    func togglePin(cardID: String) {
        guard let idx = activeCards.firstIndex(where: { $0.id == cardID }) else { return }
        activeCards[idx].pinned.toggle()
        if activeCards[idx].pinned {
            isCardCollapsed = false
        }
        syncActiveCard()
        replaceRecent(activeCards[idx])
    }

    func dismissActiveCard() {
        guard let id = activeCard?.id else { return }
        dismissCard(cardID: id)
    }

    func dismissCard(cardID: String) {
        guard let idx = activeCards.firstIndex(where: { $0.id == cardID }) else { return }
        var card = activeCards[idx]
        card.dismissed = true
        activeCards.remove(at: idx)
        isCardCollapsed = false
        syncActiveCard()
        replaceRecent(card)
    }

    func copyActiveReply() {
        guard let id = activeCard?.id else { return }
        copyReply(cardID: id)
    }

    func copyReply(cardID: String) {
        guard let card = activeCards.first(where: { $0.id == cardID }) else { return }
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

    func sendProfileOverridesUpdateIfNeeded() {
        guard let currentSessionID else { return }
        guard sessionState == .capturing || sessionState == .paused else { return }

        Task {
            do {
                try await udsClient.send(
                    type: "session_control",
                    payload: SessionControlPayload(
                        event: "profile_update",
                        sessionID: currentSessionID.uuidString,
                        profile: selectedProfileID,
                        profileOverrides: profileSettings
                    )
                )
            } catch {
                await MainActor.run {
                    self.errorMessage = "Не удалось обновить режим ответов: \(error.localizedDescription)"
                }
            }
        }
    }

    func markActiveCardUseful() {
        guard let id = activeCard?.id else { return }
        markCardUseful(cardID: id)
    }

    func markCardUseful(cardID: String) {
        guard let card = activeCards.first(where: { $0.id == cardID }) else { return }
        sendCardFeedback(card: card, useful: true, excluded: false)
    }

    func markActiveCardUseless() {
        guard let id = activeCard?.id else { return }
        markCardUseless(cardID: id)
    }

    func markCardUseless(cardID: String) {
        guard let card = activeCards.first(where: { $0.id == cardID }) else { return }
        sendCardFeedback(card: card, useful: false, excluded: false)
    }

    func excludeActiveCardPattern() {
        guard let id = activeCard?.id else { return }
        excludeCardPattern(cardID: id)
    }

    func excludeCardPattern(cardID: String) {
        guard let sessionID = currentSessionID else { return }
        guard let idx = activeCards.firstIndex(where: { $0.id == cardID }) else { return }

        activeCards[idx].excluded = true
        let card = activeCards[idx]
        syncActiveCard()
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

    func detachCard(cardID: String) {
        guard let card = activeCards.first(where: { $0.id == cardID }) else { return }
        performDetach(for: card)
    }

    func detachRecentCard(cardID: String) {
        guard let card = recentCards.first(where: { $0.id == cardID }) else { return }
        performDetach(for: card)
    }

    func saveCardToDatabase(_ card: InsightCard) {
        let sessionID = currentSessionID?.uuidString ?? "manual-\(selectedProfileID)"
        let profileID = card.scenario.isEmpty ? selectedProfileID : card.scenario
        savedCardStore.upsert(card: card, sessionID: sessionID, profileID: profileID)
        reloadLatestSavedCards()
    }

    func requestCardReanalysis(card: InsightCard, userQuery: String) async -> String {
        let trimmed = userQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Введите вопрос для переанализа."
        }

        let sessionID = currentSessionID?.uuidString ?? "manual-\(selectedProfileID)"
        let requestID = UUID().uuidString

        return await withCheckedContinuation { continuation in
            cardReanalysisContinuations[requestID] = continuation

            Task {
                do {
                    try await udsClient.send(
                        type: "card_reanalyze",
                        payload: CardReanalysisPayload(
                            requestID: requestID,
                            sessionID: sessionID,
                            profile: selectedProfileID,
                            cardID: card.id,
                            agentName: card.agentName ?? "Оркестратор",
                            triggerReason: card.triggerReason,
                            insight: card.insight,
                            replyCautious: card.replyCautious,
                            replyConfident: card.replyConfident,
                            userQuery: trimmed
                        )
                    )
                } catch {
                    await MainActor.run {
                        if let pending = self.cardReanalysisContinuations.removeValue(forKey: requestID) {
                            pending.resume(returning: "Ошибка запроса к LLM: \(error.localizedDescription)")
                        }
                    }
                }
            }

            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 7_000_000_000)
                guard let self else { return }
                if let pending = self.cardReanalysisContinuations.removeValue(forKey: requestID) {
                    pending.resume(returning: "LLM не ответил вовремя. Повторите запрос.")
                }
            }
        }
    }
}

private extension MainViewModel {
    func performDetach(for card: InsightCard) {
        let detached = detachedCardWindowManager.detach(card: card) { [weak self] in
            Task { @MainActor [weak self] in
                self?.replaceRecent(card)
            }
        }
        guard detached else {
            errorMessage = "Можно вынести не более 3 карточек одновременно."
            return
        }

        replaceRecent(card)
    }

    func makeASRProvider(optionID: String, captureMode: CaptureSourceMode) -> ASRProvider {
        if optionID == ASRProviderOption.whisperKit.id && captureMode == .meeting {
            return SystemSpeechASRProvider()
        }
        return ASRProviderFactory.make(optionID: optionID)
    }

    func refreshPermissionsOnAppActivated() {
        permissionsManager.refresh()
        schedulePermissionRefreshBurst()
    }

    func schedulePermissionRefreshBurst() {
        permissionBurstTask?.cancel()
        permissionBurstTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for seconds in [0.6, 1.2, 2.4] {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                self.permissionsManager.refresh()
            }
        }
    }

    func recomputeOnboardingReadiness() {
        let checklist = permissionsManager.checklist
        onboardingReady = checklist.microphonePermissionGranted
            && (!requiresSpeechPermission || checklist.speechRecognitionPermissionGranted)
            && (!requiresScreenPermission || checklist.screenRecordingPermissionGranted)
            && checklist.oneTimeAcknowledgementAccepted
    }

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
        profileSettings.forceAnswerMode = loadPersistedForceMode(for: suggested)
        isApplyingCalendarSuggestion = false

        let profileTitle = ProfileOption.title(for: suggested)
        if automatic {
            calendarStatusText = "Календарь: профиль применен автоматически -> \(profileTitle)"
        } else {
            calendarStatusText = "Календарь: профиль применен -> \(profileTitle)"
        }
    }

    func sendCardFeedback(card: InsightCard, useful: Bool, excluded: Bool) {
        guard let sessionID = currentSessionID else { return }

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
                        self.upsertTranscriptSegment(normalized)
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

    func startMicASRStreamingTaskIfNeeded() {
        guard let micASR = micASRProvider else { return }
        micTranscriptTask?.cancel()
        micTranscriptTask = Task {
            do {
                try await micASR.startStream()
                for await segment in micASR.segments {
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
                        self.upsertTranscriptSegment(normalized)
                    }

                    do {
                        try await udsClient.send(type: "transcript_segment", payload: normalized)
                    } catch {
                        await MainActor.run {
                            self.errorMessage = "Ошибка отправки транскрипции микрофона: \(error.localizedDescription)"
                        }
                    }
                }
            } catch {
                // Mic ASR в meeting-режиме — вспомогательный; не показываем ошибку
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
            if activeCards.contains(where: { !$0.pinned }) {
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
        let incomingSlot = cardSlotKey(card)
        var mergedCard = card
        if let idx = activeCards.firstIndex(where: { cardSlotKey($0) == incomingSlot }) {
            let existing = activeCards[idx]
            mergedCard.pinned = existing.pinned
            mergedCard.dismissed = existing.dismissed
            mergedCard.excluded = existing.excluded
            activeCards[idx] = mergedCard
        } else {
            activeCards.append(mergedCard)
        }

        activeCards.sort { lhs, rhs in
            let lhsPriority = cardPriority(lhs)
            let rhsPriority = cardPriority(rhs)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.timestamp > rhs.timestamp
        }
        if activeCards.count > 3 {
            activeCards = Array(activeCards.prefix(3))
        }

        detachedCardWindowManager.updateIfDetached(card: mergedCard)
        syncActiveCard()
        isCardCollapsed = false

        replaceRecent(mergedCard)
        let sessionID = currentSessionID?.uuidString ?? "manual-\(selectedProfileID)"
        let profileID = mergedCard.scenario.isEmpty ? selectedProfileID : mergedCard.scenario
        savedCardStore.upsert(card: mergedCard, sessionID: sessionID, profileID: profileID)
    }

    func syncActiveCard() {
        if let orchestrator = activeCards.first(where: { cardPriority($0) == 0 }) {
            activeCard = orchestrator
            return
        }
        activeCard = activeCards.first
    }

    func upsertTranscriptSegment(_ segment: TranscriptSegment) {
        if segment.isFinal {
            transcript.removeAll { $0.utteranceId == segment.utteranceId && !$0.isFinal }
            transcript.append(segment)
            return
        }

        if let idx = transcript.lastIndex(where: { $0.utteranceId == segment.utteranceId && !$0.isFinal }) {
            transcript[idx] = segment
        } else {
            transcript.append(segment)
        }
    }

    func replaceRecent(_ card: InsightCard) {
        let slot = cardSlotKey(card)
        if let idx = recentCards.firstIndex(where: { cardSlotKey($0) == slot }) {
            recentCards[idx] = card
            return
        }
        recentCards.insert(card, at: 0)
        if recentCards.count > 3 {
            recentCards = Array(recentCards.prefix(3))
        }
    }

    func handleCardReanalysisReply(_ reply: UDSEventClient.CardReanalysisReply) {
        guard let continuation = cardReanalysisContinuations.removeValue(forKey: reply.requestID) else {
            return
        }
        continuation.resume(returning: reply.answer)
    }

    func cardSlotKey(_ card: InsightCard) -> String {
        (card.agentName ?? "Оркестратор")
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
    }

    func cardPriority(_ card: InsightCard) -> Int {
        switch (card.agentName ?? "Оркестратор").lowercased() {
        case "оркестратор":
            return 0
        case "психолог":
            return 1
        case "принудительный ответ":
            return 2
        default:
            return 9
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

    func persistForceMode(_ enabled: Bool, for profileID: String) {
        let key = forceModeDefaultsKeyPrefix + profileID
        UserDefaults.standard.set(enabled, forKey: key)
    }

    func loadPersistedForceMode(for profileID: String) -> Bool {
        let key = forceModeDefaultsKeyPrefix + profileID
        if UserDefaults.standard.object(forKey: key) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: key)
    }
}
