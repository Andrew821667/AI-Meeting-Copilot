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
        let slot = slotKey(for: card)
        if let existing = windows[slot] {
            onCloseHandlers[slot] = onClose
            apply(card: card, to: existing, slotKey: slot)
            existing.makeKeyAndOrderFront(nil)
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
        window.isMovableByWindowBackground = true
        window.isOpaque = true
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor(calibratedRed: 0.97, green: 0.94, blue: 0.88, alpha: 1.0)

        // Гарантия: окно не попадает в screen sharing/захват экрана.
        window.sharingType = .none

        windows[slot] = window
        onCloseHandlers[slot] = onClose
        apply(card: card, to: window, slotKey: slot)

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

    public func updateIfDetached(card: InsightCard) {
        let slot = slotKey(for: card)
        guard let window = windows[slot] else { return }
        apply(card: card, to: window, slotKey: slot)
    }

    public func close(slotKey: String) {
        if let window = windows[slotKey] {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
            windows.removeValue(forKey: slotKey)
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

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard let pair = windows.first(where: { $0.value === window }) else { return }
        let key = pair.key
        windows.removeValue(forKey: key)
        if let handler = onCloseHandlers.removeValue(forKey: key) {
            handler()
        }
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
    }

    private func apply(card: InsightCard, to window: NSWindow, slotKey: String) {
        window.title = "Карточка — \(card.agentName ?? "Оркестратор")"
        let closeAction: () -> Void = { [weak self] in
            self?.close(slotKey: slotKey)
        }
        let root = DetachedInsightCardView(card: card, onClose: closeAction)
            .environment(\.colorScheme, .light)
            .preferredColorScheme(.light)
        let hostingView = NSHostingView(rootView: root)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor(calibratedRed: 0.97, green: 0.94, blue: 0.88, alpha: 1.0).cgColor
        window.contentView = hostingView
    }

    private func slotKey(for card: InsightCard) -> String {
        let base = (card.agentName ?? "Оркестратор").lowercased()
        return base.replacingOccurrences(of: " ", with: "_")
    }
}
