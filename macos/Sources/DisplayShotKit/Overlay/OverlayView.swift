import AppKit

/// Full-screen canvas for one display: frozen capture, dim mask, redactions, annotations,
/// selection border/handles, W×H label, and the docked toolbars as subviews.
final class OverlayView: NSView {
    unowned let session: OverlaySession
    let index: Int

    private let palette = ToolPalette()
    private let actionBar = ActionBar()
    private let colorStrip = ColorStrip()
    private let widthBadge = StrokeWidthBadge()
    private let errorLabel = NSTextField(labelWithString: "")
    private var textEditor: InlineTextView?
    private var labelRect: CGRect = .zero
    private var labelText = ""
    private var errorHide: DispatchWorkItem?

    private static let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.white,
    ]

    init(session: OverlaySession, index: Int, frame: CGRect) {
        self.session = session
        self.index = index
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay

        for v in [palette, actionBar, colorStrip] as [NSView] {
            v.isHidden = true
            addSubview(v)
        }
        addSubview(widthBadge)

        errorLabel.isHidden = true
        errorLabel.font = .systemFont(ofSize: 13, weight: .medium)
        errorLabel.textColor = .white
        errorLabel.backgroundColor = NSColor(hex: 0xC0392B)
        errorLabel.drawsBackground = true
        errorLabel.wantsLayer = true
        errorLabel.layer?.cornerRadius = 6
        errorLabel.layer?.masksToBounds = true
        addSubview(errorLabel)

        palette.onSelectTool = { [weak self] tool in self?.session.selectTool(tool) }
        palette.onToggleColors = { [weak self] in self?.session.toggleColorStrip() }
        palette.onUndo = { [weak self] in self?.session.undo() }
        actionBar.onCopy = { [weak self] in self?.session.copyToClipboard() }
        actionBar.onSave = { [weak self] in self?.session.save() }
        actionBar.onCancel = { [weak self] in self?.session.cancel() }
        colorStrip.onPick = { [weak self] i in self?.session.setColor(index: i) }
        colorStrip.onCustom = { [weak self] in self?.session.showCustomColorPanel() }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    // MARK: Events

    private func location(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func mouseDown(with event: NSEvent) {
        let p = location(event)
        session.mouseDown(at: p, index: index, event: event)
        session.cursor(at: p, index: index).set()
    }

    override func mouseDragged(with event: NSEvent) {
        let p = location(event)
        session.mouseDragged(at: p, index: index)
        session.cursor(at: p, index: index).set()
    }

    override func mouseUp(with event: NSEvent) {
        let p = location(event)
        session.mouseUp(at: p, index: index)
        session.cursor(at: p, index: index).set()
    }

    override func mouseMoved(with event: NSEvent) {
        let p = location(event)
        session.mouseMoved(at: p, index: index)
        session.cursor(at: p, index: index).set()
    }

    override func scrollWheel(with event: NSEvent) { session.scroll(event) }
    override func flagsChanged(with event: NSEvent) { session.flagsChanged(event) }

    override func keyDown(with event: NSEvent) {
        _ = session.handleKey(event) // unhandled keys are swallowed (no beep)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), session.handleKey(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let cap = session.captures[index]
        ctx.interpolationQuality = .none
        ImageComposer.drawImage(cap.image, in: bounds, in: ctx)

        let isActive = session.activeIndex == index
        let sel = isActive ? session.selection?.rect : nil

        ctx.setFillColor(Palette.dim.cgColor)
        if let sel {
            let path = CGMutablePath()
            path.addRect(bounds)
            path.addRect(sel)
            ctx.addPath(path)
            ctx.fillPath(using: .evenOdd)
        } else {
            ctx.fill(bounds)
        }

        guard let sel else {
            drawHintIfNeeded(ctx)
            return
        }

        ctx.saveGState()
        ctx.clip(to: sel)
        var all = session.store.items
        if let ip = session.inProgress { all.append(ip) }
        for a in all {
            guard case .redact(let rect, let mode, let block) = a.kind else { continue }
            let pr = rect.scaled(cap.scale).integral
            if let patch = session.redactor.patch(source: cap.image, pixelRect: pr, mode: mode, blockPixels: block * cap.scale) {
                ImageComposer.drawImage(patch.image, in: patch.pixelRect.scaled(1 / cap.scale), in: ctx)
            }
        }
        ctx.interpolationQuality = .high
        AnnotationRenderer.draw(session.store.items, in: ctx, clip: sel)
        if let ip = session.inProgress {
            if case .redact(let r, _, _) = ip.kind {
                ctx.setStrokeColor(NSColor(white: 1, alpha: 0.8).cgColor)
                ctx.setLineWidth(1)
                ctx.setLineDash(phase: 0, lengths: [4, 3])
                ctx.stroke(r.insetBy(dx: 0.5, dy: 0.5))
                ctx.setLineDash(phase: 0, lengths: [])
            } else {
                AnnotationRenderer.draw(ip, in: ctx)
            }
        }
        ctx.restoreGState()

        ctx.setLineWidth(1)
        ctx.setStrokeColor(NSColor(white: 0, alpha: 0.5).cgColor)
        ctx.stroke(sel.insetBy(dx: -1.5, dy: -1.5))
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.stroke(sel.insetBy(dx: -0.5, dy: -0.5))

        if session.showsHandles, let model = session.selection {
            for (_, r) in model.handleRects() {
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(r)
                ctx.setStrokeColor(NSColor(white: 0, alpha: 0.6).cgColor)
                ctx.stroke(r.insetBy(dx: 0.5, dy: 0.5))
            }
        }
        drawLabel()
    }

    private func drawHintIfNeeded(_ ctx: CGContext) {
        guard session.selection == nil, session.phase == .idle else { return }
        let text = "Drag to select an area   ·   ⌘A full screen   ·   Esc to cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor(white: 1, alpha: 0.85),
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let rect = CGRect(x: bounds.midX - size.width / 2 - 14, y: bounds.midY - size.height / 2 - 8,
                          width: size.width + 28, height: size.height + 16)
        Palette.chrome.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        (text as NSString).draw(at: CGPoint(x: rect.minX + 14, y: rect.minY + 8), withAttributes: attrs)
    }

    private func labelSize(_ text: String) -> CGSize {
        let s = (text as NSString).size(withAttributes: OverlayView.labelAttributes)
        return CGSize(width: ceil(s.width) + 12, height: ceil(s.height) + 6)
    }

    private func drawLabel() {
        guard !labelText.isEmpty else { return }
        Palette.chrome.setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4).fill()
        (labelText as NSString).draw(at: CGPoint(x: labelRect.minX + 6, y: labelRect.minY + 3), withAttributes: OverlayView.labelAttributes)
    }

    // MARK: Chrome

    func refreshChrome() {
        let active = session.activeIndex == index
        let show = active && session.showsChrome
        palette.isHidden = !show
        actionBar.isHidden = !show
        colorStrip.isHidden = !(show && session.colorStripVisible)

        if active, let model = session.selection {
            let sel = model.rect
            labelText = "\(Int(sel.width.rounded())) × \(Int(sel.height.rounded()))"
            let layout = ToolbarLayout.place(selection: sel, screen: bounds,
                                             paletteSize: ToolPalette.intrinsicSize,
                                             barSize: ActionBar.intrinsicSize,
                                             labelSize: labelSize(labelText))
            palette.frame = layout.palette
            actionBar.frame = layout.actionBar
            labelRect = layout.label

            let stripSize = ColorStrip.intrinsicSize
            let cb = palette.colorButtonFrame
            let y = layout.palette.minY + cb.midY - stripSize.height / 2
            var x = layout.palette.minX - ToolbarLayout.gap - stripSize.width
            if x < bounds.minX { x = layout.palette.maxX + ToolbarLayout.gap }
            colorStrip.frame = CGRect(x: x, y: y, width: stripSize.width, height: stripSize.height).fitted(in: bounds)

            palette.update(selectedTool: session.activeTool, color: session.color, canUndo: session.store.canUndo)
            colorStrip.update(selectedIndex: session.colorIndex)
        } else {
            labelText = ""
        }
        needsDisplay = true
    }

    // MARK: Text editor hosting

    func showTextEditor(at p: CGPoint, color: NSColor, fontSize: CGFloat) {
        removeTextEditor()
        let tv = InlineTextView.make(at: p, color: color, fontSize: fontSize)
        tv.onCommit = { [weak self] in self?.session.commitText() }
        tv.onCancel = { [weak self] in self?.session.cancelText() }
        tv.onResize = { [weak self] in self?.needsDisplay = true }
        addSubview(tv)
        textEditor = tv
        window?.makeFirstResponder(tv)
    }

    func removeTextEditor() {
        guard let tv = textEditor else { return }
        if window?.firstResponder === tv { window?.makeFirstResponder(self) }
        tv.removeFromSuperview()
        textEditor = nil
    }

    var textEditorString: String { textEditor?.string ?? "" }
    var textEditorOrigin: CGPoint? { textEditor?.frame.origin }

    func updateTextEditorStyle(color: NSColor, fontSize: CGFloat) {
        textEditor?.applyStyle(color: color, fontSize: fontSize)
    }

    // MARK: Feedback

    func showWidthBadge(_ text: String, near p: CGPoint) {
        widthBadge.show(text, near: p, in: bounds)
    }

    func flashError(_ text: String) {
        errorLabel.stringValue = "  \(text)  "
        errorLabel.sizeToFit()
        let size = CGSize(width: errorLabel.frame.width, height: errorLabel.frame.height + 10)
        errorLabel.frame = CGRect(x: bounds.midX - size.width / 2, y: bounds.maxY - 80, width: size.width, height: size.height)
        errorLabel.isHidden = false
        errorHide?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.errorLabel.isHidden = true }
        errorHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }
}
