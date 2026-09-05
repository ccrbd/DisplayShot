import AppKit

enum Palette {
    /// Preset annotation colours; keys 1–9 select the first nine.
    static let colors: [NSColor] = [
        NSColor(hex: 0xFF3B30), // red
        NSColor(hex: 0xFF9500), // orange
        NSColor(hex: 0xFFD60A), // yellow
        NSColor(hex: 0x34C759), // green
        NSColor(hex: 0x0A84FF), // blue
        NSColor(hex: 0xBF5AF2), // purple
        NSColor(hex: 0xFF2D55), // pink
        NSColor(hex: 0x000000), // black
        NSColor(hex: 0xFFFFFF), // white
        NSColor(hex: 0x8E8E93), // gray
    ]

    static let dim = NSColor(white: 0, alpha: 0.45)
    static let chrome = NSColor(white: 0.10, alpha: 0.94)
    static let chromeBorder = NSColor(white: 1, alpha: 0.12)
    static let highlight = NSColor(white: 1, alpha: 0.18)
    static let accent = NSColor(srgbRed: 1.0, green: 0.45, blue: 0.25, alpha: 1)
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
