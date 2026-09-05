import AppKit

enum PermissionGate {
    static var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt (only works once per app identity; afterwards the user must
    /// enable it in System Settings).
    @discardableResult
    static func request() -> Bool { CGRequestScreenCaptureAccess() }

    static func showDeniedAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "DisplayShot needs Screen Recording access"
        alert.informativeText = "Turn on DisplayShot under System Settings → Privacy & Security → Screen Recording, then press the shortcut again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
