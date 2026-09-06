import CoreGraphics
import Foundation

enum ToolKind: String, CaseIterable, Codable {
    case pen, line, arrow, rectangle, marker, text, emoji, redact

    var defaultWidth: CGFloat {
        switch self {
        case .pen: return 3
        case .line: return 3
        case .arrow: return 4
        case .rectangle: return 3
        case .marker: return 14
        case .text: return 18
        case .emoji: return 48
        case .redact: return 8
        }
    }

    var widthRange: ClosedRange<CGFloat> {
        switch self {
        case .text: return 8...96
        case .emoji: return 16...256
        case .redact: return 2...64
        default: return 1...32
        }
    }

    var title: String {
        switch self {
        case .pen: return "Pen"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .marker: return "Marker"
        case .text: return "Text"
        case .emoji: return "Emoji"
        case .redact: return "Redact"
        }
    }

    var symbolName: String {
        switch self {
        case .pen: return "pencil"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .marker: return "highlighter"
        case .text: return "textformat"
        case .emoji: return "face.smiling"
        case .redact: return "eye.slash"
        }
    }

    /// Single-key shortcut inside the overlay.
    var key: String {
        switch self {
        case .pen: return "p"
        case .line: return "l"
        case .arrow: return "a"
        case .rectangle: return "r"
        case .marker: return "m"
        case .text: return "t"
        case .emoji: return "e"
        case .redact: return "x"
        }
    }
}

enum RedactMode: String, Codable, CaseIterable {
    case pixelate, blur, blackout

    var title: String {
        switch self {
        case .pixelate: return "Mosaic (pixelate)"
        case .blur: return "Blur"
        case .blackout: return "Blackout"
        }
    }
}

struct Stroke {
    var color: CGColor
    var width: CGFloat
}

struct TextAnnotation {
    var origin: CGPoint
    var string: String
    var color: CGColor
    var fontSize: CGFloat
}

/// A single emoji stamped on the canvas; `size` is the font size, `rotation` in degrees.
struct EmojiAnnotation {
    var center: CGPoint
    var string: String
    var size: CGFloat
    var rotation: CGFloat

    /// Unrotated bounding box used for hit-testing.
    var bounds: CGRect {
        CGRect(x: center.x - size * 0.6, y: center.y - size * 0.6, width: size * 1.2, height: size * 1.2)
    }
}

/// One annotation in screen (view) coordinates: points, top-left origin.
struct Annotation: Identifiable {
    enum Kind {
        case pen([CGPoint], Stroke)
        case line(CGPoint, CGPoint, Stroke)
        case arrow(CGPoint, CGPoint, Stroke)
        case rectangle(CGRect, Stroke)
        case marker([CGPoint], Stroke)
        case text(TextAnnotation)
        case emoji(EmojiAnnotation)
        /// rect, mode, block size in points
        case redact(CGRect, RedactMode, CGFloat)
    }

    let id: UUID
    var kind: Kind

    init(_ kind: Kind) {
        id = UUID()
        self.kind = kind
    }

    var isRedaction: Bool {
        if case .redact = kind { return true }
        return false
    }

    var isMarker: Bool {
        if case .marker = kind { return true }
        return false
    }

    /// Whether the annotation is large enough to be worth keeping.
    var isMeaningful: Bool {
        switch kind {
        case .pen(let pts, _), .marker(let pts, _): return !pts.isEmpty
        case .line(let a, let b, _), .arrow(let a, let b, _): return a.distance(to: b) >= 2
        case .rectangle(let r, _), .redact(let r, _, _): return r.width >= 2 && r.height >= 2
        case .text(let t): return !t.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .emoji(let e): return !e.string.isEmpty && e.size > 0
        }
    }

    /// Returns a copy with the stroke width (or font/block size) replaced.
    func withWidth(_ w: CGFloat) -> Annotation {
        var copy = self
        switch kind {
        case .pen(let p, var s): s.width = w; copy.kind = .pen(p, s)
        case .marker(let p, var s): s.width = w; copy.kind = .marker(p, s)
        case .line(let a, let b, var s): s.width = w; copy.kind = .line(a, b, s)
        case .arrow(let a, let b, var s): s.width = w; copy.kind = .arrow(a, b, s)
        case .rectangle(let r, var s): s.width = w; copy.kind = .rectangle(r, s)
        case .text(var t): t.fontSize = w; copy.kind = .text(t)
        case .emoji(var e): e.size = w; copy.kind = .emoji(e)
        case .redact(let r, let m, _): copy.kind = .redact(r, m, w)
        }
        return copy
    }
}
