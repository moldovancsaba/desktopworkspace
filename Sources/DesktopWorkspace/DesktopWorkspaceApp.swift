import SwiftUI
import AppKit

@main
struct DesktopWorkspaceApp: App {
    @StateObject private var store = WorkspaceStore()
    @StateObject private var windowManager = WindowManager()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Desktop Workspace", id: "main") {
            ContentView(store: store, windowManager: windowManager)
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

                if !windowManager.activeWorkspaces.isEmpty {
                    Divider()
                    ForEach(windowManager.activeWorkspaces) { activeWs in
                        Button("Re-Align \(activeWs.name)") {
                            Task { await windowManager.realignWorkspace(id: activeWs.id) }
                        }
                    }
                }
            }

            Divider()

            Button("Open Desktop Workspace") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
