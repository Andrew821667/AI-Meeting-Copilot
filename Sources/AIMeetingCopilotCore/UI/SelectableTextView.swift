import SwiftUI
import AppKit

/// NSTextView-обёртка для SwiftUI: текст можно выделять и копировать (Cmd+C / контекстное меню).
/// Поддерживает прокрутку длинного текста.
struct SelectableTextView: NSViewRepresentable {
    let text: String
    var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
    var textColor: NSColor = .labelColor

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = font
        textView.textColor = textColor
        textView.string = text
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
            textView.font = font
            textView.textColor = textColor
        }
    }
}
