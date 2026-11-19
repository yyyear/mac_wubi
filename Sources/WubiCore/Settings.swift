import Foundation

/// User configuration, stored as JSON under
/// ~/Library/Application Support/WubiInput/config.json.
/// Missing keys fall back to the defaults below, so the file is optional.
public struct WubiSettings: Codable, Equatable, Sendable {
    /// Commit automatically when a four-key code has exactly one candidate.
    public var autoCommitUnique: Bool = true
    /// Translate ASCII punctuation into Chinese punctuation.
    public var chinesePunctuation: Bool = true
    /// Treat a lone Shift press as a Chinese/English toggle.
    public var shiftTogglesEnglish: Bool = true
    /// Show a small badge at the caret whenever the mode changes.
    public var showModeHUD: Bool = true
    /// How many candidates a page holds. Clamped to 1...10.
    public var pageSize: Int = 5
    /// Learn from what the user commits, re-ranking those words next time.
    public var userLearning: Bool = true
    /// Show a progress hint when the typed code has longer codes behind it.
    public var showCodeHint: Bool = true
    /// Also list candidates whose code merely starts with what was typed.
    public var prefixCandidates: Bool = true
    /// Number of candidate rows kept per lookup.
    public var candidateLimit: Int = 128

    public init() {}

    /// Page size as the UI should use it: 1 to 10, defaulting to 5.
    public var effectivePageSize: Int {
        min(10, max(1, pageSize))
    }

    public static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("WubiInput", isDirectory: true)
    }()

    public static var fileURL: URL {
        supportDirectory.appendingPathComponent("config.json")
    }

    public static func load() -> WubiSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(WubiSettings.self, from: data) else {
            return WubiSettings()
        }
        return decoded
    }

    /// Writes the config back, creating the folder and a default file on first
    /// run so users always have something to edit.
    public func save() {
        let directory = WubiSettings.supportDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: WubiSettings.fileURL, options: .atomic)
    }

    /// Writes a default config file when none exists yet.
    public static func ensureConfigFile() {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        WubiSettings().save()
    }
}
