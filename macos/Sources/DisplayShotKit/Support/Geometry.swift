import CoreGraphics

extension CGRect {
    /// Rectangle spanning two arbitrary corner points.
    init(corner a: CGPoint, _ b: CGPoint) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    var center: CGPoint { CGPoint(x: midX, y: midY) }

    func scaled(_ s: CGFloat) -> CGRect {
        CGRect(x: minX * s, y: minY * s, width: width * s, height: height * s)
    }

    /// Shifts the rect so it lies inside `bounds`, shrinking it only if it is larger than `bounds`.
    func fitted(in bounds: CGRect) -> CGRect {
        var r = self
        r.size.width = min(r.width, bounds.width)
        r.size.height = min(r.height, bounds.height)
        if r.minX < bounds.minX { r.origin.x = bounds.minX }
        if r.maxX > bounds.maxX { r.origin.x = bounds.maxX - r.width }
        if r.minY < bounds.minY { r.origin.y = bounds.minY }
        if r.maxY > bounds.maxY { r.origin.y = bounds.maxY - r.height }
        return r
    }
}

extension CGPoint {
    func clamped(to r: CGRect) -> CGPoint {
        CGPoint(x: min(max(x, r.minX), r.maxX), y: min(max(y, r.minY), r.maxY))
    }

    func distance(to p: CGPoint) -> CGFloat { hypot(p.x - x, p.y - y) }

    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
}

@inline(__always) func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }

/// Snaps the segment `a -> b` to the nearest multiple of 45 degrees, preserving its length.
func snapAngle(from a: CGPoint, to b: CGPoint) -> CGPoint {
    let dx = b.x - a.x, dy = b.y - a.y
    let len = hypot(dx, dy)
    guard len > 0 else { return b }
    let step = CGFloat.pi / 4
    let angle = (atan2(dy, dx) / step).rounded() * step
    return CGPoint(x: a.x + cos(angle) * len, y: a.y + sin(angle) * len)
}
