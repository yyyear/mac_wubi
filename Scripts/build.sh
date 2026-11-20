#!/usr/bin/env bash
# Builds build/WubiInput.app from the Swift package and ad-hoc signs it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP="build/WubiInput.app"

# Resolve the signing identity once; both bundles use it.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | head -1 | sed 's/.*"\(.*\)"/\1/')}"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG" --product WubiInput
swift build -c "$CONFIG" --product WubiSettingsApp

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/WubiInput" "$APP/Contents/MacOS/WubiInput"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/icon.tiff "$APP/Contents/Resources/icon.tiff"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# InputSourceKit resolves the mode ID through the bundle’s InfoPlist.strings.
for LOCALE in zh-Hans en; do
    LP="$LOCALE.lproj"
    plutil -lint "Resources/$LP/InfoPlist.strings" >/dev/null
    cp -R "Resources/$LP" "$APP/Contents/Resources/"
done

# SwiftPM resource bundles: the dictionary and the HUD artwork.
for RESOURCE_BUNDLE in "$BIN_DIR/WubiInput_WubiCore.bundle" "$BIN_DIR/WubiInput_WubiUI.bundle"; do
    if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
        echo "missing resource bundle at $RESOURCE_BUNDLE" >&2
        exit 1
    fi
    cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
done

# Settings app, nested so the input method menu can launch it directly.
SETTINGS_DIR="$APP/Contents/Applications/WubiSettings.app"
mkdir -p "$SETTINGS_DIR/Contents/MacOS" "$SETTINGS_DIR/Contents/Resources"
cp "$BIN_DIR/WubiSettingsApp" "$SETTINGS_DIR/Contents/MacOS/WubiSettings"
cp Resources/SettingsInfo.plist "$SETTINGS_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$SETTINGS_DIR/Contents/Resources/AppIcon.icns"
strip -x "$SETTINGS_DIR/Contents/MacOS/WubiSettings" 2>/dev/null || true
# Sign the nested app first: the outer signature then seals whatever is inside.
if [[ -n "$IDENTITY" ]]; then
    codesign --force --sign "$IDENTITY" --timestamp=none "$SETTINGS_DIR" >/dev/null 2>&1 || true
else
    codesign --force --sign - --timestamp=none "$SETTINGS_DIR" >/dev/null 2>&1 || true
fi

# Strip debug info for a smaller, faster-to-load binary.
strip -x "$APP/Contents/MacOS/WubiInput" 2>/dev/null || true

plutil -lint "$APP/Contents/Info.plist" >/dev/null
# A restrictive umask must never leak into the bundle: system processes read it.
chmod -R a+rX "$APP"
find "$APP" -name Info.plist -exec chmod 644 {} +

# Prefer a real identity: macOS validates input method signatures through
# amfid, and ad-hoc signatures are rejected on recent releases. Override with
# CODESIGN_IDENTITY=... to pick a specific certificate.
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