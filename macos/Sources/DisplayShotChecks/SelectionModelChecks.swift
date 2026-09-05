import CoreGraphics
@testable import DisplayShotKit

enum SelectionModelChecks {
    static let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)

    static func run() {
        Checks.suite("SelectionModel") {
            Checks.run("drag rect normalizes and clamps") {
                let r = SelectionModel.rect(from: CGPoint(x: 300, y: 200), to: CGPoint(x: 100, y: 700), square: false, in: bounds)
                try expectEqual(r, CGRect(x: 100, y: 200, width: 200, height: 400))
            }
            Checks.run("square drag uses the larger side and respects bounds") {
                let r = SelectionModel.rect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 150), square: true, in: bounds)
                try expectEqual(r, CGRect(x: 100, y: 100, width: 200, height: 200))
                let clamped = SelectionModel.rect(from: CGPoint(x: 900, y: 100), to: CGPoint(x: 990, y: 500), square: true, in: bounds)
                try expectEqual(clamped, CGRect(x: 900, y: 100, width: 100, height: 100))
            }
            Checks.run("hit test: handles, inside, outside") {
                let m = SelectionModel(rect: CGRect(x: 100, y: 100, width: 200, height: 100), bounds: bounds)
                try expectEqual(m.hitTest(CGPoint(x: 100, y: 100)), .handle(.topLeft))
                try expectEqual(m.hitTest(CGPoint(x: 300, y: 150)), .handle(.right))
                try expectEqual(m.hitTest(CGPoint(x: 200, y: 200)), .handle(.bottom))
                try expectEqual(m.hitTest(CGPoint(x: 305, y: 205)), .handle(.bottomRight))
                try expectEqual(m.hitTest(CGPoint(x: 200, y: 150)), .inside)
                try expectEqual(m.hitTest(CGPoint(x: 50, y: 50)), .outside)
            }
            Checks.run("resize edge, then flip through itself") {
                var m = SelectionModel(rect: CGRect(x: 100, y: 100, width: 200, height: 100), bounds: bounds)
                let h = m.resize(.right, to: CGPoint(x: 400, y: 999), square: false)
                try expectEqual(h, .right)
                try expectEqual(m.rect, CGRect(x: 100, y: 100, width: 300, height: 100))
                let flipped = m.resize(.right, to: CGPoint(x: 50, y: 0), square: false)
                try expectEqual(flipped, .left)
                try expectEqual(m.rect, CGRect(x: 50, y: 100, width: 50, height: 100))
            }
            Checks.run("corner resize with square constraint") {
                var m = SelectionModel(rect: CGRect(x: 100, y: 100, width: 200, height: 100), bounds: bounds)
                let h = m.resize(.bottomRight, to: CGPoint(x: 400, y: 150), square: true)
                try expectEqual(h, .bottomRight)
                try expectEqual(m.rect, CGRect(x: 100, y: 100, width: 300, height: 300))
            }
            Checks.run("move clamps to bounds") {
                var m = SelectionModel(rect: CGRect(x: 100, y: 100, width: 200, height: 100), bounds: bounds)
                m.move(to: CGPoint(x: 950, y: -20))
                try expectEqual(m.rect, CGRect(x: 800, y: 0, width: 200, height: 100))
            }
            Checks.run("nudge and grow") {
                var m = SelectionModel(rect: CGRect(x: 100, y: 100, width: 200, height: 100), bounds: bounds)
                m.nudge(dx: 1, dy: -1)
                try expectEqual(m.rect.origin, CGPoint(x: 101, y: 99))
                m.grow(dw: 10, dh: 10)
                try expectEqual(m.rect.size, CGSize(width: 210, height: 110))
                m.grow(dw: 100_000, dh: 0)
                try expectEqual(m.rect.maxX, bounds.maxX)
                m.grow(dw: -100_000, dh: 0)
                try expectEqual(m.rect.width, SelectionModel.minSize)
            }
            Checks.run("oversized rect is clamped to bounds") {
                let m = SelectionModel(rect: bounds.insetBy(dx: -50, dy: -50), bounds: bounds)
                try expectEqual(m.rect, bounds)
            }
            Checks.run("handle flips") {
                try expectEqual(Handle.topLeft.flippedHorizontally, .topRight)
                try expectEqual(Handle.left.flippedHorizontally, .right)
                try expectEqual(Handle.top.flippedHorizontally, .top)
                try expectEqual(Handle.bottomLeft.flippedVertically, .topLeft)
                try expectEqual(Handle.right.flippedVertically, .right)
            }
        }
    }
}
