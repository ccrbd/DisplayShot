import CoreGraphics
@testable import DisplayShotKit

enum AnnotationChecks {
    static let stroke = Stroke(color: CGColor(gray: 0, alpha: 1), width: 2)

    static func line(_ x: CGFloat) -> Annotation {
        Annotation(.line(CGPoint(x: x, y: 0), CGPoint(x: x, y: 10), stroke))
    }

    static func run() {
        Checks.suite("Annotations") {
            Checks.run("undo/redo is sequential and a new action clears redo") {
                let store = AnnotationStore()
                try expectFalse(store.canUndo)
                store.add(line(1)); store.add(line(2)); store.add(line(3))
                try expectEqual(store.items.count, 3)
                try expect(store.undo())
                try expectEqual(store.items.count, 2)
                try expect(store.canRedo)
                try expect(store.undo())
                try expect(store.redo())
                try expectEqual(store.items.count, 2)
                store.add(line(4))
                try expectFalse(store.canRedo)
                try expectEqual(store.items.count, 3)
                store.clear()
                try expect(store.isEmpty)
                try expectFalse(store.undo())
                try expectFalse(store.redo())
            }
            Checks.run("meaningfulness thresholds") {
                try expectFalse(Annotation(.line(.zero, CGPoint(x: 1, y: 0), stroke)).isMeaningful)
                try expect(Annotation(.line(.zero, CGPoint(x: 5, y: 0), stroke)).isMeaningful)
                try expectFalse(Annotation(.rectangle(CGRect(x: 0, y: 0, width: 1, height: 10), stroke)).isMeaningful)
                try expect(Annotation(.redact(CGRect(x: 0, y: 0, width: 4, height: 4), .pixelate, 8)).isMeaningful)
                try expectFalse(Annotation(.text(TextAnnotation(origin: .zero, string: "  \n", color: stroke.color, fontSize: 18))).isMeaningful)
            }
            Checks.run("withWidth replaces stroke width / font size / block size") {
                let a = Annotation(.arrow(.zero, CGPoint(x: 10, y: 10), stroke)).withWidth(7)
                guard case .arrow(_, _, let s) = a.kind else { throw CheckFailure(description: "not an arrow") }
                try expectEqual(s.width, 7)
                let t = Annotation(.text(TextAnnotation(origin: .zero, string: "x", color: stroke.color, fontSize: 18))).withWidth(30)
                guard case .text(let ta) = t.kind else { throw CheckFailure(description: "not text") }
                try expectEqual(ta.fontSize, 30)
                let r = Annotation(.redact(CGRect(x: 0, y: 0, width: 4, height: 4), .blur, 8)).withWidth(12)
                guard case .redact(_, .blur, let block) = r.kind else { throw CheckFailure(description: "not redact") }
                try expectEqual(block, 12)
            }
            Checks.run("45° snapping keeps length") {
                let snapped = snapAngle(from: .zero, to: CGPoint(x: 100, y: 8))
                try expectEqual(snapped.y, 0, accuracy: 0.001)
                try expectEqual(snapped.x, hypot(100, 8), accuracy: 0.001)
                let diagonal = snapAngle(from: .zero, to: CGPoint(x: 100, y: 90))
                try expectEqual(diagonal.x, diagonal.y, accuracy: 0.001)
            }
            Checks.run("square rectangle from drag in every direction") {
                try expectEqual(DrawingTools.rect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 40, y: 20), square: true),
                                CGRect(x: 10, y: 10, width: 30, height: 30))
                try expectEqual(DrawingTools.rect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 90, y: 60), square: true),
                                CGRect(x: 60, y: 60, width: 40, height: 40))
            }
            Checks.run("drawing tools: begin/update per tool") {
                let color = CGColor(gray: 1, alpha: 1)
                try expect(DrawingTools.begin(.text, at: .zero, color: color, width: 18, blur: false) == nil)
                guard let pen = DrawingTools.begin(.pen, at: CGPoint(x: 1, y: 1), color: color, width: 3, blur: false) else {
                    throw CheckFailure(description: "pen did not begin")
                }
                let pen2 = DrawingTools.update(pen, origin: CGPoint(x: 1, y: 1), to: CGPoint(x: 5, y: 5), constrain: false)
                guard case .pen(let pts, _) = pen2.kind else { throw CheckFailure(description: "not a pen") }
                try expectEqual(pts.count, 2)
                guard let redact = DrawingTools.begin(.redact, at: CGPoint(x: 10, y: 10), color: color, width: 8, blur: false) else {
                    throw CheckFailure(description: "redact did not begin")
                }
                let blurred = DrawingTools.update(redact, origin: CGPoint(x: 10, y: 10), to: CGPoint(x: 30, y: 20), constrain: true)
                guard case .redact(let rr, let mode, _) = blurred.kind else { throw CheckFailure(description: "not redact") }
                try expectEqual(mode, .blur)
                try expectEqual(rr, CGRect(x: 10, y: 10, width: 20, height: 10))
            }
            Checks.run("hot key display string and defaults") {
                try expectEqual(HotKey.default.displayString, "⇧⌘1")
                try expectEqual(HotKey(keyCode: 122, carbonModifiers: 0, keyLabel: "F1").displayString, "F1")
            }
        }
    }
}
