#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="DesktopWorkspace"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")"
BUILD_DIR="$ROOT_DIR/build"
BUNDLE_DIR="$BUILD_DIR/$APP_NAME.app"

# 1. Build and sign .app bundle
"$ROOT_DIR/scripts/build_app.sh"

# 2. Build drag-and-drop DMG (with /Applications symlink)
DMG_STAGING="$BUILD_DIR/dmg-staging"
DMG_PATH="$BUILD_DIR/${APP_NAME}-${VERSION}.dmg"
rm -rf "$DMG_STAGING" "$DMG_PATH"
mkdir -p "$DMG_STAGING"
cp -R "$BUNDLE_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "Desktop Workspace" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$DMG_STAGING"

# 3. Build ZIP archive (preserves macOS resource forks & code signatures)
ZIP_PATH="$BUILD_DIR/${APP_NAME}-${VERSION}.zip"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$BUNDLE_DIR" "$ZIP_PATH"

# 4. Build macOS Installer PKG
COMPONENT_PKG="$BUILD_DIR/${APP_NAME}-component.pkg"
PKG_PATH="$BUILD_DIR/${APP_NAME}-${VERSION}.pkg"
rm -f "$COMPONENT_PKG" "$PKG_PATH"

pkgbuild \
    --component "$BUNDLE_DIR" \
    --install-location "/Applications" \
    "$COMPONENT_PKG" >/dev/null

if [[ -z "${INSTALLER_IDENTITY:-}" ]]; then
    INSTALLER_IDENTITY="$(security find-identity -v -p basic 2>/dev/null | awk '/Developer ID Installer/{print $2; exit}')"
fi

if [[ -n "${INSTALLER_IDENTITY:-}" ]]; then
    productbuild \
        --package "$COMPONENT_PKG" \
        --sign "$INSTALLER_IDENTITY" \
        "$PKG_PATH" >/dev/null
else
    productbuild \
        --package "$COMPONENT_PKG" \
        "$PKG_PATH" >/dev/null
fi
rm -f "$COMPONENT_PKG"

# 5. Generate SHA-256 checksums
(
    cd "$BUILD_DIR"
    shasum -a 256 "${APP_NAME}-${VERSION}.dmg" "${APP_NAME}-${VERSION}.zip" "${APP_NAME}-${VERSION}.pkg" > SHA256SUMS.txt
)

echo "Release packages built in $BUILD_DIR:"
ls -lh "$BUILD_DIR/${APP_NAME}-${VERSION}."* "$BUILD_DIR/SHA256SUMS.txt"
