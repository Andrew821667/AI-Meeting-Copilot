import Foundation
import AppKit
import SwiftUI

@MainActor
public final class DetachedCardWindowManager: NSObject {
    private var windows: [String: NSWindow] = [:]
    private var onCloseHandlers: [String: () -> Void] = [:]

    public override init() {
        super.init()
    }

    public var count: Int {
        windows.count
    }

    public func detach(card: InsightCard, onClose: @escaping () -> Void) -> Bool {
        if windows[card.id] != nil {
            windows[card.id]?.makeKeyAndOrderFront(nil)
            return true
        }
        guard windows.count < 3 else {
            return false
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Карточка — \(card.agentName ?? "Оркестратор")"
        window.isReleasedWhenClosed = false

        // Гарантия: окно не попадает в screen sharing/захват экрана.
        window.sharingType = .none

        let closeAction: () -> Void = { [weak self] in
            self?.close(cardID: card.id)
        }
        let root = DetachedInsightCardView(card: card, onClose: closeAction)
        window.contentView = NSHostingView(rootView: root)

        windows[card.id] = window
        onCloseHandlers[card.id] = onClose

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )

        window.center()
        window.makeKeyAndOrderFront(nil)
        return true
    }

    public func close(cardID: String) {
        if let window = windows[cardID] {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
            windows.removeValue(forKey: cardID)
            window.orderOut(nil)
            window.close()
        }
        if let handler = onCloseHandlers.removeValue(forKey: cardID) {
            handler()
        }
    }

    public func closeAll() {
        let ids = Array(windows.keys)
        for id in ids {
            close(cardID: id)
        }
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard let pair = windows.first(where: { $0.value === window }) else { return }
        let id = pair.key
        windows.removeValue(forKey: id)
        if let handler = onCloseHandlers.removeValue(forKey: id) {
            handler()
        }
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
    }
}
