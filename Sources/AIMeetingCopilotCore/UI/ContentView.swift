import SwiftUI

public struct ContentView: View {
    @StateObject private var viewModel = MainViewModel()
    @State private var showProfileEditor = false
    @State private var showExcludeEditor = false
    @State private var excludeDraft = ""

    public init() {}

    public var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                header

                if !viewModel.onboardingReady {
                    OnboardingChecklistView(viewModel: viewModel)
                }

                controls
                calendarHint
                liveTranscript

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

            sidebar
                .frame(width: 380)
        }
        .padding(16)
        .frame(minWidth: 1240, minHeight: 760)
        .sheet(isPresented: $showProfileEditor) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Параметры профиля")
                    .font(.title3.weight(.semibold))
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
                Text("Исключения триггеров")
                    .font(.title3.weight(.semibold))
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
            viewModel.refreshCalendarSuggestion(autoApply: true)
            viewModel.reloadExcludedPhrases()
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
        HStack(spacing: 10) {
            Picker("Профиль", selection: $viewModel.selectedProfileID) {
                ForEach(viewModel.availableProfiles) { profile in
                    Text(profile.title).tag(profile.id)
                }
            }
            .frame(width: 300)
            .disabled(viewModel.sessionState == .capturing || viewModel.sessionState == .paused)

            Button("Настроить профиль") {
                showProfileEditor = true
            }
            .disabled(viewModel.sessionState == .capturing || viewModel.sessionState == .paused)

            Button("Исключения профиля") {
                viewModel.reloadExcludedPhrases()
                showExcludeEditor = true
            }
            .disabled(viewModel.sessionState == .capturing || viewModel.sessionState == .paused)

            Button("Начать захват") {
                viewModel.startCapture()
            }
            .disabled(!viewModel.onboardingReady || viewModel.sessionState == .capturing || viewModel.sessionState == .paused)

            Button("Пауза") {
                viewModel.pauseCapture()
            }
            .disabled(viewModel.sessionState != .capturing)

            Button("Продолжить") {
                viewModel.resumeCapture()
            }
            .disabled(viewModel.sessionState != .paused)

            Button("Остановить") {
                viewModel.stopCapture()
            }
            .disabled(viewModel.sessionState != .capturing && viewModel.sessionState != .paused)

            Button("Запиши это!") {
                viewModel.triggerPanicCapture()
            }
            .keyboardShortcut(.space, modifiers: [.command, .shift])
            .disabled(viewModel.sessionState != .capturing)

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "RMS микрофона: %.3f", viewModel.lastMicRms))
                Text(String(format: "RMS системы: %.3f", viewModel.lastSystemRms))
                Text(viewModel.isUserSpeaking ? "Статус микрофона: говорю" : "Статус микрофона: молчу")
            }
            .font(.caption.monospaced())
        }
    }

    private var liveTranscript: some View {
        GroupBox("Живая транскрипция") {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.transcript) { segment in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("[\(segment.isFinal ? "ФИНАЛ" : "ЧАСТЬ")] \(localizedSpeaker(segment.speaker))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(segment.text)
                                .font(.body)
                            Text(String(format: "%.2f - %.2f", segment.tsStart, segment.tsEnd))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(segment.isFinal ? Color.green.opacity(0.12) : Color.gray.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .padding(.vertical, 4)
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Карточки")
                .font(.title3.weight(.semibold))

            if let card = viewModel.activeCard {
                InsightCardView(
                    card: card,
                    collapsed: viewModel.isCardCollapsed,
                    onPin: { viewModel.togglePinActiveCard() },
                    onCopy: { viewModel.copyActiveReply() },
                    onUseful: { viewModel.markActiveCardUseful() },
                    onUseless: { viewModel.markActiveCardUseless() },
                    onExclude: { viewModel.excludeActiveCardPattern() },
                    onClose: { viewModel.dismissActiveCard() }
                )
            } else {
                Text("Активной карточки нет")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("Последние 3 карточки")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.recentCards) { card in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.insight)
                                .font(.subheadline)
                                .lineLimit(2)
                            Text(card.triggerReason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }

            Divider()

            HStack {
                Text("История сессий")
                    .font(.headline)
                Spacer()
                Button("Обновить") {
                    viewModel.reloadSessionHistory()
                }
                .font(.caption)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.sessionHistory.prefix(10)) { item in
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
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08))
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

            Spacer()
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
        case "ME": return "Я"
        default: return speaker
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
