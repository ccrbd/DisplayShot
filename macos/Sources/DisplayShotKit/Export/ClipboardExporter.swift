import AppKit

enum ClipboardExporter {
    enum Failure: Error { case encoding, pasteboard }

    /// Writes PNG + TIFF representations and verifies the pasteboard actually changed.
    static func copy(_ image: CGImage) throws {
        guard let png = ImageComposer.pngData(image) else { throw Failure.encoding }
        let pb = NSPasteboard.general
        let before = pb.changeCount
        pb.clearContents()
        pb.declareTypes([.png, .tiff], owner: nil)
        var ok = pb.setData(png, forType: .png)
        if let tiff = ImageComposer.tiffData(image) {
            ok = pb.setData(tiff, forType: .tiff) && ok
        }
        guard ok, pb.changeCount != before else { throw Failure.pasteboard }
    }
}
