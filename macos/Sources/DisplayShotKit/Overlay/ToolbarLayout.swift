import CoreGraphics

/// Pure placement math for the tool palette, action bar and dimension label around a selection.
/// Coordinates are points with a top-left origin. Nothing is ever placed outside `screen`.
enum ToolbarLayout {
    static let gap: CGFloat = 8

    struct Result: Equatable {
        var palette: CGRect
        var actionBar: CGRect
        var label: CGRect
    }

    static func place(selection: CGRect, screen: CGRect, paletteSize: CGSize, barSize: CGSize, labelSize: CGSize) -> Result {
        // Palette: right of the selection → left of it → inside its top-right corner.
        let py = clamp(selection.minY, screen.minY, max(screen.minY, screen.maxY - paletteSize.height))
        var palette: CGRect
        if selection.maxX + gap + paletteSize.width <= screen.maxX {
            palette = CGRect(origin: CGPoint(x: selection.maxX + gap, y: py), size: paletteSize)
        } else if selection.minX - gap - paletteSize.width >= screen.minX {
            palette = CGRect(origin: CGPoint(x: selection.minX - gap - paletteSize.width, y: py), size: paletteSize)
        } else {
            palette = CGRect(origin: CGPoint(x: selection.maxX - gap - paletteSize.width, y: selection.minY + gap), size: paletteSize)
        }
        palette = palette.fitted(in: screen)

        // Action bar: below the selection → above it → beside the palette → inside the selection.
        let bx = clamp(selection.maxX - barSize.width, screen.minX, max(screen.minX, screen.maxX - barSize.width))
        let w = barSize.width, h = barSize.height
        let barCandidates = [
            CGRect(x: bx, y: selection.maxY + gap),                                   // below, right-aligned
            CGRect(x: bx, y: selection.minY - gap - h),                               // above, right-aligned
            CGRect(x: palette.minX - gap - w, y: selection.maxY + gap),               // below, left of palette
            CGRect(x: palette.minX - gap - w, y: selection.minY - gap - h),           // above, left of palette
            CGRect(x: palette.maxX + gap, y: selection.maxY + gap),                   // below, right of palette
            CGRect(x: palette.maxX + gap, y: selection.minY - gap - h),               // above, right of palette
            CGRect(x: selection.maxX - gap - w, y: selection.maxY - gap - h),         // inside bottom-right
            CGRect(x: selection.minX + gap, y: selection.maxY - gap - h),             // inside bottom-left
            CGRect(x: palette.maxX + gap, y: palette.maxY - h),                       // next to the palette's foot
            CGRect(x: palette.minX - gap - w, y: palette.maxY - h),
        ].map { CGRect(origin: $0.origin, size: barSize) }
        var bar = barCandidates[6].fitted(in: screen)
        if let free = barCandidates.first(where: { screen.contains($0) && !$0.intersects(palette) }) {
            bar = free
        } else if let fitted = barCandidates.map({ $0.fitted(in: screen) }).first(where: { !$0.intersects(palette) }) {
            bar = fitted
        }

        // Dimension label: first candidate that is on-screen and does not overlap the toolbars.
        let g = gap / 2
        let candidates = [
            CGRect(x: selection.minX, y: selection.minY - g - labelSize.height),                 // above
            CGRect(x: selection.minX + 4, y: selection.minY + 4),                                // inside top-left
            CGRect(x: selection.minX, y: selection.maxY + g),                                    // below
            CGRect(x: selection.minX - g - labelSize.width, y: selection.minY),                  // left
            CGRect(x: selection.maxX + g, y: selection.minY),                                    // right
            CGRect(x: palette.minX - g - labelSize.width, y: selection.minY),                    // beside palette
            CGRect(x: palette.maxX + g, y: selection.minY),
            CGRect(x: bar.minX, y: bar.maxY + g),                                                // beside bar
            CGRect(x: bar.minX, y: bar.minY - g - labelSize.height),
        ].map { CGRect(origin: $0.origin, size: labelSize) }
        var label = candidates[1].fitted(in: screen)
        for c in candidates where screen.contains(c) && !c.intersects(bar) && !c.intersects(palette) {
            label = c
            break
        }

        return Result(palette: palette, actionBar: bar, label: label)
    }
}

private extension CGRect {
    /// Zero-size rect at a point; `ToolbarLayout` gives it a size afterwards.
    init(x: CGFloat, y: CGFloat) { self.init(x: x, y: y, width: 0, height: 0) }
}
