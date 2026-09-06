import AppKit
import OSLog

/// Owns one capture session: the frozen images, one overlay window per display, the selection,
/// the annotation list and every interaction rule (mouse, keyboard, wheel, Esc cascade, export).
@MainActor
final class OverlaySession: NSObject {
    enum Phase: Equatable {
        case idle
        case selecting(origin: CGPoint)
        case selected
        case resizing(Handle)
        case moving(grabOffset: CGPoint)
        case drawing
        case movingEmoji(id: UUID, grabOffset: CGPoint)
        case erasing
    }

    struct ScreenContext {
        let capture: DisplayCapture
        let window: OverlayWindow
        let view: OverlayView
    }

    let prefs: Preferences
    let captures: [DisplayCapture]
    let store = AnnotationStore()
    let redactor = Redactor()

    private(set) var screens: [ScreenContext] = []
    private(set) var activeIndex: Int?
    private(set) var phase: Phase = .idle
    private(set) var selection: SelectionModel?
    private(set) var activeTool: ToolKind?
    private(set) var color: NSColor
    private(set) var colorIndex: Int?
    private(set) var widths: [ToolKind: CGFloat]
    private(set) var inProgress: Annotation?
    private(set) var colorStripVisible = false
    private(set) var emojiPickerVisible = false
    private(set) var isTextEditing = false
    private(set) var isEmojiPicking = false
    private(set) var redactMode: RedactMode
    private(set) var currentEmoji: String
    private var lastEmojiID: UUID?
    private(set) var isFinished = false
    var onFinished: (() -> Void)?

    private var textOrigin: CGPoint = .zero
    private var drawOrigin: CGPoint = .zero
    private(set) var lastPoint: CGPoint = .zero
    private var shiftDown = false
    private var scrollAccumulator: CGFloat = 0
    private var previousApp: NSRunningApplication?

    init(captures: [DisplayCapture], prefs: Preferences) {
        self.captures = captures
        self.prefs = prefs
        widths = prefs.toolWidths
        redactMode = prefs.redactMode
        currentEmoji = prefs.lastEmoji
        let idx = prefs.lastColorIndex
        if idx >= 0 && idx < Palette.colors.count {
            colorIndex = idx
            color = Palette.colors[idx]
        } else {
            colorIndex = 0
            color = Palette.colors[0]
        }
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        previousApp = NSWorkspace.shared.frontmostApplication
        for (i, cap) in captures.enumerated() {
            let window = OverlayWindow(screen: cap.screen)
            let view = OverlayView(session: self, index: i, frame: CGRect(origin: .zero, size: cap.screen.frame.size))
            window.contentView = view
            screens.append(ScreenContext(capture: cap, window: window, view: view))
        }
        for s in screens { s.window.orderFrontRegardless() }
        NSApp.activate(ignoringOtherApps: true)
        makeKey(screenIndex(containing: NSEvent.mouseLocation) ?? 0)
        NSCursor.crosshair.set()
        refresh()
    }

    func dismiss() {
        guard !isFinished else { return }
        isFinished = true
        for s in screens {
            s.view.removeTextEditor()
            s.view.removeEmojiReceiver()
            s.window.orderOut(nil)
            s.window.close()
        }
        if NSColorPanel.sharedColorPanelExists, NSColorPanel.shared.isVisible { NSColorPanel.shared.close() }
        NSCursor.arrow.set()
        previousApp?.activate(options: [])
        onFinished?()
    }

    func cancel() { dismiss() }

    private func screenIndex(containing globalPoint: CGPoint) -> Int? {
        screens.firstIndex { $0.capture.screen.frame.contains(globalPoint) }
    }

    private func makeKey(_ index: Int) {
        let s = screens[index]
        s.window.makeKeyAndOrderFront(nil)
        s.window.makeFirstResponder(s.view)
    }

