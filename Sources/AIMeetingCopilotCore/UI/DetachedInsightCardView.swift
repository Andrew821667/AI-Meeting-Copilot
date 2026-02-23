import SwiftUI
import AppKit

struct DetachedInsightCardView: View {
    let card: InsightCard
    let fontSize: CGFloat
    let onClose: () -> Void

    private let primaryTextColor = Color(red: 0.20, green: 0.13, blue: 0.09)
    private let secondaryTextColor = Color(red: 0.38, green: 0.28, blue: 0.19)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Заголовок
            HStack {
                Text(card.agentName ?? "Оркестратор")
                    .font(.headline)
                    .foregroundStyle(primaryTextColor)
                Text("·")
                    .foregroundStyle(secondaryTextColor)
                Text(localizedSpeaker(card.speaker))
                    .font(.subheadline)
                    .foregroundStyle(secondaryTextColor)
                Spacer()
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
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
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
}
