#!/usr/bin/env bash
# Removes the input method and its state.
set -euo pipefail

echo "==> stopping the input method"
killall WubiInput 2>/dev/null || true

for TARGET in "$HOME/Library/Input Methods/WubiInput.app" "/Library/Input Methods/WubiInput.app"; do
    if [[ -d "$TARGET" ]]; then
        echo "==> removing $TARGET"
        if [[ "$TARGET" == /Library/* ]]; then
            sudo rm -rf "$TARGET"
        else
            rm -rf "$TARGET"
        fi
    fi
done

echo "==> removing the enabled-input-source entry"
python3 - <<'PY' || true
import os, plistlib, subprocess
path = os.path.expanduser("~/Library/Preferences/com.apple.HIToolbox.plist")
if not os.path.exists(path):
    raise SystemExit(0)
with open(path, "rb") as handle:
    data = plistlib.load(handle)
sources = [s for s in data.get("AppleEnabledInputSources", [])
           if s.get("Bundle ID") != "com.sifang.wubi"]
data["AppleEnabledInputSources"] = sources
with open(path, "wb") as handle:
    plistlib.dump(data, handle)
subprocess.run(["killall", "cfprefsd"], capture_output=True)
print("input source entry removed")
PY

killall TextInputMenuAgent 2>/dev/null || true

echo "==> keeping user data at ~/Library/Application Support/WubiInput (delete manually if unwanted)"
echo "卸载完成"