    private func restoreWindows() {
        for s in screens { s.window.orderFrontRegardless() }
        if let i = activeIndex { makeKey(i) }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Derived state used by the views

    var showsChrome: Bool { selection != nil && (phase == .selected || phase == .drawing) }

    var showsHandles: Bool {
        if case .selecting = phase { return false }
        return selection != nil
    }

    func width(for tool: ToolKind) -> CGFloat { widths[tool] ?? tool.defaultWidth }

    private func bounds(_ index: Int) -> CGRect { screens[index].view.bounds }
    private var activeView: OverlayView? { activeIndex.map { screens[$0].view } }
    private func refresh() { for s in screens { s.view.refreshChrome() } }

    // MARK: - Mouse

    func mouseDown(at p: CGPoint, index: Int, event: NSEvent) {
        lastPoint = p
        shiftDown = event.modifierFlags.contains(.shift)
        if isTextEditing {
            commitText()
            return
        }
        if isEmojiPicking { cancelEmojiPick() }
        colorStripVisible = false
        emojiPickerVisible = false
        if let sel = selection, activeIndex == index {
            switch sel.hitTest(p) {
            case .handle(let h):
                phase = .resizing(h)
            case .inside:
                if let tool = activeTool {
                    if tool == .text {
                        beginText(at: p)
                    } else if tool == .eraser {
                        store.beginGroup()
                        phase = .erasing
                        erase(at: p)
                    } else if tool == .emoji {
                        if let hit = emojiHit(at: p), case .emoji(let e) = hit.kind {
                            lastEmojiID = hit.id
                            phase = .movingEmoji(id: hit.id, grabOffset: p - e.center)
                        } else {
                            stampEmoji(at: p)
                        }
                    } else {
                        startDrawing(tool, at: p.clamped(to: sel.rect))
                    }
                } else {
                    phase = .moving(grabOffset: p - sel.rect.origin)
                }
            case .outside:
                beginSelection(at: p, index: index)
            }
        } else {
            beginSelection(at: p, index: index)
        }
        refresh()
    }

    private func beginSelection(at p: CGPoint, index: Int) {
        if activeIndex != index { makeKey(index) }
        activeIndex = index
        store.clear()
        redactor.clearCache()
        selection = nil
        inProgress = nil
        phase = .selecting(origin: p)
    }

    func mouseDragged(at p: CGPoint, index: Int) {
        guard index == activeIndex else { return }
        lastPoint = p
        applyDrag(p)
        refresh()
    }

    private func applyDrag(_ p: CGPoint) {
        guard let i = activeIndex else { return }
        let b = bounds(i)
        switch phase {
        case .selecting(let origin):
            selection = SelectionModel(rect: SelectionModel.rect(from: origin, to: p, square: shiftDown, in: b), bounds: b)
        case .resizing(let h):
            guard var sel = selection else { return }
            let next = sel.resize(h, to: p, square: shiftDown)
            selection = sel
            phase = .resizing(next)
        case .moving(let grab):
            guard var sel = selection else { return }
            sel.move(to: p - grab)
            selection = sel
        case .drawing:
            guard let ip = inProgress, let sel = selection else { return }
            var updated = DrawingTools.update(ip, origin: drawOrigin, to: p.clamped(to: sel.rect), constrain: shiftDown)
            if case .redact(let r, _, let blk) = updated.kind { updated.kind = .redact(r, shiftDown ? .blur : redactMode, blk) }
            inProgress = updated
        case .erasing:
            erase(at: p)
        case .movingEmoji(let id, let grab):
            guard let sel = selection, let a = store.item(id: id), case .emoji(var e) = a.kind else { return }
            e.center = (p - grab).clamped(to: sel.rect)
            var copy = a
            copy.kind = .emoji(e)
            store.replace(id: id, with: copy)
        default:
            break
        }
    }

    func mouseUp(at p: CGPoint, index: Int) {
        switch phase {
        case .selecting:
            if let sel = selection, sel.rect.width >= 3, sel.rect.height >= 3 {
                phase = .selected
            } else {
                selection = nil
                phase = .idle
            }
        case .resizing, .moving, .movingEmoji:
            phase = .selected
        case .erasing:
            store.endGroup()
            phase = .selected
        case .drawing:
            if let ip = inProgress, ip.isMeaningful { store.add(ip) }
            inProgress = nil
            phase = .selected
        default:
            break
        }
        refresh()
    }

    func mouseMoved(at p: CGPoint, index: Int) {
        if activeIndex == nil || activeIndex == index { lastPoint = p }
    }

    func flagsChanged(_ event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        guard shift != shiftDown else { return }
        shiftDown = shift
        switch phase {
        case .selecting, .resizing, .drawing:
            applyDrag(lastPoint)
            refresh()
        default:
            break
        }
    }

    func cursor(at p: CGPoint, index: Int) -> NSCursor {
        if isTextEditing || isEmojiPicking { return .arrow }
        guard let sel = selection, activeIndex == index else { return .crosshair }
        switch phase {
        case .moving, .movingEmoji: return .closedHand
        case .resizing(let h): return cursor(for: h)
        case .drawing, .erasing: return activeTool == .text ? .iBeam : .crosshair
        default: break
        }
        switch sel.hitTest(p) {
        case .handle(let h): return cursor(for: h)
        case .inside:
            guard let tool = activeTool else { return .openHand }
            if tool == .text { return .iBeam }
            if tool == .emoji { return emojiHit(at: p) != nil ? .openHand : .crosshair }
            return .crosshair
        case .outside: return .arrow
        }
    }

    private func cursor(for h: Handle) -> NSCursor {
        switch h {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        default: return .crosshair
        }
    }

    // MARK: - Drawing tools

    private func startDrawing(_ tool: ToolKind, at p: CGPoint) {
        guard var a = DrawingTools.begin(tool, at: p, color: color.cgColor, width: width(for: tool), blur: shiftDown) else { return }
        if case .redact(let r, _, let b) = a.kind { a.kind = .redact(r, shiftDown ? .blur : redactMode, b) }
        drawOrigin = p
        inProgress = a
        phase = .drawing
    }

    func setRedactMode(_ mode: RedactMode) {
        redactMode = mode
        prefs.redactMode = mode
        if activeTool != .redact { activeTool = .redact }
        refresh()
    }

    // MARK: - Eraser

    private func erase(at p: CGPoint) {
        guard let sel = selection else { return }
        let r = width(for: .eraser) / 2
        let q = p.clamped(to: sel.rect)
        for a in store.items where AnnotationHitTester.hits(a, circleAt: q, radius: r) {
            store.remove(id: a.id)
        }
    }

    // MARK: - Emoji tool

    func toggleEmojiPicker() {
        if activeTool != .emoji { activeTool = .emoji }
        emojiPickerVisible.toggle()
        colorStripVisible = false
        refresh()
    }

    func setEmoji(_ emoji: String) {
        currentEmoji = emoji
        prefs.lastEmoji = emoji
        emojiPickerVisible = false
        if activeTool != .emoji { activeTool = .emoji }
        refresh()
    }

    private func stampEmoji(at p: CGPoint) {
        let a = Annotation(.emoji(EmojiAnnotation(center: p, string: currentEmoji, size: width(for: .emoji), rotation: 0)))
        store.add(a)
        lastEmojiID = a.id
    }

    private func emojiHit(at p: CGPoint) -> Annotation? {
        for a in store.items.reversed() {
            if case .emoji(let e) = a.kind, e.bounds.contains(p) { return a }
        }
        return nil
    }

    /// Applies a change to the most recently stamped/moved emoji.
    private func updateLastEmoji(_ change: (inout EmojiAnnotation) -> Void) {
        guard let id = lastEmojiID, let a = store.item(id: id), case .emoji(var e) = a.kind else { return }
        change(&e)
        var copy = a
        copy.kind = .emoji(e)
        store.replace(id: id, with: copy)
    }

    func rotateLastEmoji(by degrees: CGFloat) {
        updateLastEmoji { $0.rotation += degrees }
        refresh()
    }

    func beginEmojiPick() {
        guard let v = activeView else { return }
        isEmojiPicking = true
        emojiPickerVisible = false
        v.showEmojiReceiver()
        NSApp.orderFrontCharacterPalette(nil)
    }

    func finishEmojiPick(_ emoji: String?) {
        guard isEmojiPicking else { return }
        isEmojiPicking = false
        activeView?.removeEmojiReceiver()
        if let emoji, !emoji.isEmpty { setEmoji(emoji) } else { refresh() }
    }

    func cancelEmojiPick() { finishEmojiPick(nil) }

    func selectTool(_ tool: ToolKind?) {
        if isTextEditing { commitText() }
        if isEmojiPicking { cancelEmojiPick() }
        if case .drawing = phase {
            inProgress = nil
            phase = .selected
        }
        activeTool = tool
        refresh()
    }

    func setColor(index: Int) {
        guard index >= 0, index < Palette.colors.count else { return }
        colorIndex = index
        color = Palette.colors[index]
        prefs.lastColorIndex = index
        colorStripVisible = false
        if isTextEditing { activeView?.updateTextEditorStyle(color: color, fontSize: width(for: .text)) }
        refresh()
    }

    func setCustomColor(_ c: NSColor) {
        colorIndex = nil
        color = c
        if isTextEditing { activeView?.updateTextEditorStyle(color: color, fontSize: width(for: .text)) }
        refresh()
    }

    func toggleColorStrip() {
        colorStripVisible.toggle()
        emojiPickerVisible = false
        refresh()
    }

    func showCustomColorPanel() {
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.color = color
        panel.isContinuous = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.orderFront(nil)
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        setCustomColor(sender.color)
    }

    func undo() {
        guard !isTextEditing else { return }
        store.undo()
        refresh()
    }

    func redo() {
        guard !isTextEditing else { return }
        store.redo()
        refresh()
    }

    // MARK: - Text tool

    private func beginText(at p: CGPoint) {
        guard let v = activeView else { return }
        isTextEditing = true
        textOrigin = p
        v.showTextEditor(at: p, color: color, fontSize: width(for: .text))
    }

    func commitText() {
        guard isTextEditing, let v = activeView else { return }
        let string = v.textEditorString.trimmingCharacters(in: .newlines)
        let origin = v.textEditorOrigin ?? textOrigin
        v.removeTextEditor()
        isTextEditing = false
        if !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.add(Annotation(.text(TextAnnotation(origin: origin, string: string, color: color.cgColor, fontSize: width(for: .text)))))
        }
        refresh()
    }

