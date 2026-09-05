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
        let b = NSButton(image: symbolImage(symbol), target: target, action: action)
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

/// Vertical strip of tool buttons, colour button and undo, docked beside the selection.
final class ToolPalette: ChromeView {
    static let buttonSize: CGFloat = 28
    static let spacing: CGFloat = 2
    static let pad: CGFloat = 5

    var onSelectTool: ((ToolKind?) -> Void)?
    var onToggleColors: (() -> Void)?
    var onUndo: (() -> Void)?

    private var toolButtons: [ToolKind: NSButton] = [:]
    private let colorButton = ChromeView.makeButton(symbol: "circle.fill", tooltip: "Colour (1–9)", target: nil, action: nil)
    private let undoButton = ChromeView.makeButton(symbol: "arrow.uturn.backward", tooltip: "Undo (⌘Z)", target: nil, action: nil)
    private var selectedTool: ToolKind?

    static var intrinsicSize: CGSize {
        let n = CGFloat(ToolKind.allCases.count + 2)
        return CGSize(width: buttonSize + 2 * pad, height: n * buttonSize + (n - 1) * spacing + 2 * pad)
    }

    var colorButtonFrame: CGRect { colorButton.frame }

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

    @objc private func colorTapped() { onToggleColors?() }
    @objc private func undoTapped() { onUndo?() }

    func update(selectedTool: ToolKind?, color: NSColor, canUndo: Bool) {
        self.selectedTool = selectedTool
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

/// Small pill showing the current stroke width next to the cursor after a wheel change.
final class StrokeWidthBadge: NSView {
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 60, height: 24))
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        addSubview(label)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        Palette.chrome.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    }

    func show(_ text: String, near point: CGPoint, in bounds: CGRect) {
        label.stringValue = text
        label.sizeToFit()
        let size = CGSize(width: label.frame.width + 20, height: 24)
        label.frame = CGRect(x: 10, y: (size.height - label.frame.height) / 2, width: label.frame.width, height: label.frame.height)
        frame = CGRect(origin: CGPoint(x: point.x + 18, y: point.y - 32), size: size).fitted(in: bounds)
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
