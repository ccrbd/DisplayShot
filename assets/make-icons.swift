// Renders the DisplayShot icon at every size needed by macOS, Windows and the web.
// Usage: swift assets/make-icons.swift <output-dir>
// Requires only the macOS SDK (works with Command Line Tools, no Xcode).
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets/build")
let pngDir = outDir.appendingPathComponent("png")
let iconset = outDir.appendingPathComponent("DisplayShot.iconset")
for dir in [pngDir, iconset] {
    try? FileManager.default.removeItem(at: dir)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
}

/// Draws the icon: dark slate rounded square, four viewfinder corner brackets, coral capture dot.
/// `fullBleed` fills the whole canvas (web favicon); otherwise the macOS-style 8 % margin is kept.
func render(size: Int, fullBleed: Bool) -> CGImage {
    let s = CGFloat(size)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let inset = fullBleed ? 0 : s * 0.08
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = rect.width * 0.225
    let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let colors = [CGColor(srgbRed: 0.19, green: 0.24, blue: 0.34, alpha: 1),
                  CGColor(srgbRed: 0.05, green: 0.07, blue: 0.13, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY),
                           end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    ctx.restoreGState()

    // Viewfinder brackets
    let frame = rect.insetBy(dx: rect.width * 0.22, dy: rect.width * 0.22)
    let arm = frame.width * 0.30
    let lineWidth = max(1.0, rect.width * 0.075)
    ctx.setStrokeColor(CGColor(srgbRed: 0.93, green: 0.96, blue: 1.0, alpha: 1))
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (frame.minX, frame.minY, 1, 1), (frame.maxX, frame.minY, -1, 1),
        (frame.minX, frame.maxY, 1, -1), (frame.maxX, frame.maxY, -1, -1),
    ]
    for (cx, cy, dx, dy) in corners {
        ctx.move(to: CGPoint(x: cx, y: cy + dy * arm))
        ctx.addLine(to: CGPoint(x: cx, y: cy))
        ctx.addLine(to: CGPoint(x: cx + dx * arm, y: cy))
    }
    ctx.strokePath()

    // Capture dot
    let r = frame.width * 0.14
    ctx.setFillColor(CGColor(srgbRed: 1.0, green: 0.45, blue: 0.25, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: frame.midX - r, y: frame.midY - r, width: 2 * r, height: 2 * r))
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("failed to write \(url.path)") }
}

// Generic PNG set (used for the Windows .ico and the favicon)
for size in [16, 24, 32, 48, 64, 128, 256, 512, 1024] {
    writePNG(render(size: size, fullBleed: false), to: pngDir.appendingPathComponent("icon-\(size).png"))
}
for size in [16, 32, 48, 180, 512] {
    writePNG(render(size: size, fullBleed: true), to: pngDir.appendingPathComponent("favicon-\(size).png"))
}
// macOS iconset naming
for base in [16, 32, 128, 256, 512] {
    writePNG(render(size: base, fullBleed: false), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(render(size: base * 2, fullBleed: false), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("icons rendered to \(outDir.path)")