    func cancelText() {
        guard isTextEditing else { return }
        activeView?.removeTextEditor()
        isTextEditing = false
        refresh()
    }

    // MARK: - Keyboard

    /// Returns true when the event was consumed.
    func handleKey(_ event: NSEvent) -> Bool {
        if isTextEditing || isEmojiPicking { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command), shift = flags.contains(.shift), opt = flags.contains(.option)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        switch event.keyCode {
        case 53: // Esc
            escape()
            return true
        case 36, 76: // Return / Enter
            if !cmd { copyToClipboard(); return true }
        case 123, 124, 125, 126: // arrows
            guard var sel = selection, let i = activeIndex else { return true }
            let step = (shift ? 10 : 1) / screens[i].capture.scale
            var dx: CGFloat = 0, dy: CGFloat = 0
            switch event.keyCode {
            case 123: dx = -step
            case 124: dx = step
            case 125: dy = step
            default: dy = -step
            }
            if opt { sel.grow(dw: dx, dh: dy) } else { sel.nudge(dx: dx, dy: dy) }
            selection = sel
            refresh()
            return true
        default:
            break
        }

        if cmd {
            switch chars {
            case "a": selectAll(); return true
            case "c": copyToClipboard(); return true
            case "s": save(); return true
            case "z": if shift { redo() } else { undo() }; return true
            default: return false
            }
        }

        guard selection != nil else { return false }
        if let tool = ToolKind.allCases.first(where: { $0.key == chars }) {
            selectTool(activeTool == tool ? nil : tool)
            return true
        }
        if chars == "v" { selectTool(nil); return true }
        if activeTool == .emoji, chars == "[" || chars == "]" {
            rotateLastEmoji(by: chars == "[" ? -15 : 15)
            return true
        }
        if let d = Int(chars), (1...9).contains(d), d <= Palette.colors.count {
            setColor(index: d - 1)
            return true
        }
        return false
    }

