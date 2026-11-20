#!/usr/bin/env bash
# Builds a distributable installer: build/四方五笔-<version>.pkg
#
#   ./Scripts/build_pkg.sh            # unsigned pkg (users must right-click Open)
#   ./Scripts/build_pkg.sh --sign     # sign with Developer ID Installer if present
#
# Signing and notarisation need an Apple Developer Program membership:
#   Developer ID Application  -> signs the app
#   Developer ID Installer    -> signs the pkg
# Without them the pkg still installs, but Gatekeeper warns on first launch.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SIGN=0
[[ "${1:-}" == "--sign" ]] && SIGN=1

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
APP="build/WubiInput.app"
PKGROOT="build/pkgroot"
PKGDIR="build/pkg"
OUT="build/四方五笔-${VERSION}.pkg"

echo "==> building app (${VERSION})"
if [[ $SIGN -eq 1 ]]; then
    DEV_ID="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application[^"]*\)"/\1/p' | head -1)"
    [[ -n "$DEV_ID" ]] && CODESIGN_IDENTITY="$DEV_ID" ./Scripts/build.sh release || ./Scripts/build.sh release
else
    ./Scripts/build.sh release
fi

echo "==> staging payload"
rm -rf "$PKGROOT" "$PKGDIR"
mkdir -p "$PKGROOT/Library/Input Methods" "$PKGDIR"
# ditto keeps the bundle's signatures and extended attributes intact.
/usr/bin/ditto "$APP" "$PKGROOT/Library/Input Methods/WubiInput.app"

# The build tree may carry restrictive modes (umask 077). System processes must
# be able to READ Info.plist, otherwise the method registers as "WithoutModes"
# and never appears in the input menu.
chmod -R a+rX "$PKGROOT/Library/Input Methods/WubiInput.app"
find "$PKGROOT/Library/Input Methods/WubiInput.app" -name Info.plist -exec chmod 644 {} +

echo "==> building component pkg"
chmod +x Scripts/pkg/scripts/postinstall
# Never let Installer relocate the input method into a same-ID build copy.
/usr/bin/pkgbuild --analyze --root "$PKGROOT" "$PKGDIR/components.plist"
python3 - "$PKGDIR/components.plist" <<'PY'
import plistlib, sys
path = sys.argv[1]
with open(path, "rb") as f:
    items = plistlib.load(f)
def pin(items):
    for item in items:
        item["BundleIsRelocatable"] = False
        pin(item.get("ChildBundles", []))
pin(items)
with open(path, "wb") as f:
    plistlib.dump(items, f)
PY
/usr/bin/pkgbuild --root "$PKGROOT" --component-plist "$PKGDIR/components.plist" \
    --identifier "com.sifang.wubi.pkg" \
    --version "$VERSION" \
    --install-location "/" \
    --scripts Scripts/pkg/scripts \
    --ownership recommended \
    "$PKGDIR/wubi.pkg"

echo "==> building distribution pkg"
sed "s/__VERSION__/$VERSION/" Scripts/pkg/distribution.xml > "$PKGDIR/distribution.xml"
/usr/bin/productbuild --distribution "$PKGDIR/distribution.xml" \
    --package-path "$PKGDIR" \
    --resources Scripts/pkg \
    "$OUT"

if [[ $SIGN -eq 1 ]]; then
    INSTALLER_ID="$(security find-identity -v | sed -n 's/.*"\(Developer ID Installer[^"]*\)"/\1/p' | head -1)"
    if [[ -n "$INSTALLER_ID" ]]; then
        echo "==> signing pkg with: $INSTALLER_ID"
        /usr/bin/productsign --sign "$INSTALLER_ID" "$OUT" "$OUT.signed"
        mv "$OUT.signed" "$OUT"
    else
        echo "!! no Developer ID Installer certificate, pkg stays unsigned"
    fi
fi

echo
echo "==> done: $OUT  ($(du -sh "$OUT" | cut -f1))"
echo "    verify: pkgutil --check-signature \"$OUT\""
echo "    install: open \"$OUT\"  (or: sudo installer -pkg \"$OUT\" -target /)"