import Foundation
import AppKit
import SwiftUI

@MainActor
public final class DetachedCardWindowManager: NSObject {
    private var windows: [String: NSWindow] = [:]
    private var hostingViews: [String: NSHostingView<AnyView>] = [:]
    private var onCloseHandlers: [String: () -> Void] = [:]
    private var lastCards: [String: InsightCard] = [:]
    /// «Поверх всех окон» — состояние per-карточка, по умолчанию включено.
    private var pinnedOnTop: [String: Bool] = [:]

    public override init() {
        super.init()
    }

    public var count: Int {
        windows.count
    }

    public func detach(card: InsightCard, fontSize: CGFloat = 13.0, onClose: @escaping () -> Void) -> Bool {
        currentFontSize = fontSize
        let slot = slotKey(for: card)
        if let existing = windows[slot] {
            onCloseHandlers[slot] = onClose
            apply(card: card, to: existing, slotKey: slot)
            existing.orderFront(nil)
            return true
        }
        guard windows.count < 3 else {
            return false
        }

        // NSPanel вместо NSWindow:
        // - .nonactivatingPanel — клик в карточку не отбирает фокус у Zoom/Telemost,
        //   пользователь может кликнуть и продолжить разговор не теряя контекст.
        // - .utilityWindow — узкий заголовок, не прерывает основное окно.
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Карточка — \(card.agentName ?? "Оркестратор")"
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = true
        panel.appearance = NSAppearance(named: .aqua)
        panel.backgroundColor = NSColor(calibratedRed: 0.97, green: 0.94, blue: 0.88, alpha: 1.0)

        // Полная автономность от main-окна:
        // 1) sharingType=.none — окно не попадает в screen sharing / Zoom Share
        //    Screen / QuickTime запись, даже если идёт трансляция всего экрана.
        //    Собеседник карточку НЕ видит никогда; toggle на это не влияет.
        panel.sharingType = .none
        // 2) level управляется per-карточка кнопкой-пином (см. setPinned).
        panel.level = .floating
        // 3) collectionBehavior — окно видно во всех Spaces, не сворачивается
        //    с .app, остаётся при full-screen других окон, не показывается
        //    отдельной плиткой в Mission Control.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        // 4) hidesOnDeactivate=false — карточка остаётся, когда пользователь
        //    переключается на Zoom/Telemost.
        panel.hidesOnDeactivate = false
        // 5) becomesKeyOnlyIfNeeded — клик по тексту не активирует окно.
        panel.becomesKeyOnlyIfNeeded = true
        let window: NSWindow = panel

        windows[slot] = window
        onCloseHandlers[slot] = onClose
        pinnedOnTop[slot] = pinnedOnTop[slot] ?? true
        apply(card: card, to: window, slotKey: slot)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )

        // Позиция запоминается per-слот между запусками: расставил карточки
        // один раз — дальше каждая открывается там, где её оставили.
        let autosaveName = "aimc-detached-card-\(slot)"
        let restored = window.setFrameUsingName(autosaveName)
        window.setFrameAutosaveName(autosaveName)
        if !restored {
            window.center()
        }
        window.orderFront(nil)
        return true
    }

    public func updateIfDetached(card: InsightCard) {
        let slot = slotKey(for: card)
        guard let window = windows[slot] else { return }
        apply(card: card, to: window, slotKey: slot)
    }

    public func close(slotKey: String) {
        if let window = windows[slotKey] {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
            windows.removeValue(forKey: slotKey)
            hostingViews.removeValue(forKey: slotKey)
            lastCards.removeValue(forKey: slotKey)
            window.orderOut(nil)
            window.close()
        }
        if let handler = onCloseHandlers.removeValue(forKey: slotKey) {
            handler()
        }
    }

    public func closeAll() {
        let keys = Array(windows.keys)
        for key in keys {
            close(slotKey: key)
        }
    }

    /// Переключает «поверх всех окон» для конкретной карточки.
    /// На видимость при демонстрации экрана НЕ влияет — sharingType=.none
    /// всегда, собеседник карточку не видит в любом режиме.
    public func setPinned(_ pinned: Bool, slotKey: String) {
        pinnedOnTop[slotKey] = pinned
        guard let window = windows[slotKey] else { return }
        window.level = pinned ? .floating : .normal
        if pinned {
            window.orderFront(nil)
        }
        // Перерисовываем контент, чтобы кнопка-пин отразила состояние.
        if let card = lastCards[slotKey] {
            apply(card: card, to: window, slotKey: slotKey)
        }
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard let pair = windows.first(where: { $0.value === window }) else { return }
        let key = pair.key
        windows.removeValue(forKey: key)
        hostingViews.removeValue(forKey: key)
        lastCards.removeValue(forKey: key)
        if let handler = onCloseHandlers.removeValue(forKey: key) {
            handler()
        }
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
    }

    private var currentFontSize: CGFloat = 13.0

    private func apply(card: InsightCard, to window: NSWindow, slotKey: String) {
        window.title = "Карточка — \(card.agentName ?? "Оркестратор")"
        lastCards[slotKey] = card
        let closeAction: () -> Void = { [weak self] in
            self?.close(slotKey: slotKey)
        }
        let isPinned = pinnedOnTop[slotKey] ?? true
        let togglePin: () -> Void = { [weak self] in
            guard let self else { return }
            self.setPinned(!(self.pinnedOnTop[slotKey] ?? true), slotKey: slotKey)
        }
        let root = AnyView(
            DetachedInsightCardView(
                card: card,
                fontSize: currentFontSize,
                isPinnedOnTop: isPinned,
                onTogglePin: togglePin,
                onClose: closeAction
            )
            .environment(\.colorScheme, .light)
            .preferredColorScheme(.light)
        )

        // Переиспользуем hosting view: пересоздание на каждый streaming-чанк
        // сбрасывало скролл и выделение текста каждые ~300мс.
        if let hosting = hostingViews[slotKey], window.contentView === hosting {
            hosting.rootView = root
        } else {
            let hostingView = NSHostingView(rootView: root)
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor(calibratedRed: 0.97, green: 0.94, blue: 0.88, alpha: 1.0).cgColor
            hostingViews[slotKey] = hostingView
            window.contentView = hostingView
        }
    }

    private func slotKey(for card: InsightCard) -> String {
        let base = (card.agentName ?? "Оркестратор").lowercased()
        return base.replacingOccurrences(of: " ", with: "_")
    }
}
