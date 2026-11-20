import Carbon
import Foundation

/// Only explicit install/repair requests may change the enabled source list.
/// Use the enabled-only TIS list: a default mode can report IsEnabled even
/// when its parent is disabled and the mode is absent from the switcher.
struct WubiRegistration {
    let bundle: Bundle
    let modeID: String
    let bundleID: String

    init?(_ bundle: Bundle) {
        guard let id = bundle.bundleIdentifier, id == "com.sifang.wubi",
              let modes = bundle.object(forInfoDictionaryKey: "ComponentInputModeDict") as? [String: Any],
              let visible = modes["tsVisibleInputModeOrderedArrayKey"] as? [String],
              visible.count == 1 else { return nil }
        self.bundle = bundle
        bundleID = id
        modeID = visible[0]
    }

    private func sources(all: Bool, type: CFString? = nil, id: String? = nil) -> [TISInputSource] {
        var filter = [kTISPropertyBundleID as String: bundleID]
        if let type { filter[kTISPropertyInputSourceType as String] = type as String }
        if let id { filter[kTISPropertyInputSourceID as String] = id }
        return TISCreateInputSourceList(filter as CFDictionary, all).takeRetainedValue() as! [TISInputSource]
    }

    func mode(all: Bool) -> TISInputSource? {
        sources(all: all, type: kTISTypeKeyboardInputMode, id: modeID).first
    }

    func ensureEnabled() -> Bool {
        if mode(all: false) != nil { return true }
        if sources(all: true).isEmpty {
            let status = TISRegisterInputSource(bundle.bundleURL as CFURL)
            guard status == noErr else { NSLog("WubiInput: registration failed (%d)", status); return false }
        }
        guard let target = mode(all: true) else {
            NSLog("WubiInput: mode not visible; log out and add 四方五笔 in Keyboard settings")
            return false
        }
        // Enabling a method also enables its default mode. Do not issue a
        // second enable for the child; enable only the mode if the method is
        // already active. An explicit retry may enable a non-default mode.
        let parentType = kTISTypeKeyboardInputMethodModeEnabled!
        let source: TISInputSource
        if sources(all: false, type: parentType).isEmpty {
            guard let parent = sources(all: true, type: parentType).first else { return false }
            source = parent
        } else {
            source = target
        }
        let status = TISEnableInputSource(source)
        guard status == noErr else { NSLog("WubiInput: enable failed (%d)", status); return false }
        // Allow preferences and the session's TIS cache to catch up without
        // repeating registration or enable operations.
        for _ in 0..<10 {
            if mode(all: false) != nil { return true }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        }
        NSLog("WubiInput: mode not yet enabled; check Keyboard settings after login")
        return false
    }
}
