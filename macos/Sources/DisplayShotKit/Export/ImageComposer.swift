import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Produces the final image: cropped source at native pixel scale, redactions burned in,
/// annotations drawn on top with the same renderer the overlay uses.
enum ImageComposer {
    static func compose(source: CGImage, scale: CGFloat, selection: CGRect,
                        annotations: [Annotation], redactor: Redactor) -> CGImage? {
        let sourceBounds = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let pixelRect = selection.scaled(scale).integral.intersection(sourceBounds)
        guard pixelRect.width >= 1, pixelRect.height >= 1,
              let crop = source.cropping(to: pixelRect) else { return nil }
        let w = Int(pixelRect.width), h = Int(pixelRect.height)
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // Work in y-down pixel coordinates, like the overlay view.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .none
        drawImage(crop, in: CGRect(x: 0, y: 0, width: w, height: h), in: ctx)

        for a in annotations {
            guard case .redact(let rect, let mode, let block) = a.kind else { continue }
            let pr = rect.scaled(scale).integral
            guard let patch = redactor.patch(source: source, pixelRect: pr, mode: mode, blockPixels: block * scale) else { continue }
            let dest = CGRect(x: patch.pixelRect.minX - pixelRect.minX, y: patch.pixelRect.minY - pixelRect.minY,
                              width: patch.pixelRect.width, height: patch.pixelRect.height)
            drawImage(patch.image, in: dest, in: ctx)
        }

        // Annotations are stored in points; scale into pixels and shift by the crop origin.
        ctx.saveGState()
        ctx.interpolationQuality = .high
        ctx.setAllowsAntialiasing(true)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -pixelRect.minX / scale, y: -pixelRect.minY / scale)
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        AnnotationRenderer.draw(annotations, in: ctx, clip: pixelRect.scaled(1 / scale))
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()

        return ctx.makeImage()
    }

    /// Draws a CGImage upright into a y-down (flipped) context.
    static func drawImage(_ image: CGImage, in rect: CGRect, in ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }

    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    static func tiffData(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).tiffRepresentation
    }
}
