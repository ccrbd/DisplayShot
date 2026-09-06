import AppKit
import OSLog
import ScreenCaptureKit

struct DisplayCapture {
    let screen: NSScreen
    let image: CGImage
    /// Backing scale: image pixels per point.
    let scale: CGFloat
}

enum CaptureError: LocalizedError {
    case noDisplays

    var errorDescription: String? {
        switch self {
        case .noDisplays: return "No displays could be captured."
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

/// Grabs every display at native resolution, without the cursor, using ScreenCaptureKit.
@MainActor
final class ScreenCapturer {
    func captureAll() async throws -> [DisplayCapture] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var results: [DisplayCapture] = []
        for screen in NSScreen.screens {
            guard let id = screen.displayID,
                  let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            let scale = screen.backingScaleFactor
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * scale)
            config.height = Int(screen.frame.height * scale)
            config.showsCursor = false
            config.captureResolution = .best
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.colorSpaceName = CGColorSpace.sRGB
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            Logger(subsystem: "com.ccrbd.DisplayShot", category: "capture")
                .info("display \(id) frame \(Int(screen.frame.width))x\(Int(screen.frame.height)) pt @\(scale)x -> captured \(image.width)x\(image.height) px")
            results.append(DisplayCapture(screen: screen, image: image, scale: scale))
        }
        guard !results.isEmpty else { throw CaptureError.noDisplays }
        return results
    }
}
