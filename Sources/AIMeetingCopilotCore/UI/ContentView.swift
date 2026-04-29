import SwiftUI

public struct ContentView: View {
    @ObservedObject private var viewModel: MainViewModel
    @State private var showProfileEditor = false
    @State private var showExcludeEditor = false
    @State private var showLast50Cards = false
    @State private var showSessionCards = false
    @State private var excludeDraft = ""
    @State private var selectedCardForDetails: InsightCard?
    @State private var selectedSessionTitle: String = ""
    @State private var selectedSessionCards: [InsightCard] = []

    private let panelFill = Color(red: 0.98, green: 0.95, blue: 0.89)
    private let panelBorder = Color(red: 0.76, green: 0.67, blue: 0.53)

    public init(viewModel: MainViewModel = MainViewModel()) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.94, blue: 0.88),
                    Color(red: 0.94, green: 0.89, blue: 0.80)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            HSplitView {
                leftPane
                rightPane
            }
            .padding(10)
        }
        .frame(minWidth: 420, minHeight: 300)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showProfileEditor) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Параметры профиля")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Button("Закрыть") { showProfileEditor = false }
                }
                Text(ProfileOption.title(for: viewModel.selectedProfileID))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProfileSettingsEditorView(settings: $viewModel.profileSettings) {
                    viewModel.resetProfileSettingsToDefaults()
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $showExcludeEditor) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Исключения триггеров")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Button("Закрыть") { showExcludeEditor = false }
                }
                Text(ProfileOption.title(for: viewModel.selectedProfileID))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("Фраза для исключения", text: $excludeDraft)
                    Button("Добавить") {
                        let value = excludeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { return }
                        viewModel.addManualExcludedPhrase(value)
                        excludeDraft = ""
                    }
                }

                if viewModel.excludedPhrases.isEmpty {
                    Text("Список исключений пуст.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(Array(viewModel.excludedPhrases.enumerated()), id: \.offset) { item in
                            let phrase = item.element
                            HStack {
                                Text(phrase)
                                Spacer()
                                Button("Удалить") {
                                    viewModel.removeManualExcludedPhrase(phrase)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .frame(minHeight: 220)
                }
            }
            .padding(16)
            .frame(minWidth: 620, minHeight: 360)
            .onAppear {
                viewModel.reloadExcludedPhrases()
            }
        }
        .onAppear {
            viewModel.reloadSessionHistory()
            viewModel.reloadLatestSavedCards()
            viewModel.refreshCalendarSuggestion(autoApply: true)
            viewModel.reloadExcludedPhrases()
        }
        .sheet(item: $selectedCardForDetails) { card in
            CardDetailSheetView(
                card: card,
                fontSize: viewModel.cardFontSize,
                onSave: {
                    viewModel.saveCardToDatabase(card)
                },
                onRequestReanalysis: { prompt in
                    await viewModel.requestCardReanalysis(card: card, userQuery: prompt)
                }
            )
        }
        .sheet(isPresented: $showLast50Cards) {
            NavigationStack {
                List(viewModel.latestSavedCards) { card in
                    Button {
                        selectedCardForDetails = card
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.agentName ?? "Оркестратор")
                                .font(.subheadline.weight(.semibold))
                            Text(card.insight)
                                .font(.subheadline)
                                .lineLimit(2)
                            Text(card.triggerReason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .navigationTitle("Последние 50 карточек")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Закрыть") { showLast50Cards = false }
                    }
                }
            }
            .frame(minWidth: 760, minHeight: 560)
            .onAppear {
                viewModel.reloadLatestSavedCards()
            }
        }
        .sheet(isPresented: $showSessionCards) {
            NavigationStack {
                List(selectedSessionCards) { card in
                    Button {
                        selectedCardForDetails = card
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.agentName ?? "Оркестратор")
                                .font(.subheadline.weight(.semibold))
                            Text(card.insight)
                                .font(.subheadline)
                                .lineLimit(2)
                                .textSelection(.enabled)
                            Text(card.triggerReason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .navigationTitle(selectedSessionTitle)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Закрыть") { showSessionCards = false }
                    }
                }
            }
            .frame(minWidth: 760, minHeight: 560)
        }
    }

    private var leftPane: some View {
        VSplitView {
            splitPanel(minHeight: 60, idealHeight: 430) {
                ScrollView {
                    mainTopContent
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }

            splitPanel(minHeight: 50, idealHeight: 260) {
                liveTranscript
                    .padding(10)
            }
        }
        .frame(minWidth: 90, idealWidth: 760, maxWidth: .infinity)
        .layoutPriority(2)
    }

    private var rightPane: some View {
        VSplitView {
            splitPanel(minHeight: 36, idealHeight: 330) {
                activeCardsPane
            }

            splitPanel(minHeight: 36, idealHeight: 180) {
                recentCardsPane
            }

            splitPanel(minHeight: 36, idealHeight: 240) {
                sidebarHistory
            }
        }
        .frame(minWidth: 90, idealWidth: 430, maxWidth: .infinity)
        .layoutPriority(1)
    }

    private func splitPanel<Content: View>(
        minHeight: CGFloat,
        idealHeight: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            content()
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Индикатор перетаскивания границы
            Text("⋯")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
                .frame(maxWidth: .infinity)
                .frame(height: 8)
        }
        .frame(minHeight: minHeight, idealHeight: idealHeight, maxHeight: .infinity)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(panelFill.opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(panelBorder.opacity(0.82), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var mainTopContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if viewModel.hasPendingPermissionItems {
                OnboardingChecklistView(viewModel: viewModel)
            }

            controls
            Text(viewModel.profileSettings.forceAnswerMode
                 ? "Ответы на вопросы: ВКЛ — LLM анализирует реплики и даёт рекомендации в реальном времени."
                 : "Ответы на вопросы: ВЫКЛ.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(viewModel.profileSettings.forceAnswerMode ? Color(red: 0.33, green: 0.20, blue: 0.13) : .secondary)
            Text(viewModel.startGuideText)
                .font(.footnote)
                .foregroundStyle(viewModel.onboardingReady ? (viewModel.screenPermissionMissingForMeetingMode ? .orange : .green) : .orange)
            calendarHint

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
            if let runtimeWarningMessage = viewModel.runtimeWarningMessage {
                Text("Предупреждение: \(runtimeWarningMessage)")
                    .foregroundStyle(.orange)
                    .font(.footnote.weight(.semibold))
            }
        }
    }

    private var header: some View {
        HStack {
            CaptureIndicatorView(mode: viewModel.captureMode)
            Spacer()
            Text("Состояние: \(localizedState(viewModel.sessionState))")
                .font(.subheadline.monospaced())
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    pickersRow
                    Spacer(minLength: 0)
                    profileToolsRow
                }
                VStack(alignment: .leading, spacing: 8) {
                    pickersRow
                    profileToolsRow
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    sessionActionsRow
                    Spacer(minLength: 0)
                    levelsView
                }
                VStack(alignment: .leading, spacing: 8) {
                    sessionActionsRow
                    levelsView
                }
            }
        }
    }

    private var pickersRow: some View {
        HStack(spacing: 10) {
            Picker("Профиль", selection: $viewModel.selectedProfileID) {
                ForEach(viewModel.availableProfiles) { profile in
                    Text(profile.title).tag(profile.id)
                }
            }
            .frame(maxWidth: 280)
            .disabled(viewModel.sessionState == .capturing || viewModel.sessionState == .paused)

            Picker("ASR", selection: $viewModel.selectedASRProviderID) {
                ForEach(viewModel.availableASRProviders) { provider in
                    Text(provider.title).tag(provider.id)
                }
            }
            .frame(maxWidth: 260)
            .disabled(viewModel.sessionState == .capturing || viewModel.sessionState == .paused)

            Picker("Режим", selection: $viewModel.selectedCaptureSourceMode) {
                ForEach(viewModel.availableCaptureSourceModes) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .frame(maxWidth: 320)
            .disabled(viewModel.sessionState == .capturing || viewModel.sessionState == .paused)

            if viewModel.selectedCaptureSourceMode == .meeting {
                Picker("Встреча", selection: $viewModel.selectedMeetingSubMode) {
                    ForEach(MeetingSubMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .frame(maxWidth: 160)
                .disabled(viewModel.sessionState == .capturing || viewModel.sessionState == .paused)
            }

            Picker("LLM", selection: Binding(
                get: { viewModel.profileSettings.llmProvider ?? "deepseek" },
                set: { viewModel.profileSettings.llmProvider = $0 == "deepseek" ? nil : $0 }
            )) {
                Text("DeepSeek API").tag("deepseek")
                Text("Локальная (Ollama)").tag("ollama")
            }
            .frame(maxWidth: 200)
            .disabled(viewModel.sessionState == .capturing || viewModel.sessionState == .paused)

            // Picker модели DeepSeek виден только когда выбран этот провайдер.
            // "deepseek-chat" — alias на текущий релиз (сейчас v4-flash); явно
            // зафиксированные имена дают предсказуемое сравнение.
            if (viewModel.profileSettings.llmProvider ?? "deepseek") == "deepseek" {
                Picker("Модель", selection: Binding(
                    get: { viewModel.profileSettings.deepseekModel ?? "deepseek-chat" },
                    set: { viewModel.profileSettings.deepseekModel = $0 == "deepseek-chat" ? nil : $0 }
                )) {
                    Text("Авто (последняя)").tag("deepseek-chat")
                    Text("V4 Flash (быстрее)").tag("deepseek-v4-flash")
                    Text("V4 Pro (точнее)").tag("deepseek-v4-pro")
                }
                .frame(maxWidth: 220)
                .disabled(viewModel.sessionState == .capturing || viewModel.sessionState == .paused)
            }
        }
    }

    private var profileToolsRow: some View {
        HStack(spacing: 8) {
            Button("Настроить профиль") {
                showProfileEditor = true
            }
            .disabled(viewModel.sessionState == .capturing || viewModel.sessionState == .paused)

            Button("Исключения профиля") {
                viewModel.reloadExcludedPhrases()
                showExcludeEditor = true
            }
            .disabled(viewModel.sessionState == .capturing || viewModel.sessionState == .paused)

            HStack(spacing: 2) {
                Button("A\u{2212}") { viewModel.cardFontSize = max(10, viewModel.cardFontSize - 1) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Text("\(Int(viewModel.cardFontSize))")
                    .font(.caption.monospaced())
                    .frame(width: 22)
                Button("A+") { viewModel.cardFontSize = min(20, viewModel.cardFontSize + 1) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var sessionActionsRow: some View {
        HStack(spacing: 8) {
            Button(viewModel.startButtonTitle) {
                viewModel.startCapture()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color(red: 0.44, green: 0.56, blue: 0.31))
            .disabled(viewModel.sessionState == .capturing || viewModel.sessionState == .paused)

            Button("Пауза") {
                viewModel.pauseCapture()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.sessionState != .capturing)

            Button("Продолжить") {
                viewModel.resumeCapture()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.sessionState != .paused)

            Button("Остановить") {
                viewModel.stopCapture()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color(red: 0.63, green: 0.32, blue: 0.26))
            .disabled(viewModel.sessionState != .capturing && viewModel.sessionState != .paused)

            Button("Запиши это!") {
                viewModel.triggerPanicCapture()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(Color(red: 0.70, green: 0.48, blue: 0.24))
            .keyboardShortcut(.space, modifiers: [.command, .shift])
            .disabled(viewModel.sessionState != .capturing)

            Button(viewModel.profileSettings.forceAnswerMode
                   ? "Ответы на вопросы: ВКЛ"
                   : "Ответы на вопросы: ВЫКЛ") {
                viewModel.toggleForceAnswerMode()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(viewModel.profileSettings.forceAnswerMode
                  ? Color(red: 0.40, green: 0.31, blue: 0.23)
                  : Color(red: 0.58, green: 0.53, blue: 0.46))
        }
    }

    private var levelsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: "RMS микрофона: %.3f", viewModel.lastMicRms))
            Text(String(format: "RMS системы: %.3f", viewModel.lastSystemRms))
            Text(viewModel.isUserSpeaking ? "Статус микрофона: говорю" : "Статус микрофона: молчу")
        }
        .font(.caption.monospaced())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var liveTranscript: some View {
        GroupBox("Живая транскрипция") {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.transcript) { segment in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("[\(segment.isFinal ? "ФИНАЛ" : "ЧАСТЬ")] \(localizedSpeaker(segment.speaker))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(speakerColor(segment.speaker))
                                Text(segment.text)
                                    .font(.body)
                                    .textSelection(.enabled)
                                Text(String(format: "%.2f - %.2f", segment.tsStart, segment.tsEnd))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .id(segment.id)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(
                                segment.isFinal
                                    ? Color(red: 0.90, green: 0.95, blue: 0.87)
                                    : Color(red: 0.94, green: 0.90, blue: 0.84)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: viewModel.transcript.count) { _ in
                    if let last = viewModel.transcript.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var calendarHint: some View {
        GroupBox("Календарь") {
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.calendarStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Обновить из календаря") {
                        viewModel.refreshCalendarSuggestion()
                    }
                    Button("Применить профиль") {
                        viewModel.applyCalendarSuggestedProfile()
                    }
                    .disabled(viewModel.calendarSuggestedProfileID == nil || viewModel.sessionState == .capturing || viewModel.sessionState == .paused)
                }
            }
        }
    }

    private var activeCardsPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Карточки")
                .font(.title3.weight(.semibold))

            if viewModel.activeCards.isEmpty {
                Text("Активных карточек нет")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.activeCards) { card in
                            InsightCardView(
                                card: card,
                                collapsed: viewModel.isCardCollapsed,
                                fontSize: viewModel.cardFontSize,
                                onPin: { viewModel.togglePin(cardID: card.id) },
                                onCopy: { viewModel.copyReply(cardID: card.id) },
                                onDetach: { viewModel.detachCard(cardID: card.id) },
                                onClose: { viewModel.dismissCard(cardID: card.id) }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private var recentCardsPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Последние карточки")
                    .font(.headline)
                Spacer()
                Button("Последние 50") {
                    viewModel.reloadLatestSavedCards()
                    showLast50Cards = true
                }
                .buttonStyle(.bordered)
            }

            if viewModel.recentCards.isEmpty {
                Text("Пока нет карточек.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.recentCards) { card in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(card.agentName ?? "Оркестратор")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Вынести") {
                                    viewModel.detachRecentCard(cardID: card.id)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            Text(card.insight)
                                .font(.subheadline)
                                .lineLimit(2)
                            Text(card.triggerReason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 0.95, green: 0.91, blue: 0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .onTapGesture {
                            selectedCardForDetails = card
                        }
                    }
                }
            }
        }
    }

    private var sidebarHistory: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("История сессий")
                    .font(.headline)
                Spacer()
                Button("Обновить") {
                    viewModel.reloadSessionHistory()
                }
                .font(.caption)
            }

            if viewModel.sessionHistory.isEmpty {
                Text("Сессии пока не сохранены.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.sessionHistory.prefix(3)) { item in
                        Button {
                            selectedSessionCards = viewModel.loadSessionCards(item: item)
                            selectedSessionTitle = "Сессия \(formattedDate(item.endedAt))"
                            showSessionCards = true
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ProfileOption.title(for: item.profileID))
                                    .font(.subheadline.weight(.semibold))
                                Text("\(formattedDate(item.endedAt)) • карточек: \(item.totalCards), резервных: \(item.fallbackCards)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(item.exportPath)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 0.95, green: 0.91, blue: 0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }

            if let summary = viewModel.lastSessionSummary {
                Divider()
                Text("Экспорт текущей сессии")
                    .font(.headline)
                Text("JSON: \(summary.exportJSONPath)")
                    .font(.caption)
                    .textSelection(.enabled)
                Text("Отчёт: \(summary.reportMDPath)")
                    .font(.caption)
                    .textSelection(.enabled)
                if let reportPDFPath = summary.reportPDFPath, !reportPDFPath.isEmpty {
                    Text("PDF: \(reportPDFPath)")
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func localizedState(_ state: SessionState) -> String {
        switch state {
        case .idle: return "Ожидание"
        case .capturing: return "Захват"
        case .paused: return "Пауза"
        case .ended: return "Завершено"
        }
    }

    private func localizedSpeaker(_ speaker: String) -> String {
        switch speaker {
        case "THEM": return "Собеседник"
        case "THEM_A": return "Собеседник A"
        case "THEM_B": return "Собеседник B"
        case "THEM_C": return "Собеседник C"
        case "THEM_D": return "Собеседник D"
        case "THEM_E": return "Собеседник E"
        case "ME": return "Я"
        default: return speaker
        }
    }

    private func speakerColor(_ speaker: String) -> Color {
        switch speaker {
        case "ME": return Color(red: 0.25, green: 0.50, blue: 0.30)
        case "THEM", "THEM_A": return Color(red: 0.30, green: 0.40, blue: 0.65)
        case "THEM_B": return Color(red: 0.60, green: 0.35, blue: 0.50)
        case "THEM_C": return Color(red: 0.55, green: 0.45, blue: 0.25)
        case "THEM_D": return Color(red: 0.35, green: 0.55, blue: 0.55)
        case "THEM_E": return Color(red: 0.50, green: 0.30, blue: 0.60)
        default: return .secondary
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
