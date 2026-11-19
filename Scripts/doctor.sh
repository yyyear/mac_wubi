#!/usr/bin/env bash
# Diagnoses "the input method does not show up".
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUNDLE_ID="com.sifang.wubi"

echo "== 安装位置"
for APP in "/Library/Input Methods/WubiInput.app" "$HOME/Library/Input Methods/WubiInput.app"; do
    [[ -d "$APP" ]] && echo "  有: $APP" || echo "  无: $APP"
done

echo
echo "== 关键 Info.plist 字段（这三项写错系统会静默丢弃整个输入法）"
PLIST=""
for APP in "/Library/Input Methods/WubiInput.app" "$HOME/Library/Input Methods/WubiInput.app"; do
    [[ -f "$APP/Contents/Info.plist" ]] && PLIST="$APP/Contents/Info.plist"
done
if [[ -n "$PLIST" ]]; then
    python3 - "$PLIST" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as handle:
    info = plistlib.load(handle)
modes = info.get("ComponentInputModeDict", {}).get("tsInputModeListKey", {})
repertoire = info.get("tsInputMethodCharacterRepertoireKey", [])
print("  CFBundleIdentifier       =", info.get("CFBundleIdentifier"))
print("  TISInputSourceID         =", info.get("TISInputSourceID"), "(应等于 bundle id)")
print("  InputMethodType          =", info.get("InputMethodType"), "(应为 Keyboard)")
print("  输入模式                  =", list(modes.keys()))
print("  tsInputMethodCharacterRepertoireKey =", repertoire, "(必须是 Hans/Hant 这类脚本标签，不能是 zh_Hans)")
ok = (info.get("TISInputSourceID") == info.get("CFBundleIdentifier")
      and info.get("InputMethodType") == "Keyboard"
      and repertoire == ["Hans"]
      and list(modes.keys()) == [info.get("CFBundleIdentifier")])
print("  => 结构", "正确" if ok else "有问题，请重新运行 ./Scripts/install.sh")
PY
else
    echo "  未安装"
fi

echo
echo "== 系统是否已收录（登录后才有值）"
mkdir -p build
cat > build/tis_probe.swift <<'SWIFT'
import Carbon
import Foundation

func text(_ source: TISInputSource, _ key: CFString) -> String? {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}
func flag(_ source: TISInputSource, _ key: CFString) -> Bool {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return false }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
}
guard let sources = TISCreateInputSourceList(nil, true).takeRetainedValue() as? [TISInputSource] else { exit(1) }
var found = false
for source in sources where (text(source, kTISPropertyInputSourceID) ?? "").contains("oneself") {
    found = true
    let id = text(source, kTISPropertyInputSourceID) ?? "-"
    let type = text(source, kTISPropertyInputSourceType) ?? "-"
    print("  \(id) [\(type)] enabled=\(flag(source, kTISPropertyInputSourceIsEnabled)) selectable=\(flag(source, kTISPropertyInputSourceIsSelectCapable))")
}
if !found {
    print("  未收录 —— 注销并重新登录一次，系统会重新扫描输入法目录")
}
SWIFT
swiftc -O build/tis_probe.swift -o build/tis_probe 2>/dev/null && ./build/tis_probe

echo
echo "== 已启用的输入源"
defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null | grep -A2 oneself || echo "  未写入"

echo
echo "== 运行中的输入法进程"
pgrep -fl "Input Methods/WubiInput.app" || echo "  未运行（正常：切换输入法时会自动启动）"
