#!/usr/bin/env bash
# Builds and installs the input method.
#
#   ./Scripts/install.sh            # ~/Library/Input Methods (no sudo)
#   ./Scripts/install.sh --system   # /Library/Input Methods (asks for sudo)
#   ./Scripts/install.sh --release  # build configuration (default: release)
#
# Note: macOS builds the list of available input methods when a user logs in.
# A freshly installed method shows up after the next login (or reboot).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="release"
SCOPE="user"
for arg in "$@"; do
    case "$arg" in
        --system) SCOPE="system" ;;
        debug|release) CONFIG="$arg" ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

"$ROOT/Scripts/build.sh" "$CONFIG"

if [[ "$SCOPE" == "system" ]]; then
    TARGET="/Library/Input Methods"
    echo "==> installing to $TARGET (sudo required)"
    sudo mkdir -p "$TARGET"
    sudo rm -rf "$TARGET/WubiInput.app"
    sudo cp -R "$ROOT/build/WubiInput.app" "$TARGET/WubiInput.app"
    # Input methods are read by system processes: normalise ownership/mode.
    sudo chown -R root:wheel "$TARGET/WubiInput.app"
    sudo chmod -R 755 "$TARGET/WubiInput.app"
    INSTALLED="$TARGET/WubiInput.app"
else
    TARGET="$HOME/Library/Input Methods"
    mkdir -p "$TARGET"
    echo "==> installing to $TARGET"
    rm -rf "$TARGET/WubiInput.app"
    cp -R "$ROOT/build/WubiInput.app" "$TARGET/WubiInput.app"
    chmod -R u+rwX,go+rX "$TARGET/WubiInput.app"
    INSTALLED="$TARGET/WubiInput.app"
fi

echo "==> stopping any running instance"
killall WubiInput 2>/dev/null || true
sleep 0.5

echo "==> clearing old input source entries"
# Registering twice creates duplicate menu rows, so purge every trace of this
# bundle id first, then register exactly once.
python3 - <<'PYEOF' || true
import os, plistlib
path = os.path.expanduser("~/Library/Preferences/com.apple.HIToolbox.plist")
if os.path.exists(path):
    with open(path, "rb") as handle:
        data = plistlib.load(handle)
    for key in ("AppleEnabledInputSources", "AppleSelectedInputSources", "AppleInputSourceHistory"):
        if key in data:
            data[key] = [s for s in data[key] if s.get("Bundle ID") != "com.sifang.wubi"]
    with open(path, "wb") as handle:
        plistlib.dump(data, handle)
PYEOF
killall WubiInput 2>/dev/null || true
killall TextInputMenuAgent imklaunchagent 2>/dev/null || true
sleep 2

echo "==> registering input source"
swiftc -O Scripts/enable_input_source.swift -o build/enable-input-source 2>/dev/null || true
[[ -x build/enable-input-source ]] && ./build/enable-input-source "$INSTALLED" || true

echo "==> adding to the enabled input sources"
# The entry must use InputSourceKind "Input Mode" and the mode id declared in
# Info.plist; anything else is dropped by the text input system on read.
defaults export com.apple.HIToolbox /tmp/wubi-hitoolbox.plist 2>/dev/null || true
python3 - "/tmp/wubi-hitoolbox.plist" <<'PY' || true
import plistlib, sys
path = sys.argv[1]
try:
    with open(path, "rb") as handle:
        data = plistlib.load(handle)
except Exception:
    data = {}
sources = [s for s in data.get("AppleEnabledInputSources", [])
           if s.get("Bundle ID") != "com.sifang.wubi"]
sources.append({
    "Bundle ID": "com.sifang.wubi",
    "Input Mode": "com.sifang.wubi",
    "InputSourceKind": "Input Mode",
})
data["AppleEnabledInputSources"] = sources
with open(path, "wb") as handle:
    plistlib.dump(data, handle)
print("enabled input sources updated")
PY
defaults import com.apple.HIToolbox /tmp/wubi-hitoolbox.plist 2>/dev/null || true
rm -f /tmp/wubi-hitoolbox.plist

killall TextInputMenuAgent 2>/dev/null || true
killall imklaunchagent 2>/dev/null || true

echo
echo "安装完成：$INSTALLED"
echo
cat <<'TIPS'
系统在登录时构建输入法列表，因此新装的输入法需要：

  · 注销并重新登录（或重启）一次，然后
    系统设置 → 键盘 → 文字输入「输入法」→ 编辑… → 「+」→ 简体中文 → 五笔

验证是否已生效：

  ./Scripts/doctor.sh
TIPS