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

# Do not expose two installed bundles with identical input-source IDs.
other="/Library/Input Methods/WubiInput.app"
[[ "$SCOPE" != system ]] || other="$HOME/Library/Input Methods/WubiInput.app"
if [[ -d "$other" ]]; then
    echo "另一安装位置已有四方五笔：$other。请更新原位置，或先移除旧副本。" >&2
    exit 1
fi

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

echo "==> enabling 四方五笔 (leaving other input sources unchanged)"
if ! "$INSTALLED/Contents/MacOS/WubiInput" --ensure-input-mode; then
    echo "已安装，但未确认启用；请注销后在系统设置 → 键盘 → 输入法中添加四方五笔。" >&2
    exit 1
fi
echo "安装并启用完成：$INSTALLED"
