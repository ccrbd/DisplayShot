import AppKit

/// Draws annotations into a y-down CGContext whose units are points.
/// The caller must have `NSGraphicsContext.current` set (flipped) so text can be drawn.
enum AnnotationRenderer {
    static let markerAlpha: CGFloat = 0.35

    static func draw(_ items: [Annotation], in ctx: CGContext, clip: CGRect?) {
        ctx.saveGState()
        if let clip { ctx.clip(to: clip) }

        // All marker strokes are drawn opaque into one transparency layer that is composited
        // once with alpha + multiply, so overlapping strokes never darken twice.
        let markers = items.filter { $0.isMarker }
        if !markers.isEmpty {
            ctx.saveGState()
            ctx.setAlpha(markerAlpha)
            ctx.setBlendMode(.multiply)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            for m in markers {
                if case .marker(let pts, let s) = m.kind { strokePath(pts, s, in: ctx) }
            }
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }

        for a in items where !a.isMarker && !a.isRedaction {
            draw(a, in: ctx)
        }
        ctx.restoreGState()
    }

    /// Draws one annotation (used for the in-progress shape). Redactions are pixel operations
    /// handled by `Redactor`, so they are skipped here.
    static func draw(_ a: Annotation, in ctx: CGContext) {
        switch a.kind {
        case .pen(let pts, let s):
            strokePath(pts, s, in: ctx)
        case .marker(let pts, let s):
            ctx.saveGState()
            ctx.setAlpha(markerAlpha)
            ctx.setBlendMode(.multiply)
            strokePath(pts, s, in: ctx)
            ctx.restoreGState()
        case .line(let p, let q, let s):
            applyStroke(s, ctx)
            ctx.move(to: p)
            ctx.addLine(to: q)
            ctx.strokePath()
        case .arrow(let p, let q, let s):
            drawArrow(from: p, to: q, s, in: ctx)
        case .rectangle(let r, let s):
            applyStroke(s, ctx)
            ctx.stroke(r)
        case .text(let t):
            drawText(t, in: ctx)
        case .redact:
            break
        }
    }

    static func applyStroke(_ s: Stroke, _ ctx: CGContext) {
        ctx.setStrokeColor(s.color)
        ctx.setLineWidth(s.width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
    }

    /// Smooth freehand path through the points (quadratic curves through midpoints).
    static func strokePath(_ pts: [CGPoint], _ s: Stroke, in ctx: CGContext) {
        guard let first = pts.first else { return }
        applyStroke(s, ctx)
        let path = CGMutablePath()
        path.move(to: first)
        if pts.count <= 2 {
            path.addLine(to: pts.last ?? first)
        } else {
            for i in 1..<(pts.count - 1) {
                let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2, y: (pts[i].y + pts[i + 1].y) / 2)
                path.addQuadCurve(to: mid, control: pts[i])
            }
            path.addLine(to: pts[pts.count - 1])
        }
        ctx.addPath(path)
        ctx.strokePath()
    }

    static func drawArrow(from p: CGPoint, to q: CGPoint, _ s: Stroke, in ctx: CGContext) {
        let dx = q.x - p.x, dy = q.y - p.y
        let len = hypot(dx, dy)
        guard len > 0.5 else { return }
        let ux = dx / len, uy = dy / len
        let headLength = max(12, s.width * 4)
        let headWidth = max(10, s.width * 3.2)
        let base = CGPoint(x: q.x - ux * headLength, y: q.y - uy * headLength)
        let shaftEnd = CGPoint(x: q.x - ux * headLength * 0.7, y: q.y - uy * headLength * 0.7)

        applyStroke(s, ctx)
        ctx.move(to: p)
        ctx.addLine(to: shaftEnd)
        ctx.strokePath()

        let nx = -uy, ny = ux
        let left = CGPoint(x: base.x + nx * headWidth / 2, y: base.y + ny * headWidth / 2)
        let right = CGPoint(x: base.x - nx * headWidth / 2, y: base.y - ny * headWidth / 2)
        ctx.setFillColor(s.color)
        ctx.move(to: q)
        ctx.addLine(to: left)
        ctx.addLine(to: right)
        ctx.closePath()
        ctx.fillPath()
    }

    static func textAttributes(_ t: TextAnnotation) -> [NSAttributedString.Key: Any] {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.55)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        return [
            .font: NSFont.systemFont(ofSize: t.fontSize, weight: .semibold),
            .foregroundColor: NSColor(cgColor: t.color) ?? .white,
            .shadow: shadow,
        ]
    }

    static func textSize(_ t: TextAnnotation) -> CGSize {
        NSAttributedString(string: t.string, attributes: textAttributes(t)).size()
    }

    static func drawText(_ t: TextAnnotation, in ctx: CGContext) {
        let str = NSAttributedString(string: t.string, attributes: textAttributes(t))
        str.draw(at: t.origin)
    }
}
