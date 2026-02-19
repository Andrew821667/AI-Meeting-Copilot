import SwiftUI
import AppKit

struct DetachedInsightCardView: View {
    let card: InsightCard
    let onClose: () -> Void

    var body: some View {
        InsightCardView(
            card: card,
            collapsed: false,
            onPin: {},
            onCopy: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(card.replyConfident, forType: .string)
            },
            onDetach: {},
            onClose: onClose
        )
        .padding(12)
        .frame(minWidth: 460, minHeight: 300, alignment: .topLeading)
        .background(
            Color(red: 0.97, green: 0.94, blue: 0.88)
                .ignoresSafeArea()
        )
        .preferredColorScheme(.light)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
