import CoreGraphics

enum Handle: CaseIterable, Equatable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var affectsLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var affectsRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    var affectsTop: Bool { self == .topLeft || self == .top || self == .topRight }
    var affectsBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
    var isCorner: Bool { (affectsLeft || affectsRight) && (affectsTop || affectsBottom) }

    static func make(left: Bool, right: Bool, top: Bool, bottom: Bool) -> Handle? {
        switch (left, right, top, bottom) {
        case (true, false, true, false): return .topLeft
        case (false, false, true, false): return .top
        case (false, true, true, false): return .topRight
        case (false, true, false, false): return .right
        case (false, true, false, true): return .bottomRight
        case (false, false, false, true): return .bottom
        case (true, false, false, true): return .bottomLeft
        case (true, false, false, false): return .left
        default: return nil
        }
    }

    var flippedHorizontally: Handle {
        Handle.make(left: affectsRight, right: affectsLeft, top: affectsTop, bottom: affectsBottom) ?? self
    }

    var flippedVertically: Handle {
        Handle.make(left: affectsLeft, right: affectsRight, top: affectsBottom, bottom: affectsTop) ?? self
    }
}

enum SelectionHit: Equatable {
    case handle(Handle)
    case inside
    case outside
}

/// The selection rectangle on one display, in points with a top-left origin, always kept
/// inside `bounds`.
struct SelectionModel: Equatable {
    static let minSize: CGFloat = 1
    static let handleSize: CGFloat = 8
    static let handleHitRadius: CGFloat = 9

    private(set) var rect: CGRect
    let bounds: CGRect

    init(rect: CGRect, bounds: CGRect) {
        self.bounds = bounds
        self.rect = SelectionModel.normalize(rect, in: bounds)
    }

    static func normalize(_ r: CGRect, in bounds: CGRect) -> CGRect {
        let s = r.standardized
        let x0 = clamp(s.minX, bounds.minX, bounds.maxX), x1 = clamp(s.maxX, bounds.minX, bounds.maxX)
        let y0 = clamp(s.minY, bounds.minY, bounds.maxY), y1 = clamp(s.maxY, bounds.minY, bounds.maxY)
        let out = CGRect(x: x0, y: y0, width: max(minSize, x1 - x0), height: max(minSize, y1 - y0))
        return out.fitted(in: bounds)
    }

    /// Rect for a fresh drag from `origin` to `current`; `square` is the Shift constraint.
    static func rect(from origin: CGPoint, to current: CGPoint, square: Bool, in bounds: CGRect) -> CGRect {
        let c = current.clamped(to: bounds)
        var dx = c.x - origin.x, dy = c.y - origin.y
        if square {
            var side = max(abs(dx), abs(dy))
            let limX = dx >= 0 ? bounds.maxX - origin.x : origin.x - bounds.minX
            let limY = dy >= 0 ? bounds.maxY - origin.y : origin.y - bounds.minY
            side = min(side, limX, limY)
            dx = (dx < 0 ? -1 : 1) * side
            dy = (dy < 0 ? -1 : 1) * side
        }
        return CGRect(corner: origin, CGPoint(x: origin.x + dx, y: origin.y + dy))
    }

    func handleCenter(_ h: Handle) -> CGPoint {
        let x: CGFloat = h.affectsLeft ? rect.minX : (h.affectsRight ? rect.maxX : rect.midX)
        let y: CGFloat = h.affectsTop ? rect.minY : (h.affectsBottom ? rect.maxY : rect.midY)
        return CGPoint(x: x, y: y)
    }

    func handleRects() -> [(Handle, CGRect)] {
        let s = SelectionModel.handleSize
        return Handle.allCases.map { h in
            let c = handleCenter(h)
            return (h, CGRect(x: c.x - s / 2, y: c.y - s / 2, width: s, height: s))
        }
    }

    func hitTest(_ p: CGPoint) -> SelectionHit {
        let ordered = Handle.allCases.filter(\.isCorner) + Handle.allCases.filter { !$0.isCorner }
        for h in ordered where handleCenter(h).distance(to: p) <= SelectionModel.handleHitRadius {
            return .handle(h)
        }
        return rect.insetBy(dx: -2, dy: -2).contains(p) ? .inside : .outside
    }

    /// Drags `handle` to `point`. Returns the handle that now sits under the pointer (it flips
    /// when the rectangle is dragged through itself).
    @discardableResult
    mutating func resize(_ handle: Handle, to point: CGPoint, square: Bool) -> Handle {
        let p = point.clamped(to: bounds)
        var l = rect.minX, r = rect.maxX, t = rect.minY, b = rect.maxY

        if square && handle.isCorner {
            let ax = handle.affectsLeft ? r : l
            let ay = handle.affectsTop ? b : t
            let sx: CGFloat = p.x >= ax ? 1 : -1
            let sy: CGFloat = p.y >= ay ? 1 : -1
            var side = max(abs(p.x - ax), abs(p.y - ay))
            let limX = sx > 0 ? bounds.maxX - ax : ax - bounds.minX
            let limY = sy > 0 ? bounds.maxY - ay : ay - bounds.minY
            side = min(side, limX, limY)
            let nx = ax + sx * side, ny = ay + sy * side
            rect = SelectionModel.normalize(CGRect(corner: CGPoint(x: ax, y: ay), CGPoint(x: nx, y: ny)), in: bounds)
            return Handle.make(left: sx < 0, right: sx > 0, top: sy < 0, bottom: sy > 0) ?? handle
        }

        if handle.affectsLeft { l = p.x }
        if handle.affectsRight { r = p.x }
        if handle.affectsTop { t = p.y }
        if handle.affectsBottom { b = p.y }
        var h = handle
        if l > r { swap(&l, &r); h = h.flippedHorizontally }
        if t > b { swap(&t, &b); h = h.flippedVertically }
        rect = SelectionModel.normalize(CGRect(x: l, y: t, width: r - l, height: b - t), in: bounds)
        return h
    }

    mutating func move(to origin: CGPoint) {
        rect = CGRect(origin: origin, size: rect.size).fitted(in: bounds)
    }

    mutating func nudge(dx: CGFloat, dy: CGFloat) {
        move(to: CGPoint(x: rect.minX + dx, y: rect.minY + dy))
    }

    /// Grows/shrinks the right and bottom edges.
    mutating func grow(dw: CGFloat, dh: CGFloat) {
        var r = rect
        r.size.width = clamp(r.width + dw, SelectionModel.minSize, bounds.maxX - r.minX)
        r.size.height = clamp(r.height + dh, SelectionModel.minSize, bounds.maxY - r.minY)
        rect = r
    }
}
