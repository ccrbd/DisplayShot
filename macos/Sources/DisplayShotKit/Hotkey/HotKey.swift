import AppKit
import Carbon.HIToolbox

/// A global shortcut expressed in Carbon terms (what RegisterEventHotKey needs).
struct HotKey: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var keyLabel: String

    /// ⌘⇧1
    static let `default` = HotKey(keyCode: UInt32(kVK_ANSI_1), carbonModifiers: UInt32(cmdKey | shiftKey), keyLabel: "1")

    var displayString: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyLabel
    }

    var menuModifierFlags: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(controlKey) != 0 { f.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { f.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { f.insert(.shift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { f.insert(.command) }
        return f
    }

    /// Builds a hot key from a key event. Requires ⌘, ⌃ or ⌥ unless the key is a function key.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        let code = UInt32(event.keyCode)
        let isFunctionKey = HotKey.specialKeyLabels[event.keyCode]?.hasPrefix("F") == true
        guard isFunctionKey || (mods & ~UInt32(shiftKey)) != 0 else { return nil }
        guard let label = HotKey.label(for: event) else { return nil }
        self.init(keyCode: code, carbonModifiers: mods, keyLabel: label)
    }

    init(keyCode: UInt32, carbonModifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyLabel = keyLabel
    }

    static func label(for event: NSEvent) -> String? {
        if let special = specialKeyLabels[event.keyCode] { return special }
        guard let chars = event.charactersIgnoringModifiers, let c = chars.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(c) else { return nil }
        return chars.uppercased()
    }

    static let specialKeyLabels: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19",
    ]
}
