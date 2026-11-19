#!/usr/bin/env bash
# Builds build/WubiInput.app from the Swift package and ad-hoc signs it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP="build/WubiInput.app"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG" --product WubiInput

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/WubiInput" "$APP/Contents/MacOS/WubiInput"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/icon.tiff "$APP/Contents/Resources/icon.tiff"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Localized names: without these the switcher HUD shows the bundle identifier.
for LP in Resources/*.lproj; do
    [[ -d "$LP" ]] || continue
    cp -R "$LP" "$APP/Contents/Resources/"
done

# SwiftPM resource bundles: the dictionary and the HUD artwork.
for RESOURCE_BUNDLE in "$BIN_DIR/WubiInput_WubiCore.bundle" "$BIN_DIR/WubiInput_WubiUI.bundle"; do
    if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
        echo "missing resource bundle at $RESOURCE_BUNDLE" >&2
        exit 1
    fi
    cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
done

# Strip debug info for a smaller, faster-to-load binary.
strip -x "$APP/Contents/MacOS/WubiInput" 2>/dev/null || true

plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Prefer a real identity: macOS validates input method signatures through
# amfid, and ad-hoc signatures are rejected on recent releases. Override with
# CODESIGN_IDENTITY=... to pick a specific certificate.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | head -1 | sed 's/.*"\(.*\)"/\1/')}"
if [[ -z "$IDENTITY" ]]; then
    echo "==> signing (ad-hoc; macOS may refuse to load this bundle)"
    codesign --force --sign - --timestamp=none "$APP" >/dev/null
else
    echo "==> signing with: $IDENTITY"
    codesign --force --sign "$IDENTITY" --timestamp=none "$APP" >/dev/null
fi
codesign --verify --deep --strict "$APP"

SIZE="$(du -sh "$APP" | cut -f1)"
echo "==> done: $APP ($SIZE)"