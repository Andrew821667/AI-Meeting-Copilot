import SwiftUI
import AppKit

public struct CardDetailSheetView: View {
    public let card: InsightCard
    public let fontSize: CGFloat
    public let onSave: () -> Void
    public let onRequestReanalysis: (String) async -> String

    @State private var queryText: String = ""
    @State private var dialog: [DialogItem] = []
    @State private var isAnalyzing = false

    public init(
        card: InsightCard,
        fontSize: CGFloat = 13.0,
        onSave: @escaping () -> Void,
        onRequestReanalysis: @escaping (String) async -> String
    ) {
        self.card = card
        self.fontSize = fontSize
        self.onSave = onSave
        self.onRequestReanalysis = onRequestReanalysis
    }

    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
            actions
            Divider()
            reanalysis
        }
        .padding(16)
        .frame(minWidth: 740, minHeight: 560)
    }

    private var header: some View {
        HStack {
            Text(card.agentName ?? "Оркестратор")
                .font(.title3.weight(.semibold))
            Spacer()
            Text(card.severity.uppercased())
                .font(.caption.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.06))
                .clipShape(Capsule())
            Button("Закрыть") { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                DetailRow(title: "Триггер", text: card.triggerReason, fontSize: fontSize)
                DetailRow(title: "Инсайт", text: card.insight, fontSize: fontSize)
                DetailRow(title: "Осторожный ответ", text: card.replyCautious, fontSize: fontSize)
                DetailRow(title: "Уверенный ответ", text: card.replyConfident, fontSize: fontSize)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Копировать содержание") {
                let composed = """
                Агент: \(card.agentName ?? "Оркестратор")
                Триггер: \(card.triggerReason)
                Инсайт: \(card.insight)
                Осторожный ответ: \(card.replyCautious)
                Уверенный ответ: \(card.replyConfident)
                """
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(composed, forType: .string)
            }
            .buttonStyle(.bordered)

            Button("Сохранить в БД") {
                onSave()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var reanalysis: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Переанализ через LLM")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("Что уточнить по этой карточке?", text: $queryText)
                    .textFieldStyle(.roundedBorder)

                Button(isAnalyzing ? "Анализ..." : "Переанализировать") {
                    Task {
                        await runReanalysis()
                    }
                }
                .disabled(isAnalyzing)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(dialog) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.role)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.text)
                                .font(.subheadline)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(item.role == "Вы" ? Color(red: 0.92, green: 0.94, blue: 0.98) : Color(red: 0.95, green: 0.91, blue: 0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            .frame(minHeight: 160)
        }
    }

    @MainActor
    private func runReanalysis() async {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isAnalyzing = true
        dialog.append(DialogItem(role: "Вы", text: trimmed))
        queryText = ""

        let answer = await onRequestReanalysis(trimmed)
        dialog.append(DialogItem(role: "LLM", text: answer))
        isAnalyzing = false
    }
}

private struct DetailRow: View {
    let title: String
    let text: String
    var fontSize: CGFloat = 13.0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: fontSize))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(8)
        .background(Color.black.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DialogItem: Identifiable {
    let id = UUID()
    let role: String
    let text: String
}
