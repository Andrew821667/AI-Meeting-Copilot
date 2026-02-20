import SwiftUI

public struct InsightCardView: View {
    public let card: InsightCard
    public let collapsed: Bool
    public let onPin: () -> Void
    public let onCopy: () -> Void
    public let onDetach: () -> Void
    public let onClose: () -> Void

    private let primaryTextColor = Color(red: 0.20, green: 0.13, blue: 0.09)
    private let secondaryTextColor = Color(red: 0.38, green: 0.28, blue: 0.19)
    private let surfaceColor = Color(red: 0.98, green: 0.93, blue: 0.83)
    private let borderColor = Color(red: 0.76, green: 0.63, blue: 0.43)

    private var isDirectAnswer: Bool {
        card.cardMode == "direct_answer"
    }

    public init(
        card: InsightCard,
        collapsed: Bool,
        onPin: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onDetach: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.card = card
        self.collapsed = collapsed
        self.onPin = onPin
        self.onCopy = onCopy
        self.onDetach = onDetach
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Заголовок
            HStack(spacing: 6) {
                Text(card.agentName ?? "Оркестратор")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                Text("·")
                    .foregroundStyle(secondaryTextColor)
                Text(localizedSpeaker(card.speaker))
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                Spacer()
                Button { onDetach() } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.forward")
                        .font(.caption2)
                        .foregroundStyle(secondaryTextColor)
                }
                .buttonStyle(.plain)
                .help("Открыть в отдельном окне")
                Button { onClose() } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(secondaryTextColor)
                }
                .buttonStyle(.plain)
            }

            if isDirectAnswer {
                // Режим "Ответы на вопросы" — полный ответ LLM
                SelectableTextView(
                    text: card.insight,
                    font: .systemFont(ofSize: NSFont.systemFontSize),
                    textColor: NSColor(primaryTextColor)
                )
            } else if collapsed {
                SelectableTextView(
                    text: card.replyConfident,
                    font: .systemFont(ofSize: NSFont.systemFontSize),
                    textColor: NSColor(primaryTextColor)
                )
            } else {
                let combinedText = card.insight
                    + (card.replyConfident.isEmpty ? "" : "\n\n— Рекомендация —\n\(card.replyConfident)")
                SelectableTextView(
                    text: combinedText,
                    font: .systemFont(ofSize: NSFont.systemFontSize),
                    textColor: NSColor(primaryTextColor)
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 180, alignment: .topLeading)
        .background(surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(borderColor.opacity(0.85), lineWidth: 1)
        )
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
}
