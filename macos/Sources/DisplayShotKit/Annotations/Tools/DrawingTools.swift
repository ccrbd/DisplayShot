import CoreGraphics

/// Pure helpers that create and update the in-progress annotation for each drawing tool.
enum DrawingTools {
    /// Starts a new annotation for `tool` at `p`. Returns nil for tools that do not drag (text).
    static func begin(_ tool: ToolKind, at p: CGPoint, color: CGColor, width: CGFloat, blur: Bool) -> Annotation? {
        let stroke = Stroke(color: color, width: width)
        switch tool {
        case .pen: return Annotation(.pen([p], stroke))
        case .marker: return Annotation(.marker([p], stroke))
        case .line: return Annotation(.line(p, p, stroke))
        case .arrow: return Annotation(.arrow(p, p, stroke))
        case .rectangle: return Annotation(.rectangle(CGRect(origin: p, size: .zero), stroke))
        case .redact: return Annotation(.redact(CGRect(origin: p, size: .zero), blur ? .blur : .pixelate, width))
        case .text, .emoji, .eraser: return nil
        }
    }

    /// Extends `annotation` to the current pointer position. `constrain` is the Shift modifier:
    /// 45° snapping for line/arrow, square for rectangle, blur mode for redaction.
    static func update(_ annotation: Annotation, origin: CGPoint, to p: CGPoint, constrain: Bool) -> Annotation {
        var copy = annotation
        switch annotation.kind {
        case .pen(var pts, let s):
            if pts.last != p { pts.append(p) }
            copy.kind = .pen(pts, s)
        case .marker(var pts, let s):
            if pts.last != p { pts.append(p) }
            copy.kind = .marker(pts, s)
        case .line(let a, _, let s):
            copy.kind = .line(a, constrain ? snapAngle(from: a, to: p) : p, s)
        case .arrow(let a, _, let s):
            copy.kind = .arrow(a, constrain ? snapAngle(from: a, to: p) : p, s)
        case .rectangle(_, let s):
            copy.kind = .rectangle(rect(from: origin, to: p, square: constrain), s)
        case .redact(_, let mode, let block):
            // The mode is owned by the session (right-click choice / Shift); only the rect changes here.
            copy.kind = .redact(CGRect(corner: origin, p), mode, block)
        case .text, .emoji:
            break
        }
        return copy
    }

    static func rect(from o: CGPoint, to p: CGPoint, square: Bool) -> CGRect {
        guard square else { return CGRect(corner: o, p) }
        let dx = p.x - o.x, dy = p.y - o.y
        let side = max(abs(dx), abs(dy))
        let sx: CGFloat = dx < 0 ? -1 : 1
        let sy: CGFloat = dy < 0 ? -1 : 1
        return CGRect(corner: o, CGPoint(x: o.x + sx * side, y: o.y + sy * side))
    }
}
