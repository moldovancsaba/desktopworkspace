# Changelog

## [1.2.1] - 2026-11-20
### Changed
- **Open Workspace (when already launched):** Primary button, context menu, and menu bar change from `Launch` to `Open` when a workspace is active and bring all its windows to the front.
- **Close Active Workspace:** Added a labeled `Close` button (`xmark.circle`) and menu bar `Close <Workspace>` action to stop tracking, close the frame, and close the workspace's member windows.

## [1.2.0] - 2026-11-20
### Added
- **Launched / Active Workspace Status:** Sidebar and workspace header now display a green `Active` / `Launched` indicator and a Stop Tracking button.
- **Live Property Updates for Launched Workspaces:** Editing gap, layout preset, slot apps, target display, or Auto-Lock Alignment on an already-launched workspace updates the live windows immediately.
- **Drag & Drop Slot Swapping:** Drag and drop any slot card onto another slot in the layout canvas to swap/move apps (and live-swap their windows if the workspace is launched).

## [1.1.1] - 2026-11-20
### Fixed
- Prevent assigning the exact same open window (`preferredWindowNumber`) to multiple slots in the same workspace; already-assigned open windows now show an `In <Slot>` badge and are disabled.

## [1.1.0] - 2026-11-20
### Added
- **Open Windows Picker:** Assign currently open app windows (including multiple browser windows by title) directly to layout slots.
- **Automatic Self-Updater (Direct / GitHub Lane):** Checks GitHub Releases on launch and installs signed/notarized `.zip` updates cleanly in place (automatically disabled in Mac App Store sandboxed builds).

## [1.0.0] - 2026-11-18
### Added
- Initial open-source release of **Desktop Workspace**.
- 9 built-in tiling layouts: 3 Columns, 2 Top + 1 Bottom, 1 Top + 2 Bottom, 2 Columns, 1 Left + 2 Right, 2 Left + 1 Right, 2×2 Grid, 3 Rows, and Full Screen.
- Visual slot-to-app assignment with installed app discovery and `.app` browser.
- Persistent workspace storage in `~/Library/Application Support/DesktopWorkspace/workspaces.json`.
- Optional automatic new Desktop Space creation via Mission Control and multi-window support for already-running apps.
- Menu bar quick-launch menu (`rectangle.3.group`).
- Custom macOS app icon (`AppIcon.icns` & `Assets.xcassets`) and release packaging (`.app`, `.dmg`, `.zip`, `.pkg`).