    /// One level per press while something is mid-edit (shape, text, emoji pick, colour strip);
    /// otherwise Esc closes the overlay immediately.
    func escape() {
        if isTextEditing { cancelText(); return }
        if isEmojiPicking { cancelEmojiPick(); return }
        if case .drawing = phase {
            inProgress = nil
            phase = .selected
            refresh()
            return
        }
        if colorStripVisible { colorStripVisible = false; refresh(); return }
        if emojiPickerVisible { emojiPickerVisible = false; refresh(); return }
        dismiss()
    }

    func selectAll() {
        let index = screenIndex(containing: NSEvent.mouseLocation) ?? activeIndex ?? 0
        if activeIndex != index {
            store.clear()
            redactor.clearCache()
            activeIndex = index
            makeKey(index)
        }
        let b = bounds(index)
        selection = SelectionModel(rect: b, bounds: b)
        inProgress = nil
        phase = .selected
        refresh()
    }

    // MARK: - Scroll wheel = stroke width

    func scroll(_ event: NSEvent) {
        guard let tool = activeTool, selection != nil else { return }
        var steps = 0
        if event.hasPreciseScrollingDeltas {
            scrollAccumulator += event.scrollingDeltaY
            while abs(scrollAccumulator) >= 10 {
                steps += scrollAccumulator > 0 ? 1 : -1
                scrollAccumulator -= scrollAccumulator > 0 ? 10 : -10
            }
        } else {
            steps = event.scrollingDeltaY > 0 ? 1 : (event.scrollingDeltaY < 0 ? -1 : 0)
        }
        guard steps != 0 else { return }
        if tool == .emoji, event.modifierFlags.contains(.option) {
            rotateLastEmoji(by: CGFloat(steps) * 15)
            activeView?.showWidthBadge(width: 0, text: "rotate", color: color, shape: .none, at: lastPoint)
            return
        }
        let range = tool.widthRange
        let w = clamp(width(for: tool) + CGFloat(steps), range.lowerBound, range.upperBound)
        widths[tool] = w
        prefs.toolWidths = widths
        if let ip = inProgress { inProgress = ip.withWidth(w) }
        if tool == .emoji { updateLastEmoji { $0.size = w } }
        if isTextEditing, tool == .text { activeView?.updateTextEditorStyle(color: color, fontSize: w) }
        let unit = (tool == .text || tool == .emoji) ? "pt" : (tool == .redact ? "block" : "px")
        let shape: StrokeWidthBadge.Shape = (tool == .text || tool == .emoji) ? .none : (tool == .redact ? .square : .circle)
        let badgeColor: NSColor = tool == .marker ? color.withAlphaComponent(0.5) : (tool == .eraser || tool == .redact ? NSColor(white: 0.85, alpha: 1) : color)
        activeView?.showWidthBadge(width: w, text: "\(Int(w)) \(unit)", color: badgeColor, shape: shape, at: lastPoint)
        refresh()
    }

