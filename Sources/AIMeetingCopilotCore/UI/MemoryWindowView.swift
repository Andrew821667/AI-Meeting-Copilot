import SwiftUI

public struct MemoryWindowView: View {
    @ObservedObject var viewModel: MemoryViewModel

    public init(viewModel: MemoryViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            settingsBlock
            Divider()
            filesBlock
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
                    Text(viewModel.state.rag_available
                         ? "RAG — поиск по эмбеддингам"
                         : "RAG — поиск по эмбеддингам (скоро)").tag("rag")
                }
                .pickerStyle(.segmented)
                .disabled(!viewModel.state.settings.enabled)
            }

            if viewModel.state.settings.mode == "rag" && !viewModel.state.rag_available {
                Label("RAG-режим в разработке: чанкование и векторизация будут добавлены отдельным обновлением. Сейчас работает только Plain.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Files list

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
