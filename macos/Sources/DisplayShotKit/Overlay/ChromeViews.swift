import AppKit

/// Dark rounded panel used by the palette, action bar, colour strip and toast.
class ChromeView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        Palette.chrome.setFill()
        path.fill()
        Palette.chromeBorder.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // Swallow clicks on the panel background so the canvas underneath does not start a selection.
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}

    static func symbolImage(_ name: String, pointSize: CGFloat = 14) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: name)
            ?? NSImage(named: NSImage.actionTemplateName)!
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        return image.withSymbolConfiguration(config) ?? image
    }

    static func makeButton(symbol: String, tooltip: String, target: AnyObject?, action: Selector?) -> NSButton {
        let b = RightClickButton(image: symbolImage(symbol), target: target, action: action)
        b.isBordered = false
        b.imagePosition = .imageOnly
        b.imageScaling = .scaleProportionallyDown
        b.contentTintColor = .white
        b.toolTip = tooltip
        b.focusRingType = .none
        b.setButtonType(.momentaryChange)
        return b
    }
}

/// NSButton that also reports secondary clicks (used for the redaction mode menu).
final class RightClickButton: NSButton {
    var onRightClick: ((NSButton) -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        if let onRightClick { onRightClick(self) } else { super.rightMouseDown(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), let onRightClick { onRightClick(self); return }
        super.mouseDown(with: event)
    }
}

/// Vertical strip of tool buttons, colour button and undo, docked beside the selection.
final class ToolPalette: ChromeView {
    static let buttonSize: CGFloat = 28
    static let spacing: CGFloat = 2
    static let pad: CGFloat = 5

    var onSelectTool: ((ToolKind?) -> Void)?
    var onToggleColors: (() -> Void)?
    var onUndo: (() -> Void)?
    var onSelectRedactMode: ((RedactMode) -> Void)?
    var onToggleEmojiPicker: (() -> Void)?
    private var redactMode: RedactMode = .pixelate

    private var toolButtons: [ToolKind: NSButton] = [:]
    private let colorButton = ChromeView.makeButton(symbol: "circle.fill", tooltip: "Colour (1–9)", target: nil, action: nil)
    private let undoButton = ChromeView.makeButton(symbol: "arrow.uturn.backward", tooltip: "Undo (⌘Z)", target: nil, action: nil)
    private var selectedTool: ToolKind?

    static var intrinsicSize: CGSize {
        let n = CGFloat(ToolKind.allCases.count + 2)
        return CGSize(width: buttonSize + 2 * pad, height: n * buttonSize + (n - 1) * spacing + 2 * pad)
    }

    var colorButtonFrame: CGRect { colorButton.frame }
    func buttonFrame(for tool: ToolKind) -> CGRect { toolButtons[tool]?.frame ?? .zero }

