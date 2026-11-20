#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="DesktopWorkspace"
BUNDLE_DIR="$ROOT_DIR/build/$APP_NAME.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
    DEVID_HASH="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application/{print $2; exit}')"
    APPLE_CERT_HASH="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development|Apple Distribution/{print $2; exit}')"
    LOCAL_CERT_HASH="$(security find-identity -p codesigning 2>/dev/null | awk '/DesktopWorkspace Local Dev/{print $2; exit}')"
    CODESIGN_IDENTITY="${DEVID_HASH:-${APPLE_CERT_HASH:-${LOCAL_CERT_HASH:--}}}"
fi
ENTITLEMENTS="${ENTITLEMENTS:-$ROOT_DIR/Resources/DesktopWorkspace-Direct.entitlements}"

cd "$ROOT_DIR"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --sign - "$BUNDLE_DIR"
else
    codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" --sign "$CODESIGN_IDENTITY" "$BUNDLE_DIR"
fi

if [[ "${CREATE_DMG:-0}" == "1" ]]; then
    DMG_PATH="$ROOT_DIR/build/$APP_NAME.dmg"
    rm -f "$DMG_PATH"
    hdiutil create -volname "Desktop Workspace" -srcfolder "$BUNDLE_DIR" -ov -format UDZO "$DMG_PATH"
    echo "Packaged $DMG_PATH"
fi

echo "Built $BUNDLE_DIR"
