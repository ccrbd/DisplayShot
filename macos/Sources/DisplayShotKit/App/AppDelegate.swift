import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let hotKeys = HotKeyManager()
    private let capturer = ScreenCapturer()
    private let prefs = Preferences.shared
    private var session: OverlaySession?
    private var prefsController: PreferencesWindowController?
    private var captureItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        hotKeys.onTrigger = { [weak self] in self?.capture() }
        registerHotKey(prefs.hotKey)
        if !PermissionGate.hasScreenRecording {
            PermissionGate.request()
        }
    }

    // MARK: Status item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "DisplayShot")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "DisplayShot"
        }
        let menu = NSMenu()
        menu.delegate = self
        captureItem = NSMenuItem(title: "Capture Area", action: #selector(capture), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        menu.addItem(.separator())
        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)
        loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        let about = NSMenuItem(title: "About DisplayShot", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let quit = NSMenuItem(title: "Quit DisplayShot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
        updateCaptureItem()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let bundled = Bundle.main.bundleURL.pathExtension == "app"
        loginItem.isEnabled = bundled
        loginItem.state = (bundled && SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    private func updateCaptureItem() {
        let hk = prefs.hotKey
        captureItem.keyEquivalent = hk.keyLabel.count == 1 ? hk.keyLabel.lowercased() : ""
        captureItem.keyEquivalentModifierMask = hk.menuModifierFlags
        captureItem.title = hk.keyLabel.count == 1 ? "Capture Area" : "Capture Area (\(hk.displayString))"
    }

    // MARK: Hot key

    private func registerHotKey(_ hotKey: HotKey) {
        if !hotKeys.register(hotKey) {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Couldn't register the shortcut \(hotKey.displayString)"
            alert.informativeText = "Another app may already be using it. Choose a different shortcut in Preferences."
            alert.runModal()
        }
        updateCaptureItem()
    }

    // MARK: Actions

    @objc func capture() {
        Task { @MainActor in await self.beginCapture() }
    }

    @MainActor
    private func beginCapture() async {
        guard session == nil else { return }
        guard PermissionGate.hasScreenRecording else {
            PermissionGate.request()
            PermissionGate.showDeniedAlert()
            return
        }
        do {
            let captures = try await capturer.captureAll()
            let s = OverlaySession(captures: captures, prefs: prefs)
            s.onFinished = { [weak self] in self?.session = nil }
            session = s
            s.start()
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Couldn't capture the screen"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func openPreferences() {
        if prefsController == nil {
            let c = PreferencesWindowController(prefs: prefs)
            c.onHotKeyChanged = { [weak self] hk in self?.registerHotKey(hk) }
            prefsController = c
        }
        NSApp.activate(ignoringOtherApps: true)
        prefsController?.showWindow(nil)
        prefsController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "A fast native screenshot tool.\nCapture, annotate, redact, copy.",
                                         attributes: [.font: NSFont.systemFont(ofSize: 11)]),
        ])
    }
}
