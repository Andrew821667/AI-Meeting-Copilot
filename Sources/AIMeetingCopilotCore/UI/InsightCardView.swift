import SwiftUI

public struct InsightCardView: View {
    public let card: InsightCard
    public let collapsed: Bool
    public let onPin: () -> Void
    public let onCopy: () -> Void
    public let onClose: () -> Void

    public init(
        card: InsightCard,
        collapsed: Bool,
        onPin: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.card = card
        self.collapsed = collapsed
        self.onPin = onPin
        self.onCopy = onCopy
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(card.isFallback ? "Fallback Card" : "Insight Card")
                    .font(.headline)
                Spacer()
                Text(card.severity.uppercased())
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
                Text("Осторожно: \(card.replyCautious)")
                    .font(.subheadline)
                Text("Уверенно: \(card.replyConfident)")
                    .font(.subheadline)
            }

            HStack {
                Button(card.pinned ? "Unpin" : "Pin") { onPin() }
                Button("Copy") { onCopy() }
                Button("×") { onClose() }
                Spacer()
                Text(card.speaker)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
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
}
