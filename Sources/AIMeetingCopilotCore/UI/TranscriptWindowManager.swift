import Foundation
import AppKit
import SwiftUI

/// Отдельное окно живой транскрипции — те же свойства, что у detached-карточек:
/// свободное размещение, «поверх всех окон» по кнопке, невидимость при
/// демонстрации экрана (sharingType=.none), запоминание позиции.
@MainActor
public final class TranscriptWindowManager: NSObject {
    private var window: NSWindow?
    private var isPinnedOnTop = true

    /// Уведомляет владельца (MainViewModel) об открытии/закрытии, чтобы
    /// кнопка в основном окне отражала актуальное состояние.
    public var onStateChange: ((Bool) -> Void)?

    public private(set) var isOpen = false {
        didSet { if oldValue != isOpen { onStateChange?(isOpen) } }
    }

    public override init() {
        super.init()
    }

    public func toggle(viewModel: MainViewModel) {
        if isOpen {
            close()
        } else {
            open(viewModel: viewModel)
        }
    }

    public func open(viewModel: MainViewModel) {
        if let window {
            window.orderFront(nil)
            isOpen = true
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Живая транскрипция"
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
            TranscriptPanelView(
                viewModel: viewModel,
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

        let autosaveName = "aimc-transcript-window"
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

/// Содержимое отдельного окна транскрипции. Подписано на MainViewModel —
/// обновляется живьём вместе с основным окном.
struct TranscriptPanelView: View {
    @ObservedObject var viewModel: MainViewModel
    let isPinnedOnTop: () -> Bool
    let onTogglePin: () -> Void

    @State private var pinned = true

    private let primaryTextColor = Color(red: 0.20, green: 0.13, blue: 0.09)
    private let secondaryTextColor = Color(red: 0.38, green: 0.28, blue: 0.19)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Транскрипция")
                    .font(.headline)
                    .foregroundStyle(primaryTextColor)
                Spacer()
                Image(systemName: "eye.slash.fill")
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor.opacity(0.7))
                    .help("Скрыта при демонстрации экрана — собеседник это окно не видит")
                Button {
                    onTogglePin()
                    pinned = isPinnedOnTop()
                } label: {
                    Image(systemName: pinned ? "pin.fill" : "pin.slash")
                        .font(.caption)
                        .foregroundStyle(pinned ? Color(red: 0.55, green: 0.35, blue: 0.12) : secondaryTextColor.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help(pinned
                      ? "Поверх всех окон: ВКЛ"
                      : "Поверх всех окон: ВЫКЛ")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.transcript) { segment in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("[\(segment.isFinal ? "ФИНАЛ" : "ЧАСТЬ")] \(localizedSpeaker(segment.speaker))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(secondaryTextColor)
                                Text(segment.text)
                                    .font(.body)
                                    .foregroundStyle(primaryTextColor)
                                    .textSelection(.enabled)
                            }
                            .id(segment.id)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(
                                segment.isFinal
                                    ? Color(red: 0.90, green: 0.95, blue: 0.87)
                                    : Color(red: 0.94, green: 0.90, blue: 0.84)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
                .onChange(of: viewModel.transcript.count) { _ in
                    if let last = viewModel.transcript.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 300, alignment: .topLeading)
        .background(Color(red: 0.97, green: 0.94, blue: 0.88).ignoresSafeArea())
        .preferredColorScheme(.light)
        .onAppear { pinned = isPinnedOnTop() }
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