    init() {
        super.init(frame: CGRect(origin: .zero, size: ToolPalette.intrinsicSize))
        var y = ToolPalette.pad
        for (i, tool) in ToolKind.allCases.enumerated() {
            let b = ChromeView.makeButton(symbol: tool.symbolName, tooltip: "\(tool.title) (\(tool.key.uppercased()))",
                                          target: self, action: #selector(toolTapped(_:)))
            b.tag = i
            b.frame = CGRect(x: ToolPalette.pad, y: y, width: ToolPalette.buttonSize, height: ToolPalette.buttonSize)
            addSubview(b)
            toolButtons[tool] = b
            if tool == .redact, let rb = b as? RightClickButton {
                rb.onRightClick = { [weak self] button in self?.showRedactMenu(from: button) }
            }
            if tool == .emoji, let eb = b as? RightClickButton {
                eb.image = nil
                eb.imagePosition = .noImage
                eb.font = .systemFont(ofSize: 17)
                eb.onRightClick = { [weak self] _ in self?.onToggleEmojiPicker?() }
            }
            y += ToolPalette.buttonSize + ToolPalette.spacing
        }
        colorButton.target = self
        colorButton.action = #selector(colorTapped)
        colorButton.frame = CGRect(x: ToolPalette.pad, y: y, width: ToolPalette.buttonSize, height: ToolPalette.buttonSize)
        addSubview(colorButton)
        y += ToolPalette.buttonSize + ToolPalette.spacing
        undoButton.target = self
        undoButton.action = #selector(undoTapped)
        undoButton.frame = CGRect(x: ToolPalette.pad, y: y, width: ToolPalette.buttonSize, height: ToolPalette.buttonSize)
        addSubview(undoButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func toolTapped(_ sender: NSButton) {
        let tool = ToolKind.allCases[sender.tag]
        onSelectTool?(selectedTool == tool ? nil : tool)
    }

    private func showRedactMenu(from button: NSButton) {
        let menu = NSMenu()
        for (i, mode) in RedactMode.allCases.enumerated() {
            let item = NSMenuItem(title: mode.title, action: #selector(redactModeChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = mode == redactMode ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: CGPoint(x: button.bounds.maxX + 4, y: 0), in: button)
    }

    @objc private func redactModeChosen(_ sender: NSMenuItem) {
        onSelectRedactMode?(RedactMode.allCases[sender.tag])
    }

    @objc private func colorTapped() { onToggleColors?() }
    @objc private func undoTapped() { onUndo?() }

    func update(selectedTool: ToolKind?, color: NSColor, canUndo: Bool, redactMode: RedactMode, emoji: String) {
        self.selectedTool = selectedTool
        self.redactMode = redactMode
        if let eb = toolButtons[.emoji] {
            eb.title = emoji
            eb.toolTip = "Emoji \(emoji) (E) — right-click to choose another"
        }
        toolButtons[.redact]?.toolTip = "Redact: \(redactMode.title) (X) — right-click to change"
        colorButton.contentTintColor = color
        undoButton.isEnabled = canUndo
        undoButton.contentTintColor = canUndo ? .white : NSColor(white: 1, alpha: 0.35)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let tool = selectedTool, let b = toolButtons[tool] {
            Palette.highlight.setFill()
            NSBezierPath(roundedRect: b.frame.insetBy(dx: -1, dy: -1), xRadius: 6, yRadius: 6).fill()
        }
        // Ring around the colour dot so black/dark colours remain visible.
        let ring = colorButton.frame.insetBy(dx: 6, dy: 6)
        NSColor(white: 1, alpha: 0.7).setStroke()
        let ringPath = NSBezierPath(ovalIn: ring)
        ringPath.lineWidth = 1
        ringPath.stroke()
    }
}

/// Copy · Save · Cancel, docked below the selection.
final class ActionBar: ChromeView {
    static let buttonSize: CGFloat = 28
    static let spacing: CGFloat = 2
    static let pad: CGFloat = 5

    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    static var intrinsicSize: CGSize {
        CGSize(width: 3 * buttonSize + 2 * spacing + 2 * pad, height: buttonSize + 2 * pad)
    }

    init() {
        super.init(frame: CGRect(origin: .zero, size: ActionBar.intrinsicSize))
        let specs: [(String, String, Selector)] = [
            ("doc.on.clipboard", "Copy to clipboard (⌘C / ↩)", #selector(copyTapped)),
            ("square.and.arrow.down", "Save as PNG (⌘S)", #selector(saveTapped)),
            ("xmark", "Cancel (Esc)", #selector(cancelTapped)),
        ]
        var x = ActionBar.pad
        for (symbol, tip, sel) in specs {
            let b = ChromeView.makeButton(symbol: symbol, tooltip: tip, target: self, action: sel)
            b.frame = CGRect(x: x, y: ActionBar.pad, width: ActionBar.buttonSize, height: ActionBar.buttonSize)
            addSubview(b)
            x += ActionBar.buttonSize + ActionBar.spacing
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func copyTapped() { onCopy?() }
    @objc private func saveTapped() { onSave?() }
    @objc private func cancelTapped() { onCancel?() }
}

/// Horizontal row of preset colour swatches plus a custom-colour button.
final class ColorStrip: ChromeView {
    static let swatch: CGFloat = 20
    static let spacing: CGFloat = 4
    static let pad: CGFloat = 5

    var onPick: ((Int) -> Void)?
    var onCustom: (() -> Void)?
    private var selectedIndex: Int?
    private var swatches: [NSButton] = []

    static var intrinsicSize: CGSize {
        let n = CGFloat(Palette.colors.count + 1)
        return CGSize(width: n * swatch + (n - 1) * spacing + 2 * pad, height: swatch + 2 * pad)
    }

    init() {
        super.init(frame: CGRect(origin: .zero, size: ColorStrip.intrinsicSize))
        var x = ColorStrip.pad
        for (i, color) in Palette.colors.enumerated() {
            let image = NSImage(size: NSSize(width: ColorStrip.swatch, height: ColorStrip.swatch), flipped: false) { rect in
                let path = NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
                color.setFill()
                path.fill()
                NSColor(white: 1, alpha: 0.5).setStroke()
                path.lineWidth = 1
                path.stroke()
                return true
            }
            let b = NSButton(image: image, target: self, action: #selector(swatchTapped(_:)))
            b.isBordered = false
            b.imagePosition = .imageOnly
            b.focusRingType = .none
            b.setButtonType(.momentaryChange)
            b.tag = i
            b.toolTip = i < 9 ? "Colour \(i + 1)" : "Colour"
            b.frame = CGRect(x: x, y: ColorStrip.pad, width: ColorStrip.swatch, height: ColorStrip.swatch)
            addSubview(b)
            swatches.append(b)
            x += ColorStrip.swatch + ColorStrip.spacing
        }
        let custom = ChromeView.makeButton(symbol: "ellipsis.circle", tooltip: "Custom colour…", target: self, action: #selector(customTapped))
        custom.frame = CGRect(x: x, y: ColorStrip.pad, width: ColorStrip.swatch, height: ColorStrip.swatch)
        addSubview(custom)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func swatchTapped(_ sender: NSButton) { onPick?(sender.tag) }
    @objc private func customTapped() { onCustom?() }

    func update(selectedIndex: Int?) {
        self.selectedIndex = selectedIndex
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let i = selectedIndex, i < swatches.count {
            Palette.highlight.setFill()
            NSBezierPath(roundedRect: swatches[i].frame.insetBy(dx: -2, dy: -2), xRadius: 5, yRadius: 5).fill()
        }
    }
}

/// Grid of common emojis plus a "more" button that opens the system emoji picker.
/// Shown by right-clicking the emoji tool; hides after a pick.
final class EmojiStrip: ChromeView {
    static let presets = [
        "👍", "👎", "❤️", "😀", "😂", "😍", "🤔", "😮", "😢", "😡",
        "🔥", "✅", "❌", "⭐", "👉", "👈", "👆", "👇", "⚠️", "💡",
        "🎯", "📌", "❓", "❗", "💯", "🎉", "👀", "🙏", "👏", "💪",
        "🚀", "⏰", "🔒", "🔑", "📷", "✏️", "🐛", "💬", "🏁", "✨",
    ]
    static let columns = 10
    static let cell: CGFloat = 26
    static let spacing: CGFloat = 2
    static let pad: CGFloat = 5

    var onPick: ((String) -> Void)?
    var onMore: (() -> Void)?
    private var selected = ""
    private var buttons: [NSButton] = []

    static var intrinsicSize: CGSize {
        let cols = CGFloat(columns)
        let rows = CGFloat((presets.count + 1 + columns - 1) / columns)
        return CGSize(width: cols * cell + (cols - 1) * spacing + 2 * pad,
                      height: rows * cell + (rows - 1) * spacing + 2 * pad)
    }

    init() {
        super.init(frame: CGRect(origin: .zero, size: EmojiStrip.intrinsicSize))
        func cellFrame(_ i: Int) -> CGRect {
            let col = CGFloat(i % EmojiStrip.columns), row = CGFloat(i / EmojiStrip.columns)
            return CGRect(x: EmojiStrip.pad + col * (EmojiStrip.cell + EmojiStrip.spacing),
                          y: EmojiStrip.pad + row * (EmojiStrip.cell + EmojiStrip.spacing),
                          width: EmojiStrip.cell, height: EmojiStrip.cell)
        }
        for (i, emoji) in EmojiStrip.presets.enumerated() {
            let b = NSButton(title: emoji, target: self, action: #selector(tapped(_:)))
            b.isBordered = false
            b.font = .systemFont(ofSize: 16)
            b.focusRingType = .none
            b.setButtonType(.momentaryChange)
            b.tag = i
            b.toolTip = "Stamp \(emoji)"
            b.frame = cellFrame(i)
            addSubview(b)
            buttons.append(b)
        }
        let more = ChromeView.makeButton(symbol: "plus.circle", tooltip: "More emoji… (opens the emoji picker)", target: self, action: #selector(moreTapped))
        more.frame = cellFrame(EmojiStrip.presets.count)
        addSubview(more)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func tapped(_ sender: NSButton) { onPick?(EmojiStrip.presets[sender.tag]) }
    @objc private func moreTapped() { onMore?() }

    func update(selected: String) {
        self.selected = selected
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let i = EmojiStrip.presets.firstIndex(of: selected), i < buttons.count {
            Palette.highlight.setFill()
            NSBezierPath(roundedRect: buttons[i].frame.insetBy(dx: -1, dy: -1), xRadius: 5, yRadius: 5).fill()
        }
    }
}

/// Shows the actual stroke size as a circle (or block) in the current colour, plus the number,
/// centred on the cursor while the wheel changes it.
final class StrokeWidthBadge: NSView {
    enum Shape { case circle, square, none }

    private var diameter: CGFloat = 0
    private var color: NSColor = .white
    private var shape: Shape = .circle
    private var text = ""
    private var hideWork: DispatchWorkItem?
    private static let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
        .foregroundColor: NSColor.white,
    ]

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 60, height: 24))
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let d = diameter
        let preview = CGRect(x: (previewBox - d) / 2, y: (bounds.height - d) / 2, width: d, height: d)
        if shape != .none, d > 0 {
            color.setFill()
            let path = shape == .circle ? NSBezierPath(ovalIn: preview) : NSBezierPath(rect: preview)
            path.fill()
            NSColor(white: 1, alpha: 0.9).setStroke()
            let outline = shape == .circle ? NSBezierPath(ovalIn: preview.insetBy(dx: -1, dy: -1)) : NSBezierPath(rect: preview.insetBy(dx: -1, dy: -1))
            outline.lineWidth = 1
            outline.stroke()
        }
        let size = (text as NSString).size(withAttributes: StrokeWidthBadge.attrs)
        let pill = CGRect(x: previewBox + 6, y: (bounds.height - size.height) / 2 - 3, width: size.width + 12, height: size.height + 6)
        Palette.chrome.setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        (text as NSString).draw(at: CGPoint(x: pill.minX + 6, y: pill.minY + 3), withAttributes: StrokeWidthBadge.attrs)
    }

    private var previewBox: CGFloat { max(diameter + 4, 24) }

    /// `width` is the real on-screen size in points; the preview is centred on `point`.
    func show(width: CGFloat, text: String, color: NSColor, shape: Shape, at point: CGPoint, in bounds: CGRect) {
        self.diameter = shape == .none ? 0 : min(max(width, 2), 200)
        self.color = color
        self.shape = shape
        self.text = text
        let textSize = (text as NSString).size(withAttributes: StrokeWidthBadge.attrs)
        let size = CGSize(width: previewBox + 6 + textSize.width + 12, height: max(previewBox, 26))
        frame = CGRect(origin: CGPoint(x: point.x - previewBox / 2, y: point.y - size.height / 2), size: size).fitted(in: bounds)
        isHidden = false
        needsDisplay = true
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.isHidden = true }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }
}

/// Non-activating HUD shown briefly after copy/save.
final class ToastWindow: NSPanel {
    private static var active: [ToastWindow] = []

    static func show(_ text: String, on screen: NSScreen) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.sizeToFit()
        let size = CGSize(width: label.frame.width + 28, height: label.frame.height + 16)
        let container = ChromeView(frame: CGRect(origin: .zero, size: size))
        label.frame.origin = CGPoint(x: 14, y: 8)
        container.addSubview(label)

        let origin = CGPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.minY + 90)
        let panel = ToastWindow(contentRect: CGRect(origin: origin, size: size),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = container
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        active.append(panel)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
                active.removeAll { $0 === panel }
            })
        }
    }
}
