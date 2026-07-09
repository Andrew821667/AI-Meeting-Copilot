import SwiftUI

public struct MemoryWindowView: View {
    @ObservedObject var viewModel: MemoryViewModel

    public init(viewModel: MemoryViewModel) {
        self.viewModel = viewModel
    }

    private var hubActiveLabelText: String {
        let base = "Memory Hub активен: \(viewModel.state.memory_hub_url)."
        if let count = viewModel.hubActiveItems {
            let formatted = NumberFormatter.localizedString(
                from: NSNumber(value: count), number: .decimal)
            return "\(base) В хабе \(formatted) активных записей памяти."
        }
        return base
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            settingsBlock
            Divider()
            // В режиме Memory Hub основную площадь занимает браузер хаба —
            // локальный список файлов сбивал с толку («память пуста», хотя
            // в хабе 100k+ записей). Файлы остаются в других режимах.
            if viewModel.state.settings.mode == "memory_hub" && viewModel.state.memory_hub_available {
                hubBrowserBlock
            } else {
                filesBlock
            }
            Divider()
            footer
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 480)
        .onAppear {
            viewModel.reload()
        }
        .alert("Ошибка", isPresented: errorBinding) {
            Button("OK", role: .cancel) { viewModel.lastError = nil }
        } message: {
            Text(viewModel.lastError ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.lastError != nil },
            set: { newValue in if !newValue { viewModel.lastError = nil } }
        )
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Память / Контекст для LLM")
                .font(.title2.bold())
            Text("Заметки в этой папке вклеиваются в system prompt при каждом ответе. Используй для фактов о тебе, проекте, продукте — то, что регулярно нужно ассистенту.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Settings

    private var settingsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { viewModel.state.settings.enabled },
                set: { viewModel.setEnabled($0) }
            )) {
                Text("Использовать память в ответах LLM")
                    .font(.body)
            }
            .toggleStyle(.switch)

            HStack(spacing: 16) {
                Text("Режим обработки:")
                Picker("", selection: Binding(
                    get: { viewModel.state.settings.mode },
                    set: { viewModel.setMode($0) }
                )) {
                    Text("Plain — вклеить весь корпус").tag("plain")
                    Text(viewModel.state.memory_hub_available
                         ? "Memory Hub — внешний RAG"
                         : "Memory Hub (не настроен)").tag("memory_hub")
                    Text("RAG — локальный поиск").tag("rag")
                }
                .pickerStyle(.segmented)
                .disabled(!viewModel.state.settings.enabled)
            }

            if viewModel.state.settings.mode == "memory_hub" {
                if viewModel.state.memory_hub_available {
                    Label(hubActiveLabelText, systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Label("Воспоминания хаба живут на сервере и НЕ отображаются в списке файлов ниже — «Файлы памяти» это отдельные локальные заметки. Под каждый вопрос собеседника Суфлёр автоматически находит в хабе несколько подходящих воспоминаний.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let reason = viewModel.hubUnreachableReason {
                    Label("Memory Hub настроен, но недоступен: \(reason). Проверь интернет/сервер и нажми «Обновить».", systemImage: "wifi.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Label("Memory Hub не настроен. Добавь в ~/Library/Application Support/AIMeetingCopilot/.env: AIMC_MEMORYHUB_URL и AIMC_MEMORYHUB_TOKEN, затем перезапусти приложение.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if viewModel.state.settings.mode == "rag" {
                Label("Локальный RAG: файлы памяти ниже нарезаются на фрагменты, и под каждый вопрос собеседника Суфлёр получает только релевантные куски (поиск BM25, офлайн). Выбирай этот режим, когда заметок больше лимита Plain (30 000 симв.).", systemImage: "doc.text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.state.settings.mode == "plain" {
                Label("Plain: содержимое всех файлов ниже целиком вклеивается в промпт каждого ответа (лимит 30 000 симв.). Просто и надёжно, пока заметок немного.", systemImage: "doc.plaintext")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Files list

    // MARK: - Memory Hub browser

    /// Браузер записей хаба: последние записи или результаты поиска — тем же
    /// hybrid-search, каким Суфлёр находит воспоминания под вопросы.
    private var hubBrowserBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Память в хабе")
                    .font(.headline)
                Spacer()
                Button("Обновить") { viewModel.searchHub() }
            }

            HStack(spacing: 8) {
                TextField("Поиск по памяти (пусто — последние записи)…", text: $viewModel.hubSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewModel.searchHub() }
                Button("Найти") { viewModel.searchHub() }
                    .disabled(viewModel.hubSearchBusy)
                if viewModel.hubSearchBusy {
                    ProgressView().controlSize(.small)
                }
            }

            if viewModel.hubItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: viewModel.hubSearchBusy ? "clock" : "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(viewModel.hubSearchBusy ? "Загружаю записи хаба…" : "Ничего не найдено — измени запрос.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.hubItems) { item in
                            hubItemRow(item)
                        }
                    }
                    .padding(6)
                }
                .frame(minHeight: 180)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private func hubItemRow(_ item: HubMemoryItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(item.type.isEmpty ? "note" : item.type)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.18))
                    .clipShape(Capsule())
                Spacer()
                Text(item.updatedAt)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(item.title)
                .font(.callout)
                .textSelection(.enabled)
            if !item.detail.isEmpty {
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var filesBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Файлы памяти")
                    .font(.headline)
                Spacer()
                Button("Добавить файлы…") { viewModel.addFiles() }
                Button("Открыть папку") { viewModel.revealInFinder() }
                Button("Обновить") { viewModel.reload() }
            }

            if viewModel.state.files.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.state.files) { file in
                            fileRow(file)
                        }
                    }
                }
                .frame(minHeight: 180)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Папка памяти пуста")
                .font(.headline)
            Text("Добавь .md или .txt файлы — они автоматически попадут в контекст LLM.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func fileRow(_ file: MemoryFileInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(.body, design: .monospaced))
                Text("\(file.chars) симв. · \(file.size_bytes) байт")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                viewModel.deleteFile(file)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Footer

    private var footer: some View {
        let usage = viewModel.state.total_chars
        let limit = viewModel.state.limit_chars
        let pct = limit > 0 ? Double(usage) / Double(limit) : 0
        return VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: min(pct, 1.0))
                .tint(usage > limit ? .red : (pct > 0.8 ? .orange : .accentColor))
            HStack {
                Text("\(viewModel.state.files.count) файлов · \(usage) симв. из \(limit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if viewModel.state.truncated {
                    Spacer()
                    Label("Превышен лимит — память будет обрезана", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
