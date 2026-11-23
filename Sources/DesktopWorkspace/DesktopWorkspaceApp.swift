import SwiftUI
import AppKit

@main
struct DesktopWorkspaceApp: App {
    @StateObject private var store = WorkspaceStore()
    @StateObject private var windowManager = WindowManager()
    @StateObject private var updateManager = UpdateManager()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Desktop Workspace", id: "main") {
            ContentView(store: store, windowManager: windowManager, updateManager: updateManager)
                .task {
                    registerGlobalHotkeys()
                    await updateManager.checkForUpdates(silentIfUpToDate: true)
                }
        }
        .defaultSize(width: 980, height: 740)

        MenuBarExtra("Desktop Workspace", systemImage: "rectangle.3.group") {
            if !windowManager.isAccessibilityGranted {
                Button("⚠️ Grant Accessibility Permission…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                    windowManager.requestAccessibilityPermission()
                }
                Divider()
            }

            if store.workspaces.isEmpty {
                Text("No saved workspaces")
            } else {
                ForEach(store.workspaces) { ws in
                    if windowManager.isActive(ws.id) {
                        Button("Focus \(ws.name)") {
                            windowManager.focusWorkspace(id: ws.id)
                        }
                    } else {
                        Button("Launch \(ws.name)") {
                            Task {
                                let ok = await windowManager.launchWorkspace(ws) { rect in
                                    store.updateSavedFrame(rect, for: ws.id)
                                }
                                if !ok {
                                    NSApp.activate(ignoringOtherApps: true)
                                    openWindow(id: "main")
                                }
                            }
                        }
                        .disabled(ws.slotApps.isEmpty || windowManager.isLaunching)
                    }
                }

                if !windowManager.activeWorkspaces.isEmpty {
                    Divider()
                    ForEach(windowManager.activeWorkspaces) { activeWs in
                        Button("Re-Align \(activeWs.name)") {
                            Task { await windowManager.realignWorkspace(id: activeWs.id) }
                        }
                        Button("Close \(activeWs.name)") {
                            windowManager.stopWorkspace(id: activeWs.id, closeWindows: true)
                        }
                    }
                }
            }

            Divider()

            Button("Capture Current Desktop") {
                switch store.captureCurrentDesktop() {
                case .success(let captured):
                    windowManager.statusMessage = "Captured \(captured.slotApps.count) open windows into “\(captured.name)”."
                    windowManager.statusSeverity = .success
                case .needsAccessibility:
                    windowManager.statusMessage = "Accessibility permission is required to capture open windows."
                    windowManager.statusSeverity = .warning
                case .noOpenWindows:
                    windowManager.statusMessage = "No open standard windows found on the current desktop to capture."
                    windowManager.statusSeverity = .warning
                }
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }

            Button("Open Desktop Workspace") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }

            if updateManager.isSupported {
                if let update = updateManager.availableUpdate {
                    Button("Install Update v\(update.version)…") {
                        Task { await updateManager.installUpdate(update) }
                    }
                    .disabled(updateManager.isInstalling)
                } else {
                    Button("Check for Updates…") {
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: "main")
                        Task { await updateManager.checkForUpdates(silentIfUpToDate: false) }
                    }
                }
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private func registerGlobalHotkeys() {
        HotkeyManager.shared.register(
            onWorkspaceIndex: { index in
                guard index < store.workspaces.count else { return }
                let ws = store.workspaces[index]
                if windowManager.isActive(ws.id) {
                    windowManager.focusWorkspace(id: ws.id)
                } else {
                    Task {
                        let launched = await windowManager.launchWorkspace(ws) { rect in
                            store.updateSavedFrame(rect, for: ws.id)
                        }
                        if !launched {
                            NSApp.activate(ignoringOtherApps: true)
                            openWindow(id: "main")
                        }
                    }
                }
            },
            onRealign: {
                let hadActive = windowManager.hasActiveWorkspace
                Task { await windowManager.realignActiveWorkspace() }
                if !hadActive {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
            }
        )
    }
}
