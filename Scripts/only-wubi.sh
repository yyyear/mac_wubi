#!/usr/bin/env bash
# Leaves exactly one input source enabled: 四方五笔.
#
# Useful if you never want to think about input switching again: Shift inside
# the method handles Chinese/English, so the keyboard layout and the built-in
# Wubi both just add noise to the switcher.
#
#   ./Scripts/only-wubi.sh          # keep only 四方五笔
#   ./Scripts/only-wubi.sh --restore  # re-add a US keyboard layout as a fallback
set -euo pipefail

BUNDLE_ID="com.sifang.wubi"
MODE_ID="com.sifang.wubi"

restore=0
[[ "${1:-}" == "--restore" ]] && restore=1

defaults export com.apple.HIToolbox /tmp/wubi-hitoolbox-only.plist

python3 - "$restore" <<'PY'
import plistlib, sys

restore = sys.argv[1] == "1"
path = "/tmp/wubi-hitoolbox-only.plist"
with open(path, "rb") as handle:
    data = plistlib.load(handle)

ours = {
    "Bundle ID": "com.sifang.wubi",
    "Input Mode": "com.sifang.wubi",
    "InputSourceKind": "Input Mode",
}

if restore:
    sources = [
        {"InputSourceKind": "Keyboard Layout", "KeyboardLayout ID": 0, "KeyboardLayout Name": "ABC"},
        ours,
    ]
else:
    sources = [ours]

data["AppleEnabledInputSources"] = sources
data["AppleSelectedInputSources"] = [ours]
with open(path, "wb") as handle:
    plistlib.dump(data, handle)
print("enabled input sources ->", [s.get("Bundle ID") or s.get("KeyboardLayout Name") for s in sources])
PY

defaults import com.apple.HIToolbox /tmp/wubi-hitoolbox-only.plist
rm -f /tmp/wubi-hitoolbox-only.plist

killall TextInputMenuAgent 2>/dev/null || true
sleep 2
echo "完成。菜单栏输入法列表现在只剩 四方五笔。"
echo "要恢复英文键盘：./Scripts/only-wubi.sh --restore"
