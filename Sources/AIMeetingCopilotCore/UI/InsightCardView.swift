import SwiftUI

public struct InsightCardView: View {
    public let card: InsightCard
    public let collapsed: Bool
    public let onPin: () -> Void
    public let onCopy: () -> Void
    public let onDetach: () -> Void
    public let onClose: () -> Void
    @State private var dragOffset: CGSize = .zero
    private let primaryTextColor = Color(red: 0.20, green: 0.13, blue: 0.09)
    private let secondaryTextColor = Color(red: 0.38, green: 0.28, blue: 0.19)
    private let surfaceColor = Color(red: 0.98, green: 0.93, blue: 0.83)
    private let borderColor = Color(red: 0.76, green: 0.63, blue: 0.43)
    private var cardHeight: CGFloat { collapsed ? 98 : 206 }

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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(card.agentName ?? "Оркестратор")
                    .font(.headline)
                    .foregroundStyle(primaryTextColor)
                Spacer()
                Text(card.isFallback ? "РЕЗЕРВ" : "АКТИВНАЯ")
                    .font(.caption2.monospaced())
                    .foregroundStyle(secondaryTextColor)
                Spacer()
                Text(localizedSeverity(card.severity))
                    .font(.caption2.monospaced())
                    .foregroundStyle(primaryTextColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(card.isFallback ? Color.orange.opacity(0.3) : Color.blue.opacity(0.2))
                    .clipShape(Capsule())
                Text("Потяни -> окно")
                    .font(.caption2)
                    .foregroundStyle(secondaryTextColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.45))
                    .clipShape(Capsule())
                    .offset(dragOffset)
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in
                                dragOffset = value.translation
                            }
                            .onEnded { _ in
                                dragOffset = .zero
                                onDetach()
                            }
                    )
            }

            if collapsed {
                Text(card.insight)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(primaryTextColor)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Карточка-подсказка")
                            .font(.caption2)
                            .foregroundStyle(secondaryTextColor)
                        Text(card.triggerReason)
                            .font(.caption)
                            .foregroundStyle(secondaryTextColor)
                        Text(card.insight)
                            .font(.body.weight(.medium))
                            .foregroundStyle(primaryTextColor)
                        Text("Осторожный ответ: \(card.replyCautious)")
                            .font(.subheadline)
                            .foregroundStyle(primaryTextColor)
                        Text("Уверенный ответ: \(card.replyConfident)")
                            .font(.subheadline)
                            .foregroundStyle(primaryTextColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 76, maxHeight: 76)
            }

            HStack {
                Button(card.pinned ? "Открепить" : "Закрепить") { onPin() }
                Button("Копировать ответ") { onCopy() }
                Button("Вынести в окно") { onDetach() }
                Button("Скрыть") { onClose() }
                Spacer()
                Text(localizedSpeaker(card.speaker))
                    .font(.caption.monospaced())
                    .foregroundStyle(secondaryTextColor)
            }

            if !collapsed {
                Text("Кнопки: закрепить карточку, скопировать ответ, вынести в отдельное окно или скрыть.")
                    .font(.caption2)
                    .foregroundStyle(secondaryTextColor)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .topLeading)
        .background(surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(borderColor.opacity(0.85), lineWidth: 1)
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let distance = hypot(value.translation.width, value.translation.height)
                    if distance > 32 {
                        onDetach()
                    }
                }
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
