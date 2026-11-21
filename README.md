# Desktop Workspace

A lightweight, native macOS SwiftUI app by **Moldovan Csaba Kft** ([moldovancsaba.com](https://moldovancsaba.com)) for organizing apps into saved desktop layouts, launching them into a fresh Desktop Space, and managing them as a unified workspace.

## Features

- **9 Built-in Tiling Layouts:** 3 Columns, 2 Top + 1 Bottom, 1 Top + 2 Bottom, 2 Columns, 1 Left + 2 Right, 2 Left + 1 Right, 2×2 Grid, 3 Rows, and Full Screen.
- **Installed Apps & Open Windows Picker:** Assign any installed macOS app, or pick specific currently open windows by title (e.g., two browser windows side-by-side) with duplicate-window prevention.
- **Two Workspace Modes:**
  - **Full Screen Tiled:** Aligns apps edge-to-edge across your chosen display.
  - **Framed Group:** Groups the workspace inside a resizable container frame you can move/resize as a set, maximize/restore, or dock to the sidebar.
- **Active Workspace Controls:** Live `Active` / `Launched` status, **Open Workspace** (brings all windows to front), **Re-Align** (`⌘⇧R`, also reopens closed apps), **Close** (stops and closes member windows), **Auto-Lock Alignment**, and **Drag & Drop Slot Swapping**.
- **Live Property Updates & Persistence:** Editing gap, layout, slots, display, or Auto-Lock on an active workspace updates windows immediately; workspaces and frame geometry persist in `~/Library/Application Support/DesktopWorkspace/workspaces.json`.
- **Two-Lane Updates:** Direct/GitHub builds check GitHub Releases automatically (`UpdateManager`) and install notarized `.zip` updates in place; Mac App Store builds update via the Mac App Store.

## Requirements

- macOS 14.0 or later
- **Accessibility Permission** (`System Settings → Privacy & Security → Accessibility`) to position/resize windows and create Mission Control Desktops.

## Building & Publishing

```bash
# Build & sign DesktopWorkspace.app
./scripts/build_app.sh

# Build .app, .dmg, .pkg, .zip, and SHA256SUMS.txt
./scripts/package_all.sh
```

See [docs/RELEASE_AND_PUBLISHING_GUIDE.md](docs/RELEASE_AND_PUBLISHING_GUIDE.md) for the full release, notarization, and App Store Connect checklist.

## License & Legal

Released under the [MIT License](LICENSE). See [PRIVACY.md](PRIVACY.md) and [LEGAL.md](LEGAL.md).
