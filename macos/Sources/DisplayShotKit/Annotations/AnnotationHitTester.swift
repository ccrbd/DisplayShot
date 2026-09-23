import AppKit

/// Decides whether an annotation is touched by the eraser circle (centre `p`, radius `r`).
enum AnnotationHitTester {
    static func hits(_ a: Annotation, circleAt p: CGPoint, radius r: CGFloat) -> Bool {
        switch a.kind {
        case .pen(let pts, let s), .marker(let pts, let s):
            let reach = r + s.width / 2
            guard pts.count > 1 else { return pts.first.map { $0.distance(to: p) <= reach } ?? false }
            for i in 0..<(pts.count - 1) where distance(from: p, toSegment: pts[i], pts[i + 1]) <= reach { return true }
            return false
        case .line(let a, let b, let s), .arrow(let a, let b, let s):
            return distance(from: p, toSegment: a, b) <= r + max(s.width / 2, s.width * 1.6)
        case .rectangle(let rect, let s):
            let reach = r + s.width / 2
            let tl = CGPoint(x: rect.minX, y: rect.minY), tr = CGPoint(x: rect.maxX, y: rect.minY)
            let bl = CGPoint(x: rect.minX, y: rect.maxY), br = CGPoint(x: rect.maxX, y: rect.maxY)
            return [(tl, tr), (tr, br), (br, bl), (bl, tl)].contains { distance(from: p, toSegment: $0.0, $0.1) <= reach }
        case .ellipse(let rect, let s):
            // Distance to the ellipse outline at the parametric angle of `p`.
            let a = rect.width / 2, b = rect.height / 2
            guard a > 0, b > 0 else { return false }
            let c = rect.center
            let angle = atan2((p.y - c.y) / b, (p.x - c.x) / a)
            let q = CGPoint(x: c.x + a * cos(angle), y: c.y + b * sin(angle))
            return p.distance(to: q) <= r + s.width / 2
        case .text(let t):
            let size = AnnotationRenderer.textSize(t)
            return CGRect(origin: t.origin, size: size).insetBy(dx: -r, dy: -r).contains(p)
        case .emoji(let e):
            return e.bounds.insetBy(dx: -r, dy: -r).contains(p)
        case .redact(let rect, _, _):
            return rect.insetBy(dx: -r, dy: -r).contains(p)
        }
    }
}
