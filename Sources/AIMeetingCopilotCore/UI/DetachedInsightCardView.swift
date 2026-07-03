import SwiftUI
import AppKit

struct DetachedInsightCardView: View {
    let card: InsightCard
    let fontSize: CGFloat
    let isPinnedOnTop: Bool
    let onTogglePin: () -> Void
    let onClose: () -> Void

    private let primaryTextColor = Color(red: 0.20, green: 0.13, blue: 0.09)
    private let secondaryTextColor = Color(red: 0.38, green: 0.28, blue: 0.19)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Заголовок
            HStack(spacing: 8) {
                Text(card.agentName ?? "Оркестратор")
                    .font(.headline)
                    .foregroundStyle(primaryTextColor)
                Text("·")
                    .foregroundStyle(secondaryTextColor)
                Text(localizedSpeaker(card.speaker))
                    .font(.subheadline)
                    .foregroundStyle(secondaryTextColor)

                Spacer()

                // Индикатор приватности: sharingType=.none, собеседник это
                // окно не видит при любой демонстрации экрана.
                Image(systemName: "eye.slash.fill")
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor.opacity(0.7))
                    .help("Скрыта при демонстрации экрана — собеседник эту карточку не видит")

                // Toggle «поверх всех окон».
                Button(action: onTogglePin) {
                    Image(systemName: isPinnedOnTop ? "pin.fill" : "pin.slash")
                        .font(.caption)
                        .foregroundStyle(isPinnedOnTop ? Color(red: 0.55, green: 0.35, blue: 0.12) : secondaryTextColor.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help(isPinnedOnTop
                      ? "Поверх всех окон: ВКЛ — нажми, чтобы окно вело себя как обычное"
                      : "Поверх всех окон: ВЫКЛ — нажми, чтобы карточка была всегда видна")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if card.cardMode == "direct_answer" {
                SelectableTextView(
                    text: card.insight,
                    font: .systemFont(ofSize: fontSize),
                    textColor: NSColor(primaryTextColor)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            } else {
                let combinedText = card.insight
                    + (card.replyConfident.isEmpty ? "" : "\n\n— Рекомендация —\n\(card.replyConfident)")
                SelectableTextView(
                    text: combinedText,
                    font: .systemFont(ofSize: fontSize),
                    textColor: NSColor(primaryTextColor)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .frame(minWidth: 400, minHeight: 200, alignment: .topLeading)
        .background(
            Color(red: 0.97, green: 0.94, blue: 0.88)
                .ignoresSafeArea()
        )
        .preferredColorScheme(.light)
        // NSApp.activate здесь раньше КРАЛ фокус у Zoom/Telemost при каждом
        // streaming-обновлении карточки (каждые ~300мс). Убран намеренно.
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
