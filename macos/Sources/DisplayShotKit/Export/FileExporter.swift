import AppKit
import UniformTypeIdentifiers

enum FileExporter {
    static func defaultFilename(date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "DisplayShot \(f.string(from: date)).png"
    }

    /// Writes `image` as PNG to `directory` with a timestamped, collision-free name.
    @discardableResult
    static func saveSilently(_ image: CGImage, to directory: URL) throws -> URL {
        guard let png = ImageComposer.pngData(image) else { throw ClipboardExporter.Failure.encoding }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory.appendingPathComponent(defaultFilename())
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let base = defaultFilename().replacingOccurrences(of: ".png", with: " (\(n)).png")
            url = directory.appendingPathComponent(base)
            n += 1
        }
        try png.write(to: url, options: .atomic)
        return url
    }

    /// Presents a save panel. Returns the written URL, or nil if the user cancelled.
    static func saveWithPanel(_ image: CGImage, initialDirectory: URL) throws -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = defaultFilename()
        panel.directoryURL = initialDirectory
        panel.level = .screenSaver
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let png = ImageComposer.pngData(image) else { throw ClipboardExporter.Failure.encoding }
        try png.write(to: url, options: .atomic)
        return url
    }
}
