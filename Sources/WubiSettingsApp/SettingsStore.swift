import Foundation
import SwiftUI
import WubiCore

/// Observable bridge over WubiSettings: every edit is written straight back to
/// config.json and broadcast so a running input method picks it up at once.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: WubiSettings {
        didSet { persist() }
    }

    /// Guards the initial load from triggering a write.
    private var isLoaded = false

    init() {
        settings = WubiSettings.load()
        isLoaded = true
    }

    private func persist() {
        guard isLoaded else { return }
        settings.save()
    }

    func resetToDefaults() {
        var fresh = WubiSettings()
        fresh.pageSize = settings.pageSize
        settings = fresh
    }

    var configPath: String { WubiSettings.fileURL.path }
}
