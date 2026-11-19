import Carbon
import Foundation

/// Registers an input method bundle with the Text Input Source system and tries
/// to enable it. macOS still owns the final toggle, but this saves the manual
/// hunt through System Settings in the common case.

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write("usage: enable-input-source <bundle>\n".data(using: .utf8)!)
    exit(2)
}
let url = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
let status = TISRegisterInputSource(url)
print("TISRegisterInputSource -> \(status)")

guard let sources = TISCreateInputSourceList(nil, true).takeRetainedValue() as? [TISInputSource] else {
    exit(1)
}

let wanted = "com.sifang.wubi"
var matched: TISInputSource?
for source in sources {
    func property(_ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
    let identifier = property(kTISPropertyInputSourceID) ?? ""
    let bundleID = property(kTISPropertyBundleID) ?? ""
    if identifier.contains(wanted) || bundleID == wanted {
        matched = source
        print("found: \(identifier)")
        break
    }
}

guard let source = matched else {
    print("input source not visible yet; add it from System Settings → Keyboard → Input Sources")
    exit(0)
}

let enabled = TISEnableInputSource(source)
print("TISEnableInputSource -> \(enabled)")
let selected = TISSelectInputSource(source)
print("TISSelectInputSource -> \(selected)")
