import AppKit

/// UserDefaults-backed settings.
final class Preferences {
    static let shared = Preferences()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let hotKey = "hotKey"
        static let saveDirectory = "saveDirectory"
        static let saveWithoutAsking = "saveWithoutAsking"
        static let playSound = "playSound"
        static let toolWidths = "toolWidths"
        static let lastColorIndex = "lastColorIndex"
    }

    var hotKey: HotKey {
        get {
            guard let data = defaults.data(forKey: Key.hotKey),
                  let hk = try? JSONDecoder().decode(HotKey.self, from: data) else { return .default }
            return hk
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.hotKey) }
    }

    var saveDirectory: URL {
        get {
            if let path = defaults.string(forKey: Key.saveDirectory) {
                return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            }
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
        }
        set { defaults.set(newValue.path, forKey: Key.saveDirectory) }
    }

    var saveWithoutAsking: Bool {
        get { defaults.bool(forKey: Key.saveWithoutAsking) }
        set { defaults.set(newValue, forKey: Key.saveWithoutAsking) }
    }

    var playSound: Bool {
        get { defaults.object(forKey: Key.playSound) == nil ? true : defaults.bool(forKey: Key.playSound) }
        set { defaults.set(newValue, forKey: Key.playSound) }
    }

    var toolWidths: [ToolKind: CGFloat] {
        get {
            var out: [ToolKind: CGFloat] = [:]
            for tool in ToolKind.allCases { out[tool] = tool.defaultWidth }
            if let raw = defaults.dictionary(forKey: Key.toolWidths) as? [String: Double] {
                for (k, v) in raw { if let tool = ToolKind(rawValue: k) { out[tool] = CGFloat(v) } }
            }
            return out
        }
        set {
            var raw: [String: Double] = [:]
            for (k, v) in newValue { raw[k.rawValue] = Double(v) }
            defaults.set(raw, forKey: Key.toolWidths)
        }
    }

    var lastColorIndex: Int {
        get { defaults.object(forKey: Key.lastColorIndex) == nil ? 0 : defaults.integer(forKey: Key.lastColorIndex) }
        set { defaults.set(newValue, forKey: Key.lastColorIndex) }
    }
}
