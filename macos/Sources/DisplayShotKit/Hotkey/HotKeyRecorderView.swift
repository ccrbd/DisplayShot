import AppKit

/// Click, then press the new shortcut. Esc cancels recording.
final class HotKeyRecorderView: NSView {
    var hotKey: HotKey { didSet { needsDisplay = true } }
    var onChange: ((HotKey) -> Void)?
    private var recording = false { didSet { needsDisplay = true } }

    init(hotKey: HotKey) {
        self.hotKey = hotKey
        super.init(frame: CGRect(x: 0, y: 0, width: 200, height: 26))
        toolTip = "Click, then press the new shortcut"
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 200, height: 26) }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        recording = true
    }

    override func becomeFirstResponder() -> Bool { true }

    override func resignFirstResponder() -> Bool {
        recording = false
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { recording = false; return }
        if let hk = HotKey(event: event) {
            hotKey = hk
            recording = false
            onChange?(hk)
        } else {
            NSSound.beep()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return false }
        keyDown(with: event)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()
        let text = recording ? "Type shortcut… (Esc to cancel)" : hotKey.displayString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: recording ? .regular : .medium),
            .foregroundColor: recording ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attrs)
    }
}
