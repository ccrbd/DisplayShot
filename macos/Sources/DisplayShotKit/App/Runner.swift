import AppKit

/// Entry point used by the thin `DisplayShot` executable.
public enum DisplayShotRunner {
    @MainActor
    public static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
