import Foundation
import AppKit
import SwiftUI

/// Отдельное плавающее окно одного ассистента: живой поток его карточек.
/// Свойства как у окна транскрипции — «поверх всех», невидимо при
/// демонстрации экрана (sharingType=.none), запоминает позицию.
///
/// Один экземпляр на ассистента; фильтрация карточек — по `agentName`.
@MainActor
public final class AssistantWindowManager: NSObject {
    private let title: String
    private let agentName: String
    private let autosaveName: String
    private let accent: NSColor

    private var window: NSWindow?
    private var isPinnedOnTop = true

    /// Уведомляет владельца (MainViewModel) об открытии/закрытии, чтобы
    /// состояние ассистента и кнопка в основном окне были согласованы.
    public var onStateChange: ((Bool) -> Void)?

    public private(set) var isOpen = false {
        didSet { if oldValue != isOpen { onStateChange?(isOpen) } }
    }

    public init(title: String, agentName: String, autosaveName: String) {
        self.title = title
        self.agentName = agentName
        self.autosaveName = autosaveName
        self.accent = NSColor(calibratedRed: 0.40, green: 0.31, blue: 0.23, alpha: 1.0)
        super.init()
    }

    public func open(viewModel: MainViewModel) {
        if let window {
            window.orderFront(nil)
            isOpen = true
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 460),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = true
        panel.appearance = NSAppearance(named: .aqua)
        panel.backgroundColor = NSColor(calibratedRed: 0.97, green: 0.94, blue: 0.88, alpha: 1.0)
        // Собеседник это окно не видит ни при какой демонстрации экрана.
        panel.sharingType = .none
        panel.level = isPinnedOnTop ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        let root = AnyView(
            AssistantPanelView(
                viewModel: viewModel,
                title: title,
                agentName: agentName,
                isPinnedOnTop: { [weak self] in self?.isPinnedOnTop ?? true },
                onTogglePin: { [weak self] in self?.togglePin() }
            )
            .environment(\.colorScheme, .light)
            .preferredColorScheme(.light)
        )
        let hostingView = NSHostingView(rootView: root)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor(calibratedRed: 0.97, green: 0.94, blue: 0.88, alpha: 1.0).cgColor
        panel.contentView = hostingView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: panel
        )

        let restored = panel.setFrameUsingName(autosaveName)
        panel.setFrameAutosaveName(autosaveName)
        if !restored {
            panel.center()
        }

        window = panel
        panel.orderFront(nil)
        isOpen = true
    }

    public func close() {
        guard let window else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
        window.orderOut(nil)
        window.close()
        self.window = nil
        isOpen = false
    }

    public func togglePin() {
        isPinnedOnTop.toggle()
        window?.level = isPinnedOnTop ? .floating : .normal
        if isPinnedOnTop {
            window?.orderFront(nil)
        }
    }

    @objc private func windowWillClose(_ notification: Notification) {
        window = nil
        isOpen = false
    }
}

/// Содержимое окна ассистента: живой список его карточек (новые сверху).
/// Подписано на MainViewModel — обновляется вместе с основным окном.
struct AssistantPanelView: View {
    @ObservedObject var viewModel: MainViewModel
    let title: String
    let agentName: String
    let isPinnedOnTop: () -> Bool
    let onTogglePin: () -> Void

    @State private var pinned = true

    private let primaryTextColor = Color(red: 0.20, green: 0.13, blue: 0.09)
    private let secondaryTextColor = Color(red: 0.38, green: 0.28, blue: 0.19)

    // Карточки этого ассистента, новые сверху.
    private var cards: [InsightCard] {
        viewModel.activeCards
            .filter { ($0.agentName ?? "") == agentName }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(primaryTextColor)
                Spacer()
                Image(systemName: "eye.slash.fill")
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor.opacity(0.7))
                    .help("Скрыто при демонстрации экрана — собеседник это окно не видит")
                Button {
                    onTogglePin()
                    pinned = isPinnedOnTop()
                } label: {
                    Image(systemName: pinned ? "pin.fill" : "pin.slash")
                        .font(.caption)
                        .foregroundStyle(pinned ? Color(red: 0.55, green: 0.35, blue: 0.12) : secondaryTextColor.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help(pinned ? "Поверх всех окон: ВКЛ" : "Поверх всех окон: ВЫКЛ")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            if cards.isEmpty {
                Spacer()
                Text("Пока нет карточек.\nАссистент включён — карточки появятся по ходу разговора.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(secondaryTextColor)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(cards) { card in
                            cardView(card)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 280, alignment: .topLeading)
        .background(Color(red: 0.97, green: 0.94, blue: 0.88).ignoresSafeArea())
        .preferredColorScheme(.light)
        .onAppear { pinned = isPinnedOnTop() }
    }

    @ViewBuilder
    private func cardView(_ card: InsightCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !card.triggerReason.isEmpty {
                Text(card.triggerReason)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
            }
            Text(card.insight)
                .font(.body)
                .foregroundStyle(primaryTextColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !card.replyConfident.isEmpty {
                replyBlock("Уверенно", card.replyConfident)
            }
            if !card.replyCautious.isEmpty {
                replyBlock("Осторожно", card.replyCautious)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(cardBackground(card))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func replyBlock(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(secondaryTextColor.opacity(0.8))
            Text(text)
                .font(.callout)
                .foregroundStyle(primaryTextColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.93, green: 0.90, blue: 0.83))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func cardBackground(_ card: InsightCard) -> Color {
        switch card.severity {
        case "warning": return Color(red: 0.97, green: 0.90, blue: 0.78)
        default:         return Color(red: 0.90, green: 0.95, blue: 0.87)
        }
    }
}
