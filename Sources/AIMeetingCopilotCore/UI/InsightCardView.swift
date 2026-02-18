import SwiftUI

public struct InsightCardView: View {
    public let card: InsightCard
    public let collapsed: Bool
    public let onPin: () -> Void
    public let onCopy: () -> Void
    public let onUseful: () -> Void
    public let onUseless: () -> Void
    public let onExclude: () -> Void
    public let onClose: () -> Void

    public init(
        card: InsightCard,
        collapsed: Bool,
        onPin: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onUseful: @escaping () -> Void,
        onUseless: @escaping () -> Void,
        onExclude: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.card = card
        self.collapsed = collapsed
        self.onPin = onPin
        self.onCopy = onCopy
        self.onUseful = onUseful
        self.onUseless = onUseless
        self.onExclude = onExclude
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(card.isFallback ? "Резервная карточка" : "Карточка-подсказка")
                    .font(.headline)
                Spacer()
                Text(localizedSeverity(card.severity))
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(card.isFallback ? Color.orange.opacity(0.3) : Color.blue.opacity(0.2))
                    .clipShape(Capsule())
            }

            if collapsed {
                Text(card.insight)
                    .font(.subheadline)
                    .lineLimit(1)
            } else {
                Text(card.triggerReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(card.insight)
                    .font(.body.weight(.medium))
                Text("Осторожный ответ: \(card.replyCautious)")
                    .font(.subheadline)
                Text("Уверенный ответ: \(card.replyConfident)")
                    .font(.subheadline)
            }

            HStack {
                Button(card.pinned ? "Открепить" : "Закрепить") { onPin() }
                Button("Копировать") { onCopy() }
                Button("×") { onClose() }
                Spacer()
                Text(localizedSpeaker(card.speaker))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if !collapsed {
                HStack {
                    Button("Полезно") { onUseful() }
                    Button("Бесполезно") { onUseless() }
                    Button("Не показывать похожее") { onExclude() }
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(Color.yellow.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.yellow.opacity(0.5), lineWidth: 1)
        )
    }

    private func localizedSeverity(_ severity: String) -> String {
        switch severity.lowercased() {
        case "info": return "ИНФО"
        case "warning": return "ВНИМАНИЕ"
        case "alert": return "КРИТИЧНО"
        default: return severity.uppercased()
        }
    }

    private func localizedSpeaker(_ speaker: String) -> String {
        switch speaker {
        case "THEM": return "СОБЕСЕДНИК"
        case "THEM_A": return "СОБЕСЕДНИК A"
        case "THEM_B": return "СОБЕСЕДНИК B"
        case "ME": return "Я"
        default: return speaker
        }
    }
}
