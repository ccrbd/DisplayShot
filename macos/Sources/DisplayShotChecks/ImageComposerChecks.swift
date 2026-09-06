import AppKit
@testable import DisplayShotKit

enum ImageComposerChecks {
    /// 2-pixel black/white checkerboard: any blur or pixelation changes it dramatically.
    static func makeSource(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                let dark = ((x / 2) + (y / 2)) % 2 == 0
                ctx.setFillColor(dark ? CGColor(gray: 0, alpha: 1) : CGColor(gray: 1, alpha: 1))
                ctx.fill(CGRect(x: x, y: y, width: 2, height: 2))
            }
        }
        return ctx.makeImage()!
    }

    struct Pixels {
        let data: [UInt8]
        let bytesPerRow: Int

        init(_ image: CGImage) {
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            bytesPerRow = image.width * 4
            var buffer = [UInt8](repeating: 0, count: bytesPerRow * image.height)
            let bpr = bytesPerRow
            buffer.withUnsafeMutableBytes { buf in
                let ctx = CGContext(data: buf.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: bpr, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            data = buffer
        }

        /// Bytes of a pixel rect (top-left origin, like the composer output).
        func region(_ r: CGRect) -> [UInt8] {
            var out: [UInt8] = []
            for y in Int(r.minY)..<Int(r.maxY) {
                let start = y * bytesPerRow + Int(r.minX) * 4
                out.append(contentsOf: data[start..<(start + Int(r.width) * 4)])
            }
            return out
        }
    }

    static func compose(_ src: CGImage, _ sel: CGRect, _ annotations: [Annotation], _ redactor: Redactor = Redactor()) throws -> CGImage {
        guard let img = ImageComposer.compose(source: src, scale: 2, selection: sel, annotations: annotations, redactor: redactor) else {
            throw CheckFailure(description: "compose returned nil")
        }
        return img
    }

    static func run() {
        Checks.suite("ImageComposer") {
            Checks.run("output size is selection × scale") {
                let img = try compose(makeSource(width: 400, height: 200), CGRect(x: 10, y: 10, width: 50, height: 25), [])
                try expectEqual(img.width, 100)
                try expectEqual(img.height, 50)
            }
            Checks.run("crop matches the source region exactly (no flip, no offset)") {
                let src = makeSource(width: 400, height: 200)
                let sel = CGRect(x: 20, y: 10, width: 40, height: 20)
                let out = Pixels(try compose(src, sel, []))
                let ref = Pixels(src.cropping(to: sel.scaled(2))!)
                try expectEqual(out.data, ref.data)
                // Also check against an asymmetric source so a vertical flip would be caught.
                let asym = CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                asym.setFillColor(CGColor(gray: 1, alpha: 1)); asym.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
                asym.setFillColor(CGColor(gray: 0, alpha: 1)); asym.fill(CGRect(x: 0, y: 30, width: 40, height: 10)) // CG bottom-left: top rows in image space
                let asymImg = asym.makeImage()!
                let full = Pixels(try compose(asymImg, CGRect(x: 0, y: 0, width: 20, height: 20), []))
                try expectEqual(Int(full.data[0]), 0, "top-left pixel should be black")
                try expectEqual(Int(full.data[39 * full.bytesPerRow]), 255, "bottom-left pixel should be white")
            }
            Checks.run("pixelate redaction changes pixels only inside its rect") {
                let src = makeSource(width: 400, height: 200)
                let sel = CGRect(x: 0, y: 0, width: 200, height: 100)
                let redactor = Redactor()
                let plain = Pixels(try compose(src, sel, [], redactor))
                let redact = Annotation(.redact(CGRect(x: 50, y: 20, width: 40, height: 20), .pixelate, 8))
                let redacted = Pixels(try compose(src, sel, [redact], redactor))
                let inside = CGRect(x: 100, y: 40, width: 80, height: 40)
                try expectNotEqual(plain.region(inside), redacted.region(inside), "redacted area should differ")
                try expectEqual(plain.region(CGRect(x: 0, y: 0, width: 400, height: 30)), redacted.region(CGRect(x: 0, y: 0, width: 400, height: 30)), "area above the redaction must be untouched")
                try expectEqual(plain.region(CGRect(x: 200, y: 40, width: 200, height: 40)), redacted.region(CGRect(x: 200, y: 40, width: 200, height: 40)), "area right of the redaction must be untouched")
            }
            Checks.run("pixelation grid is anchored to the image, not the rect") {
                let src = makeSource(width: 400, height: 200)
                let sel = CGRect(x: 0, y: 0, width: 200, height: 100)
                let redactor = Redactor()
                // Two redactions whose rects differ by a few points must produce identical pixels where they overlap.
                let a = Pixels(try compose(src, sel, [Annotation(.redact(CGRect(x: 40, y: 20, width: 60, height: 30), .pixelate, 8))], redactor))
                let b = Pixels(try compose(src, sel, [Annotation(.redact(CGRect(x: 43, y: 22, width: 60, height: 30), .pixelate, 8))], redactor))
                let overlap = CGRect(x: 96, y: 48, width: 96, height: 48) // pixels covered by both
                try expectEqual(a.region(overlap), b.region(overlap), "blocks should not shift when the rect moves")
            }
            Checks.run("blur redaction also changes pixels") {
                let src = makeSource(width: 200, height: 100)
                let sel = CGRect(x: 0, y: 0, width: 100, height: 50)
                let redactor = Redactor()
                let plain = Pixels(try compose(src, sel, [], redactor))
                let blurred = Pixels(try compose(src, sel, [Annotation(.redact(CGRect(x: 10, y: 10, width: 30, height: 20), .blur, 8))], redactor))
                let inside = CGRect(x: 20, y: 20, width: 60, height: 40)
                try expectNotEqual(plain.region(inside), blurred.region(inside))
            }
            Checks.run("annotations are drawn into the output at pixel scale") {
                let src = makeSource(width: 200, height: 100)
                let sel = CGRect(x: 0, y: 0, width: 100, height: 50)
                let stroke = Stroke(color: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), width: 4)
                let rect = Annotation(.rectangle(CGRect(x: 10, y: 10, width: 40, height: 20), stroke))
                let plain = Pixels(try compose(src, sel, []))
                let drawn = Pixels(try compose(src, sel, [rect]))
                try expectNotEqual(plain.data, drawn.data)
                let idx = 20 * drawn.bytesPerRow + 40 * 4 // point (20,10) → pixel (40,20), on the top edge
                try expectGreater(Int(drawn.data[idx]), 200)
                try expectLess(Int(drawn.data[idx + 1]), 80)
            }
            Checks.run("annotations are clipped to the selection") {
                let src = makeSource(width: 200, height: 100)
                let sel = CGRect(x: 20, y: 20, width: 40, height: 20)
                let stroke = Stroke(color: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), width: 6)
                let outsideLine = Annotation(.line(CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10), stroke))
                let plain = Pixels(try compose(src, sel, []))
                let drawn = Pixels(try compose(src, sel, [outsideLine]))
                try expectEqual(plain.data, drawn.data, "a line outside the selection must not appear")
            }
            Checks.run("marker keeps text legible: overlapping strokes do not double-darken") {
                let cs = CGColorSpace(name: CGColorSpace.sRGB)!
                let ctx = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
                let white = ctx.makeImage()!
                let sel = CGRect(x: 0, y: 0, width: 100, height: 50)
                let stroke = Stroke(color: CGColor(srgbRed: 1, green: 1, blue: 0, alpha: 1), width: 20)
                let one = Pixels(try compose(white, sel, [Annotation(.marker([CGPoint(x: 10, y: 25), CGPoint(x: 90, y: 25)], stroke))]))
                let two = Pixels(try compose(white, sel, [
                    Annotation(.marker([CGPoint(x: 10, y: 25), CGPoint(x: 90, y: 25)], stroke)),
                    Annotation(.marker([CGPoint(x: 10, y: 25), CGPoint(x: 90, y: 25)], stroke)),
                ]))
                let idx = 50 * one.bytesPerRow + 100 * 4
                try expectEqual(Int(one.data[idx + 2]), Int(two.data[idx + 2]), "blue channel should be identical with one or two overlapping strokes")
                try expectLess(Int(one.data[idx + 2]), 255, "marker should tint the white background")
            }
            Checks.run("blackout redaction paints solid black") {
                let src = makeSource(width: 200, height: 100)
                let sel = CGRect(x: 0, y: 0, width: 100, height: 50)
                let out = Pixels(try compose(src, sel, [Annotation(.redact(CGRect(x: 10, y: 10, width: 30, height: 20), .blackout, 8))]))
                for y in 20..<60 {
                    for x in 20..<80 {
                        let i = y * out.bytesPerRow + x * 4
                        try expectEqual(Int(out.data[i]), 0, "R at (\(x),\(y))")
                        try expectEqual(Int(out.data[i + 1]), 0, "G at (\(x),\(y))")
                        try expectEqual(Int(out.data[i + 2]), 0, "B at (\(x),\(y))")
                    }
                }
                let outside = 5 * out.bytesPerRow + 5 * 4
                try expect(out.data[outside] == 0 || out.data[outside] == 255, "outside should be untouched checkerboard")
            }
            Checks.run("emoji is drawn, and rotation changes the result") {
                let cs = CGColorSpace(name: CGColorSpace.sRGB)!
                let ctx = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
                let white = ctx.makeImage()!
                let sel = CGRect(x: 0, y: 0, width: 100, height: 100)
                let plain = Pixels(try compose(white, sel, []))
                let up = Pixels(try compose(white, sel, [Annotation(.emoji(EmojiAnnotation(center: CGPoint(x: 50, y: 50), string: "👉", size: 40, rotation: 0)))]))
                let turned = Pixels(try compose(white, sel, [Annotation(.emoji(EmojiAnnotation(center: CGPoint(x: 50, y: 50), string: "👉", size: 40, rotation: 90)))]))
                try expectNotEqual(plain.data, up.data, "emoji should draw")
                try expectNotEqual(up.data, turned.data, "rotation should change pixels")
                try expect(EmojiAnnotation(center: CGPoint(x: 50, y: 50), string: "👉", size: 40, rotation: 0).bounds.contains(CGPoint(x: 60, y: 60)))
            }
            Checks.run("JPEG and TIFF encoding") {
                let img = makeSource(width: 16, height: 16)
                let jpeg = ImageComposer.data(img, format: .jpeg)
                try expect(jpeg != nil)
                try expectEqual(Array(jpeg!.prefix(2)), [0xFF, 0xD8])
                try expect(ImageComposer.data(img, format: .tiff) != nil)
                try expectEqual(FileExporter.defaultFilename(date: Date(timeIntervalSince1970: 0), format: .jpeg).hasSuffix(".jpg"), true)
            }
            Checks.run("PNG encoding") {
                let data = ImageComposer.pngData(makeSource(width: 16, height: 16))
                try expect(data != nil)
                try expectEqual(Array(data!.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
            }
            Checks.run("default filename format") {
                let name = FileExporter.defaultFilename(date: Date(timeIntervalSince1970: 0))
                try expect(name.hasPrefix("DisplayShot "))
                try expect(name.hasSuffix(".png"))
                try expect(name.contains(" at "))
            }
        }
    }
}
