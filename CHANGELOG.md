# Changelog

## [1.4.1] - 2026-11-22
### Fixed
- **Active Slot Swap Preservation:** Drag-and-drop slot swaps on an active workspace now preserve `trackedSlotWindows` and `overflowWarnings`, and cleanly realign swapped windows instead of reopening them.
- **Framed Group Header Drag & Dock:** Replaced SwiftUI `DragGesture` with an AppKit `WindowDragHandle` (`mouseDown` -> `performDrag`), prevented docked sidebar pill index collisions with column wrapping, cleared `window = nil` on close, and passed `containerBounds` during live `syncWindows`.
- **UI & Layout Polish:** Fixed Options Grid Row 2 Col 2 overflow at `minWidth: 880` by moving the `Gap` slider to its own row, added a `"Custom"` captured layout indicator with replacement confirmation, added disconnected display fallback in the Display picker, and aligned `Re-Align` shortcut tooltips (`⌘⇧R` in-app, `⌥⌘R` global).
- **Menu Bar & Localization:** Surfaced `statusMessage` warnings for `MenuBarExtra` capture failures (`.needsAccessibility`, `.noOpenWindows`) and added locale-independent fallbacks for Mission Control desktop discovery.

## [1.4.0] - 2026-11-22
### Fixed
- **Framed Group Click-Through (Permanent Fix):** Dynamically toggles `NSWindow.ignoresMouseEvents` so the interior is 100% WindowServer pass-through while keeping the 40pt header bar and 8px resize edges interactive.
- **Auto-Lock Loop Fix:** `makeAutoLockTask` now passes `containerBounds` and respects constrained app minimum sizes so it never repeatedly resizes/raises windows while you work.
- **Multi-Workspace & Edge Cases:** Staggered docked Framed Group sidebar pills, hid other `frameController`s during Virtual Switch, guarded concurrent hotkey launches, matched `preferredWindowNumber`, and disambiguated identical-name monitors (`displayTag`).
- **UX & Polish:** Added inline empty-slot hint, `Focus Windows` / `Lock Layout` labels, persistent `⌥⌘1–9` shortcut badges, 2-column Options `Grid`, `Capture Current Desktop` in menu bar, and `codesign --verify` + pre-release semver checks in `UpdateManager`.

## [1.3.3] - 2026-11-22
### Fixed
- **Framed Group Click-Through & App Interaction:** Disabled hit-testing on the Framed Group's transparent interior (`allowsHitTesting(false)`) and automatically raised member windows on `windowDidBecomeKey` so apps inside the frame are always clickable and interactive.

## [1.3.2] - 2026-11-22
### Fixed
- **Framed Group Full-Screen / Green Button:** Disabled isolated native macOS Full Screen Space (`collectionBehavior = [.fullScreenNone]`) on the Framed Group window and routed the green zoom button (`windowShouldZoom`) to `toggleMaximize()` so maximizing the frame keeps all member windows together on the same Desktop.

## [1.3.1] - 2026-11-22
### Fixed
- **Safari & Cryptex App Discovery:** Resolved symlinks in `loadInstalledApps()` and added `/System/Cryptexes/App/System/Applications` so Safari and other symlinked system apps appear in **Installed Apps**.

## [1.3.0] - 2026-11-21
### Fixed
- **Open Windows Picker (No Ghosts or Duplicates):** Filtered strictly to `.regular` GUI apps and standard `AXUIElement` windows with real window titles (`kAXTitleAttribute`), eliminating `AutoFill`, `CUAService`, and duplicate invisible helper rows.
### Added
- **Smart Overflow Guard:** Reads back `kAXSizeAttribute` after tiling, clamps oversized windows inside the container bounds, and displays a `Min W×H` warning badge on constrained slots.
- **Capture Current Desktop:** One-click **Capture** button in the sidebar snapshots all visible open windows and their positions into a custom workspace.
- **Global Hotkeys:** `⌥⌘1`–`⌥⌘9` to launch or focus workspaces from anywhere, and `⌥⌘R` to Re-Align.
- **Virtual Workspace Switch Mode:** Instant, animation-free workspace switching on the current Space (AeroSpace-style) alongside Current Desktop and New Mission Control Desktop.

## [1.2.2] - 2026-11-20
### Fixed
- **Framed Group Header & Insets:** Ignored titlebar safe-area inset in the Framed Group window and inset member windows inside the 40pt header bar and 2px border so apps no longer overflow at the top or cover the frame controls.

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
