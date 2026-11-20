import AppKit
import SwiftUI

/// Standalone settings app. It runs inside the input method bundle so the input
/// method menu can open it, and it talks to the method through config.json.
@main
struct WubiSettingsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = SettingsStore()

    var body: some Scene {
        WindowGroup("四方五笔") {
            SettingsView()
                .environmentObject(store)
        }
        .defaultSize(width: 800, height: 560)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于四方五笔") { NSApp.orderFrontStandardAboutPanel(nil) }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
