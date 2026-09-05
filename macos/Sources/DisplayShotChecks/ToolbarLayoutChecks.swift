import CoreGraphics
@testable import DisplayShotKit

enum ToolbarLayoutChecks {
    static let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    static let palette = CGSize(width: 38, height: 278)
    static let bar = CGSize(width: 98, height: 38)
    static let label = CGSize(width: 70, height: 20)
    static let gap = ToolbarLayout.gap

    static func place(_ sel: CGRect) -> ToolbarLayout.Result {
        ToolbarLayout.place(selection: sel, screen: screen, paletteSize: palette, barSize: bar, labelSize: label)
    }

    static func expectOnScreen(_ r: ToolbarLayout.Result, file: StaticString = #filePath, line: UInt = #line) throws {
        try expect(screen.contains(r.palette), "palette off-screen: \(r.palette)", file: file, line: line)
        try expect(screen.contains(r.actionBar), "bar off-screen: \(r.actionBar)", file: file, line: line)
        try expect(screen.contains(r.label), "label off-screen: \(r.label)", file: file, line: line)
        try expectFalse(r.actionBar.intersects(r.palette), "bar overlaps palette: \(r)", file: file, line: line)
        try expectFalse(r.label.intersects(r.actionBar), "label overlaps bar", file: file, line: line)
        try expectFalse(r.label.intersects(r.palette), "label overlaps palette", file: file, line: line)
    }

    static func run() {
        Checks.suite("ToolbarLayout") {
            Checks.run("default placement: palette right, bar below, label above") {
                let sel = CGRect(x: 200, y: 200, width: 400, height: 300)
                let r = place(sel)
                try expectEqual(r.palette.minX, sel.maxX + gap)
                try expectEqual(r.palette.minY, sel.minY)
                try expectEqual(r.actionBar.minY, sel.maxY + gap)
                try expectEqual(r.actionBar.maxX, sel.maxX)
                try expectEqual(r.label.maxY, sel.minY - gap / 2)
                try expectEqual(r.label.minX, sel.minX)
                try expectOnScreen(r)
            }
            Checks.run("flips near the right and bottom edges") {
                let sel = CGRect(x: 1000, y: 500, width: 430, height: 390)
                let r = place(sel)
                try expectEqual(r.palette.maxX, sel.minX - gap, "palette should flip to the left")
                try expectEqual(r.actionBar.maxY, sel.minY - gap, "bar should flip above")
                try expectOnScreen(r)
            }
            Checks.run("falls inside the selection when there is no room anywhere") {
                let r = place(screen)
                try expectEqual(r.palette.maxX, screen.maxX - gap)
                try expectEqual(r.actionBar.maxY, screen.maxY - gap)
                try expectOnScreen(r)
            }
            Checks.run("label moves inside at the top edge") {
                let sel = CGRect(x: 100, y: 5, width: 300, height: 200)
                let r = place(sel)
                try expect(sel.contains(r.label))
                try expectOnScreen(r)
            }
            Checks.run("tiny selections in the corners still fit") {
                try expectOnScreen(place(CGRect(x: 1420, y: 880, width: 15, height: 15)))
                try expectOnScreen(place(CGRect(x: 0, y: 0, width: 15, height: 15)))
                try expectOnScreen(place(CGRect(x: 0, y: 880, width: 15, height: 15)))
                try expectOnScreen(place(CGRect(x: 1420, y: 0, width: 15, height: 15)))
            }
        }
    }
}
