import AppKit
import Carbon
import InputMethodKit

let bundle = Bundle.main
let connectionName = (bundle.infoDictionary?["InputMethodConnectionName"] as? String) ?? "WubiInput_Connection"
let bundleIdentifier = bundle.bundleIdentifier ?? "com.sifang.wubi"

let arguments = CommandLine.arguments

/// Dev helper: --select-self makes this GUI process switch the session to this
/// input method. CLI tools cannot do it (TISSelectInputSource returns -50 from
/// a process without a text input session), which makes local testing awkward.
func selectSelf() {
    guard let sources = TISCreateInputSourceList(nil, true).takeRetainedValue() as? [TISInputSource] else { return }
    for source in sources {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
        let identifier = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
        guard identifier.contains(bundleIdentifier) else { continue }
        guard let typePointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceType) else { continue }
        let type = Unmanaged<CFString>.fromOpaque(typePointer).takeUnretainedValue() as String
        guard type == "TISTypeKeyboardInputMode" else { continue }
        NSLog("WubiInput: enable -> \(TISEnableInputSource(source))")
        NSLog("WubiInput: select -> \(TISSelectInputSource(source))")
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        if let p = TISGetInputSourceProperty(current, kTISPropertyInputSourceID) {
            NSLog("WubiInput: current source is now \(Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue())")
        }
        return
    }
    NSLog("WubiInput: --select-self found no input source for \(bundleIdentifier)")
}

// NOTE: no TISRegisterInputSource here. Every call adds another entry to the
// text input database, which is what produced a dozen duplicate menu rows.
// Registration is a one-shot install concern, handled by Scripts/install.sh.

guard let server = IMKServer(name: connectionName, bundleIdentifier: bundleIdentifier) else {
    NSLog("WubiInput: failed to create IMKServer (\(connectionName) / \(bundleIdentifier))")
    exit(1)
}
NSLog("WubiInput: IMKServer ready on \(connectionName)")

if arguments.contains("--select-self") {
    selectSelf()
    if arguments.contains("--select-only") {
        exit(0)
    }
}

// IMK never forwards modifier-only events, so the Shift shortcut is observed
// with a global monitor. It only reacts to a Shift press that no other key
// interrupts, which keeps Shift+letter working as usual.
NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
    let shiftDown = event.modifierFlags.contains(.shift)
    DispatchQueue.main.async {
        guard let controller = WubiInputController.active else { return }
        if shiftDown {
            controller.beginShiftObservation()
        } else {
            controller.handleBareShiftRelease()
        }
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
application.run()
_ = server