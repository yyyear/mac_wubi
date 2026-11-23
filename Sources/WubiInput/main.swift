import AppKit
import Carbon
import InputMethodKit
import WubiCore

let bundle = Bundle.main
let connectionName = (bundle.infoDictionary?["InputMethodConnectionName"] as? String) ?? "WubiInput_Connection"
let bundleIdentifier = bundle.bundleIdentifier ?? "com.sifang.wubi"

let arguments = CommandLine.arguments

// Handle one-shot requests before starting the IMK server. Normal launches
// never register, enable, select, or rewrite the user's preferences.
if arguments.contains("--register") || arguments.contains("--ensure-input-mode") {
    exit(WubiRegistration(bundle)?.ensureEnabled() == true ? 0 : 1)
}

if arguments.contains("--select-self") {
    guard let mode = WubiRegistration(bundle)?.mode(all: false),
          TISSelectInputSource(mode) == noErr else { exit(1) }
    if arguments.contains("--select-only") { exit(0) }
}

guard let server = IMKServer(name: connectionName, bundleIdentifier: bundleIdentifier) else {
    NSLog("WubiInput: failed to create IMKServer (\(connectionName) / \(bundleIdentifier))")
    exit(1)
}
NSLog("WubiInput: IMKServer ready on \(connectionName)")

// IMK never forwards modifier-only events, so the Shift shortcut is observed
// with a global monitor. It only reacts to a Shift press that no other key
// interrupts, which keeps Shift+letter working as usual.
NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
    // AppKit dispatches global monitor callbacks on the main thread.
    WubiInputController.active?.observeModifiers(event)
}

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
// The lexicon is shared across IMK clients. Closing a text field is not
// a reason to write; only force the pending batch when the process quits.
_ = NotificationCenter.default.addObserver(
    forName: NSApplication.willTerminateNotification, object: application, queue: nil
) { _ in
    UserLexicon.shared.flush(wait: true)
}
application.run()
_ = server
