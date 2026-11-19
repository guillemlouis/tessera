import SwiftUI
import AppKit

// MARK: - App-wide rule
// Every value displayed in Toolbox uses SelectableText:
// selecting text with the mouse (one or several lines) copies it to the clipboard
// as soon as the mouse is released. Optionally, a plain click copies the clicked line.

struct SelectableText: NSViewRepresentable {
    let attributedText: NSAttributedString
    /// A click without a drag copies the whole line under the cursor.
    var copyLineOnClick = false
    /// Shows a scroller when the content is taller than the frame.
    var scrollable = false
    /// Rewrites the copied text, e.g. to keep only the GUIDs of a selection.
    var transform: ((String) -> String)? = nil
    /// Called after a copy with the final clipboard text.
    var onCopy: ((String) -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = scrollable
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = AutoCopyTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? AutoCopyTextView else { return }
        textView.copyLineOnClick = copyLineOnClick
        textView.transform = transform
        textView.onCopy = onCopy
        scrollView.hasVerticalScroller = scrollable
        if textView.textStorage?.isEqual(to: attributedText) != true {
            textView.textStorage?.setAttributedString(attributedText)
        }
    }
}

final class AutoCopyTextView: NSTextView {
    var copyLineOnClick = false
    var transform: ((String) -> String)?
    var onCopy: ((String) -> Void)?

    override func mouseDown(with event: NSEvent) {
        // NSTextView tracks the drag inside mouseDown and returns on mouse up,
        // so the selection is final when super returns.
        super.mouseDown(with: event)

        let content = string as NSString
        guard content.length > 0 else { return }

        var copied: String?
        let selection = selectedRange()
        if selection.length > 0 {
            copied = content.substring(with: selection)
        } else if copyLineOnClick {
            let point = convert(event.locationInWindow, from: nil)
            let index = min(characterIndexForInsertion(at: point), content.length - 1)
            copied = content.substring(with: content.lineRange(for: NSRange(location: max(index, 0), length: 0)))
        }

        guard var text = copied?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        if let transform { text = transform(text) }
        Clipboard.copy(text)
        onCopy?(text)
    }
}

// MARK: - Attributed text helpers

enum TextStyle {
    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

    static func lineHeight(_ font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    static func paragraph(lineSpacing: CGFloat = 0,
                          alignment: NSTextAlignment = .left,
                          lineBreak: NSLineBreakMode = .byWordWrapping,
                          tabStops: [NSTextTab] = []) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.alignment = alignment
        style.lineBreakMode = lineBreak
        style.tabStops = tabStops
        return style
    }

    /// Uses NSColor so system colours (labelColor, systemRed...) adapt to Light and Dark mode.
    static func plain(_ text: String, font: NSFont, color: NSColor = .labelColor,
                      paragraph: NSParagraphStyle = TextStyle.paragraph()) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }
}

// MARK: - Copy feedback shown in the header

final class CopyFeedback: ObservableObject {
    static let shared = CopyFeedback()

    @Published private(set) var visible = false
    private var workItem: DispatchWorkItem?

    func flash() {
        visible = true
        workItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.visible = false }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: item)
    }
}
