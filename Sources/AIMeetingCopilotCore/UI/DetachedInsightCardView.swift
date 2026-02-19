import SwiftUI
import AppKit

struct DetachedInsightCardView: View {
    let card: InsightCard
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(card.agentName ?? "Оркестратор")
                    .font(.headline)
                Spacer()
                Text(localizedSeverity(card.severity))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            Text(card.triggerReason)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(card.insight)
                .font(.body.weight(.medium))
            Text("Осторожный: \(card.replyCautious)")
                .font(.subheadline)
            Text("Уверенный: \(card.replyConfident)")
                .font(.subheadline)

            HStack {
                Button("Копировать ответ") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(card.replyConfident, forType: .string)
                }
                Spacer()
                Button("Закрыть") {
                    onClose()
                }
            }
        }
        .padding(14)
        .frame(minWidth: 420, minHeight: 260, alignment: .topLeading)
    }

    private func localizedSeverity(_ severity: String) -> String {
        switch severity.lowercased() {
        case "info": return "ИНФО"
        case "warning": return "ВНИМАНИЕ"
        case "alert": return "КРИТИЧНО"
        default: return severity.uppercased()
        }
    }
}
