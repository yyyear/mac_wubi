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

# macOS rescans installed input methods at login. Do not edit keyboard
# preferences or restart preference daemons to remove stale menu entries.
echo "注销后系统将刷新输入源列表。"

echo "==> keeping user data at ~/Library/Application Support/WubiInput (delete manually if unwanted)"
echo "卸载完成"