    // MARK: - Export

    private func composeImage() -> CGImage? {
        if isTextEditing { commitText() }
        guard let sel = selection, let i = activeIndex else { return nil }
        let cap = screens[i].capture
        let image = ImageComposer.compose(source: cap.image, scale: cap.scale, selection: sel.rect,
                                          annotations: store.items, redactor: redactor)
        Logger(subsystem: "com.ccrbd.DisplayShot", category: "export")
            .info("selection \(Int(sel.rect.width))x\(Int(sel.rect.height)) pt @\(cap.scale)x -> \(image?.width ?? 0)x\(image?.height ?? 0) px")
        return image
    }

    private func finish(with message: String, on screen: NSScreen) {
        dismiss()
        if prefs.playSound { NSSound(named: "Tink")?.play() }
        ToastWindow.show(message, on: screen)
    }

    func copyToClipboard() {
        guard let i = activeIndex, let image = composeImage() else { return }
        let screen = screens[i].capture.screen
        do {
            try ClipboardExporter.copy(image)
        } catch {
            screens[i].view.flashError("Couldn't copy to the clipboard")
            return
        }
        finish(with: "Copied to clipboard · \(image.width) × \(image.height) px", on: screen)
    }

    func save() {
        guard let i = activeIndex, let image = composeImage() else { return }
        let screen = screens[i].capture.screen
        if prefs.saveWithoutAsking {
            do {
                let url = try FileExporter.saveSilently(image, to: prefs.saveDirectory, format: prefs.saveFormat)
                finish(with: "Saved to \(displayPath(url))", on: screen)
            } catch {
                screens[i].view.flashError("Couldn't save: \(error.localizedDescription)")
            }
            return
        }
        for s in screens { s.window.orderOut(nil) }
        do {
            if let (url, format) = try FileExporter.saveWithPanel(image, initialDirectory: prefs.saveDirectory, format: prefs.saveFormat) {
                prefs.saveDirectory = url.deletingLastPathComponent()
                prefs.saveFormat = format
                finish(with: "Saved to \(displayPath(url))", on: screen)
            } else {
                restoreWindows()
            }
        } catch {
            restoreWindows()
            screens[i].view.flashError("Couldn't save: \(error.localizedDescription)")
        }
    }
}
