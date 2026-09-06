import AppKit
import ServiceManagement

final class PreferencesWindowController: NSWindowController {
    private let prefs: Preferences
    var onHotKeyChanged: ((HotKey) -> Void)?

    private let pathField = NSTextField(labelWithString: "")
    private let silentCheckbox = NSButton(checkboxWithTitle: "Save without asking (no dialog, straight to the folder)", target: nil, action: nil)
    private let soundCheckbox = NSButton(checkboxWithTitle: "Play a sound after copying or saving", target: nil, action: nil)
    private let loginCheckbox = NSButton(checkboxWithTitle: "Launch DisplayShot at login", target: nil, action: nil)
    private lazy var recorder = HotKeyRecorderView(hotKey: prefs.hotKey)
    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    init(prefs: Preferences) {
        self.prefs = prefs
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 480, height: 240),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "DisplayShot Preferences"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        recorder.onChange = { [weak self] hk in
            guard let self else { return }
            self.prefs.hotKey = hk
            self.onHotKeyChanged?(hk)
        }

        pathField.lineBreakMode = .byTruncatingMiddle
        pathField.stringValue = displayPath(prefs.saveDirectory)
        pathField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let choose = NSButton(title: "Choose…", target: self, action: #selector(chooseFolder))
        let pathRow = NSStackView(views: [pathField, choose])
        pathRow.orientation = .horizontal
        pathRow.spacing = 8

        for f in ImageFormat.allCases { formatPopup.addItem(withTitle: f.title) }
        formatPopup.selectItem(at: ImageFormat.allCases.firstIndex(of: prefs.saveFormat) ?? 0)
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)

        silentCheckbox.state = prefs.saveWithoutAsking ? .on : .off
        silentCheckbox.target = self
        silentCheckbox.action = #selector(toggleSilent)
        soundCheckbox.state = prefs.playSound ? .on : .off
        soundCheckbox.target = self
        soundCheckbox.action = #selector(toggleSound)
        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLogin)
        refreshLoginState()

        let grid = NSGridView(views: [
            [label("Capture shortcut:"), recorder],
            [label("Save to:"), pathRow],
            [label("Format:"), formatPopup],
            [NSGridCell.emptyContentView, silentCheckbox],
            [NSGridCell.emptyContentView, soundCheckbox],
            [NSGridCell.emptyContentView, loginCheckbox],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(grid)

        let hint = NSTextField(wrappingLabelWithString: "Inside the overlay: drag to select, ⌘A full screen, P/L/A/R/M/T/E/X tools, 1–9 colours, scroll wheel stroke width, arrows nudge, ⌘Z undo, ⌘C copy, ⌘S save, Esc back.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(hint)

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            recorder.widthAnchor.constraint(equalToConstant: 200),
            hint.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 16),
            hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            hint.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            hint.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
    }

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.alignment = .right
        return l
    }

    private func refreshLoginState() {
        let bundled = Bundle.main.bundleURL.pathExtension == "app"
        loginCheckbox.isEnabled = bundled
        loginCheckbox.state = (bundled && SMAppService.mainApp.status == .enabled) ? .on : .off
        loginCheckbox.toolTip = bundled ? nil : "Available when running from DisplayShot.app"
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = prefs.saveDirectory
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            prefs.saveDirectory = url
            pathField.stringValue = displayPath(url)
        }
    }

    @objc private func formatChanged() { prefs.saveFormat = ImageFormat.allCases[formatPopup.indexOfSelectedItem] }

    @objc private func toggleSilent() { prefs.saveWithoutAsking = silentCheckbox.state == .on }
    @objc private func toggleSound() { prefs.playSound = soundCheckbox.state == .on }

    @objc private func toggleLogin() {
        do {
            if loginCheckbox.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        refreshLoginState()
    }
}

func displayPath(_ url: URL) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let p = url.path
    return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
}
