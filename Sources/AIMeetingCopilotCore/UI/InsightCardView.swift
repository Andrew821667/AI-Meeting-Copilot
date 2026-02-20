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
        VStack(alignment: .leading, spacing: 8) {
            // Заголовок: агент + кнопка закрытия
            HStack {
                Text(card.agentName ?? "Оркестратор")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                Text("·")
                    .foregroundStyle(secondaryTextColor)
                Text(localizedSpeaker(card.speaker))
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(secondaryTextColor)
                }
                .buttonStyle(.plain)
            }

            if collapsed {
                // Свёрнутый режим: одна строка
                Text(card.replyConfident)
                    .font(.body)
                    .lineLimit(2)
                    .foregroundStyle(primaryTextColor)
                    .textSelection(.enabled)
            } else {
                // Развёрнутый режим: полный ответ LLM
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(card.insight)
                            .font(.body)
                            .foregroundStyle(primaryTextColor)
                            .textSelection(.enabled)

                        Divider()

                        Text("Рекомендация:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(secondaryTextColor)
                        Text(card.replyConfident)
                            .font(.body)
                            .foregroundStyle(primaryTextColor)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
