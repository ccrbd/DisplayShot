import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

struct RedactPatch {
    let image: CGImage
    /// Pixel rect (top-left origin) within the source image that `image` covers.
    let pixelRect: CGRect
}

/// Produces pixelated / blurred patches of a source image. The pixelation grid is anchored to
/// the image origin, so moving or resizing a redaction never makes the blocks shift.
final class Redactor {
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var cache: [String: RedactPatch] = [:]

    func clearCache() { cache.removeAll() }

    func patch(source: CGImage, pixelRect: CGRect, mode: RedactMode, blockPixels: CGFloat) -> RedactPatch? {
        let bounds = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let r = pixelRect.integral.intersection(bounds)
        guard r.width >= 1, r.height >= 1 else { return nil }
        let block = max(2, blockPixels.rounded())
        let key = "\(mode.rawValue)|\(block)|\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))"
        if let cached = cache[key] { return cached }

        if mode == .blackout {
            guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: nil, width: Int(r.width), height: Int(r.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: r.width, height: r.height))
            guard let img = ctx.makeImage() else { return nil }
            let patch = RedactPatch(image: img, pixelRect: r)
            cache[key] = patch
            return patch
        }

        let input = CIImage(cgImage: source).clampedToExtent()
        let output: CIImage
        switch mode {
        case .pixelate:
            let f = CIFilter.pixellate()
            f.inputImage = input
            f.scale = Float(block)
            f.center = .zero
            guard let out = f.outputImage else { return nil }
            output = out
        case .blur:
            let f = CIFilter.gaussianBlur()
            f.inputImage = input
            f.radius = Float(block * 1.5)
            guard let out = f.outputImage else { return nil }
            output = out
        case .blackout:
            return nil
        }
        // Core Image uses a bottom-left origin.
        let ciRect = CGRect(x: r.minX, y: CGFloat(source.height) - r.maxY, width: r.width, height: r.height)
        guard let img = ciContext.createCGImage(output, from: ciRect) else { return nil }
        let patch = RedactPatch(image: img, pixelRect: r)
        cache[key] = patch
        return patch
    }
}
