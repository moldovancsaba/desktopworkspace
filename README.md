# Desktop Workspace

A lightweight, native macOS SwiftUI app for organizing apps into saved desktop layouts and launching them into a fresh Desktop Space with one click.

## Features

- **Preset Layouts**:
  - **3 Columns** (3 equal vertical columns)
  - **2 Top + 1 Bottom** (2 windows on top, 1 wide at the bottom)
  - **1 Top + 2 Bottom** (1 wide on top, 2 at the bottom)
  - **2 Columns**, **1 Left + 2 Right**, **2 Left + 1 Right**, **2×2 Grid**, **3 Rows**, and **Full Screen**
- **Visual Slot Assignment**: Click any slot in the layout preview to pick an installed macOS app (with search and `.app` browser).
- **Saved Workspaces**: Name, duplicate, delete, and persist workspaces locally in `~/Library/Application Support/DesktopWorkspace/workspaces.json`.
- **New Desktop Space & Tiling**: Optionally creates and switches to a new Mission Control Desktop, opens each assigned app (or a new window if already running), and tiles windows to fill the usable screen area with configurable gaps (`0–16 px`).
- **Menu Bar Quick Launch**: Launch any saved workspace in one click from the macOS menu bar (`rectangle.3.group` icon).

## Requirements

- macOS 14.0 or later
- Swift 5.9+ (or Xcode 15+ for archiving/App Store distribution)
- **Accessibility Permission** (`System Settings → Privacy & Security → Accessibility`) so the app can position and resize other applications' windows.

## Building & Running Locally

```bash
# Build DesktopWorkspace.app with icon and Info.plist
./scripts/build_app.sh

# Launch the app
open build/DesktopWorkspace.app
```

To also package a `.dmg` installer:

```bash
CREATE_DMG=1 ./scripts/build_app.sh
```

To regenerate the app icon from source:

```bash
swift scripts/generate_icon.swift Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png
```

## Project Structure

- `Package.swift` — Swift Package manifest
- `project.yml` — XcodeGen specification for generating `DesktopWorkspace.xcodeproj`
- `Sources/DesktopWorkspace/` — SwiftUI app, models, store, and Accessibility window manager
- `Resources/Info.plist` — macOS bundle metadata
- `Resources/AppIcon.icns` & `Resources/Assets.xcassets/` — App icon assets
- `Resources/DesktopWorkspace-AppStore.entitlements` — Sandboxed entitlements for App Store builds
- `Resources/DesktopWorkspace-Direct.entitlements` — Hardened-runtime entitlements for Developer ID distribution
- `scripts/build_app.sh` — Release build, bundle packaging, signing, and optional `.dmg` creation
- `PRIVACY.md` — Privacy policy for App Store Connect
- `docs/APP_STORE_CHECKLIST.md` — Publishing guide for Mac App Store & Developer ID notarization
