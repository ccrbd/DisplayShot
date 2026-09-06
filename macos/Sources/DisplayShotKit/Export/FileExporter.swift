import AppKit
import UniformTypeIdentifiers

enum FileExporter {
    static func defaultFilename(date: Date = Date(), format: ImageFormat = .png) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "DisplayShot \(f.string(from: date)).\(format.fileExtension)"
    }

    /// Writes `image` into `directory` with a timestamped, collision-free name.
    @discardableResult
    static func saveSilently(_ image: CGImage, to directory: URL, format: ImageFormat) throws -> URL {
        guard let data = ImageComposer.data(image, format: format) else { throw ClipboardExporter.Failure.encoding }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = defaultFilename(format: format)
        var url = directory.appendingPathComponent(base)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let name = base.replacingOccurrences(of: ".\(format.fileExtension)", with: " (\(n)).\(format.fileExtension)")
            url = directory.appendingPathComponent(name)
            n += 1
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Presents a save panel with a format chooser. Returns the written URL and the chosen
    /// format, or nil if the user cancelled.
    static func saveWithPanel(_ image: CGImage, initialDirectory: URL, format: ImageFormat) throws -> (URL, ImageFormat)? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.directoryURL = initialDirectory
        panel.level = .screenSaver
        let accessory = FormatAccessoryView(panel: panel, format: format)
        panel.accessoryView = accessory
        accessory.apply()
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, var url = panel.url else { return nil }
        let chosen = ImageFormat.from(url: url) ?? accessory.format
        if ImageFormat.from(url: url) == nil {
            url = url.appendingPathExtension(chosen.fileExtension)
        }
        guard let data = ImageComposer.data(image, format: chosen) else { throw ClipboardExporter.Failure.encoding }
        try data.write(to: url, options: .atomic)
        return (url, chosen)
    }
}

/// "Format: [JPEG ▾]" row shown inside the save panel; switching updates the allowed type and
/// the file name's extension.
final class FormatAccessoryView: NSView {
    private weak var panel: NSSavePanel?
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    private(set) var format: ImageFormat

    init(panel: NSSavePanel, format: ImageFormat) {
        self.panel = panel
        self.format = format
        super.init(frame: CGRect(x: 0, y: 0, width: 260, height: 36))
        let label = NSTextField(labelWithString: "Format:")
        label.frame = CGRect(x: 40, y: 10, width: 60, height: 18)
        label.alignment = .right
        addSubview(label)
        for f in ImageFormat.allCases { popup.addItem(withTitle: f.title) }
        popup.selectItem(at: ImageFormat.allCases.firstIndex(of: format) ?? 0)
        popup.frame = CGRect(x: 106, y: 5, width: 110, height: 26)
        popup.target = self
        popup.action = #selector(changed)
        addSubview(popup)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func changed() {
        format = ImageFormat.allCases[popup.indexOfSelectedItem]
        apply()
    }

    func apply() {
        guard let panel else { return }
        panel.allowedContentTypes = [format.utType]
        let current = panel.nameFieldStringValue
        let stem = current.isEmpty ? FileExporter.defaultFilename(format: format) : current
        let base = (stem as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(base).\(format.fileExtension)"
    }
}
