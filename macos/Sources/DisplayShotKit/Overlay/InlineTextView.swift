import AppKit

/// Invisible-ish single-character field that receives an emoji from the system character
/// palette (⌃⌘Space) and hands it back. Esc cancels.
final class EmojiReceiverView: NSTextView {
    var onPick: ((String?) -> Void)?

    static func make(at origin: CGPoint) -> EmojiReceiverView {
        let tv = EmojiReceiverView(frame: CGRect(x: origin.x, y: origin.y, width: 30, height: 30))
        tv.isRichText = false
        tv.drawsBackground = false
        tv.textContainerInset = CGSize(width: 4, height: 4)
        tv.font = .systemFont(ofSize: 18)
        tv.toolTip = "Pick an emoji"
        return tv
    }

    override var acceptsFirstResponder: Bool { true }
    override func cancelOperation(_ sender: Any?) { onPick?(nil) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onPick?(nil); return }
        super.keyDown(with: event)
    }

    override func didChangeText() {
        super.didChangeText()
        let s = string
        guard let first = s.first else { return }
        onPick?(String(first))
    }

    override func draw(_ dirtyRect: NSRect) {
        Palette.chrome.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        path.setLineDash([4, 3], count: 2, phase: 0)
        NSColor(white: 1, alpha: 0.7).setStroke()
        path.stroke()
    }
}

/// The inline editor for the text tool. Cmd+Return commits, Esc cancels, clicking elsewhere
/// on the canvas commits (handled by the session).
final class InlineTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onResize: (() -> Void)?

    static func make(at origin: CGPoint, color: NSColor, fontSize: CGFloat) -> InlineTextView {
        let tv = InlineTextView(frame: CGRect(x: origin.x, y: origin.y, width: 40, height: fontSize * 1.35))
        tv.isRichText = false
        tv.drawsBackground = false
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = CGSize(width: 4000, height: 4000)
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.applyStyle(color: color, fontSize: fontSize)
        return tv
    }

    func applyStyle(color: NSColor, fontSize: CGFloat) {
        let attrs = AnnotationRenderer.textAttributes(TextAnnotation(origin: .zero, string: "", color: color.cgColor, fontSize: fontSize))
        typingAttributes = attrs
        font = attrs[.font] as? NSFont
        textColor = color
        insertionPointColor = color
        if let storage = textStorage, storage.length > 0 {
            storage.setAttributes(attrs, range: NSRange(location: 0, length: storage.length))
        }
        fitToContent()
    }

    override var acceptsFirstResponder: Bool { true }

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func insertNewline(_ sender: Any?) {
        if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            onCommit?()
        } else {
            super.insertNewline(sender)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?(); return }
        if (event.keyCode == 36 || event.keyCode == 76) && event.modifierFlags.contains(.command) { onCommit?(); return }
        super.keyDown(with: event)
    }

    override func didChangeText() {
        super.didChangeText()
        fitToContent()
        onResize?()
    }

    override func scrollWheel(with event: NSEvent) {
        superview?.scrollWheel(with: event)
    }

    func fitToContent() {
        guard let lm = layoutManager, let tc = textContainer else { return }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        let lineHeight = (font?.pointSize ?? 18) * 1.35
        frame.size = CGSize(width: max(40, ceil(used.width) + 6), height: max(lineHeight, ceil(used.height) + 2))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        path.setLineDash([4, 3], count: 2, phase: 0)
        path.lineWidth = 1
        NSColor(white: 1, alpha: 0.65).setStroke()
        path.stroke()
    }
}
