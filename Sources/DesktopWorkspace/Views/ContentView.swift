import SwiftUI

struct ContentView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var windowManager: WindowManager
    @ObservedObject var updateManager: UpdateManager

    @State private var pickingSlot: LayoutSlot?
    @State private var workspacePendingDelete: SavedWorkspace?
    @State private var pendingPresetReplacement: LayoutPreset?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let selectedId = store.selectedWorkspaceId,
               let workspaceBinding = store.binding(for: selectedId) {
                workspaceEditor(workspaceBinding)
            } else {
                emptyState
            }
        }
        .frame(minWidth: 880, minHeight: 680)
        .onAppear {
            windowManager.refreshAccessibilityStatus()
        }
        .task(id: windowManager.isAccessibilityGranted) {
            while !windowManager.isAccessibilityGranted && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                windowManager.refreshAccessibilityStatus()
            }
        }
        .sheet(item: $pickingSlot) { slot in
            if let selectedId = store.selectedWorkspaceId,
               let workspaceBinding = store.binding(for: selectedId) {
                let ws = workspaceBinding.wrappedValue
                let slotLabels = Dictionary(uniqueKeysWithValues: ws.preset.slots.map { ($0.id, $0.label) })
                let assignedWindows: [Int: String] = Dictionary(
                    ws.slotApps.compactMap { (slotId, app) -> (Int, String)? in
                        guard slotId != slot.id, let winNum = app.preferredWindowNumber else { return nil }
                        return (winNum, slotLabels[slotId] ?? "Slot \(slotId + 1)")
                    },
                    uniquingKeysWith: { first, _ in first }
                )
                AppPickerSheet(
                    slot: slot,
                    apps: store.installedApps,
                    isLoading: store.isLoadingApps,
                    assignedOpenWindows: assignedWindows,
                    runningWindowsProvider: { store.loadRunningWindows() }
                ) { assignment in
                    workspaceBinding.wrappedValue.slotApps[slot.id] = assignment
                }
            }
        }
        .confirmationDialog(
            "Delete Workspace?",
            isPresented: Binding(
                get: { workspacePendingDelete != nil },
                set: { if !$0 { workspacePendingDelete = nil } }
            ),
            presenting: workspacePendingDelete
        ) { ws in
            Button("Delete “\(ws.name)”", role: .destructive) {
                store.deleteWorkspace(ws.id)
                workspacePendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                workspacePendingDelete = nil
            }
        } message: { ws in
            Text("This removes “\(ws.name)” and its layout assignments.")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $store.selectedWorkspaceId) {
                Section("Saved Workspaces") {
                    ForEach(Array(store.workspaces.enumerated()), id: \.element.id) { index, ws in
                        HStack(spacing: 10) {
                            MiniPresetGlyph(preset: ws.preset)
                                .frame(width: 24, height: 16)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(ws.name)
                                        .font(.body)
                                        .lineLimit(1)
                                    if windowManager.isActive(ws.id) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 7, height: 7)
                                            .help("Launched & Active")
                                    }
                                }
                                Text("\(ws.preset.name) • \(ws.slotApps.count)/\(ws.preset.slots.count) apps")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 6) {
                                if index < 9 {
                                    Text("⌥⌘\(index + 1)")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary)
                                }
                                if windowManager.isActive(ws.id) {
                                    Text("Active")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.green)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.14))
                                        .cornerRadius(4)
                                }
                            }
                        }
                        .tag(ws.id)
                        .contextMenu {
                            if windowManager.isActive(ws.id) {
                                Button("Focus Windows") {
                                    windowManager.focusWorkspace(id: ws.id)
                                }
                                Button("Re-Align") {
                                    Task { await windowManager.realignWorkspace(id: ws.id) }
                                }
                                Button("Close Workspace") {
                                    windowManager.stopWorkspace(id: ws.id, closeWindows: true)
                                }
                                Button("Stop Tracking Only") {
                                    windowManager.stopWorkspace(id: ws.id, closeWindows: false)
                                }
                            } else {
                                Button("Launch Workspace") {
                                    Task {
                                        await windowManager.launchWorkspace(ws) { rect in
                                            store.updateSavedFrame(rect, for: ws.id)
                                        }
                                    }
                                }
                            }
                            Divider()
                            Button("Duplicate") {
                                store.duplicateWorkspace(ws)
                            }
                            Button("Delete", role: .destructive) {
                                workspacePendingDelete = ws
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Button {
                        store.addWorkspace()
                    } label: {
                        Label("New", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        switch store.captureCurrentDesktop() {
                        case .success(let captured):
                            windowManager.statusMessage = "Captured \(captured.slotApps.count) open windows into “\(captured.name)”."
                            windowManager.statusSeverity = .success
                        case .needsAccessibility:
                            windowManager.statusMessage = "Grant Accessibility permission first to capture open windows."
                            windowManager.statusSeverity = .warning
                        case .noOpenWindows:
                            windowManager.statusMessage = "No visible app windows found on the current screen to capture."
                            windowManager.statusSeverity = .warning
                        }
                    } label: {
                        Label("Capture", systemImage: "camera.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .help("Capture all currently open windows and their positions into a custom workspace")
                }

                accessibilityBanner

                if updateManager.isSupported {
                    updateBanner
                }
            }
            .padding(10)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
    }

    private var accessibilityBanner: some View {
        HStack(spacing: 6) {
            if windowManager.isAccessibilityGranted {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                Text("Accessibility Ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Needs Accessibility")
                    .font(.caption)
                    .foregroundStyle(.primary)
                Spacer()
                Button("Grant") {
                    windowManager.requestAccessibilityPermission()
                }
                .font(.caption)
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .onTapGesture {
            windowManager.refreshAccessibilityStatus()
        }
    }

    private var updateBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let update = updateManager.availableUpdate {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("v\(update.version) ready")
                        .font(.caption.bold())
                    Spacer()
                    Button(updateManager.isInstalling ? "Installing…" : "Update") {
                        Task { await updateManager.installUpdate(update) }
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .disabled(updateManager.isInstalling)
                }
            } else {
                HStack(spacing: 6) {
                    Text("v\(updateManager.currentVersion)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(updateManager.isChecking ? "Checking…" : "Check Updates") {
                        Task { await updateManager.checkForUpdates(silentIfUpToDate: false) }
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .disabled(updateManager.isChecking)
                }
            }

            if let text = updateManager.statusText, updateManager.availableUpdate == nil {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }

    // MARK: - Detail Editor

    private func workspaceEditor(_ workspace: Binding<SavedWorkspace>) -> some View {
        let ws = workspace.wrappedValue
        return VStack(spacing: 0) {
            // Top bar
            HStack(spacing: 12) {
                TextField("Workspace Name", text: workspace.name)
                    .textFieldStyle(.plain)
                    .font(.title2.bold())

                if windowManager.isActive(ws.id) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                        Text("Launched")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.14))
                    .cornerRadius(6)
                }

                Spacer()

                if windowManager.isActive(ws.id) {
                    Button {
                        Task { await windowManager.realignWorkspace(id: ws.id) }
                    } label: {
                        Label("Re-Align", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .help("Reset this workspace's windows to their proper alignment (⌘⇧R in-app, ⌥⌘R global)")

                    Button {
                        windowManager.stopWorkspace(id: ws.id, closeWindows: true)
                    } label: {
                        Label("Close", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help("Stop and close this active workspace's windows")
                } else if windowManager.hasActiveWorkspace {
                    Button {
                        Task { await windowManager.realignActiveWorkspace() }
                    } label: {
                        Label("Re-Align", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .help("Reset active workspace windows to their proper alignment (⌘⇧R in-app, ⌥⌘R global)")
                }

                Button {
                    workspacePendingDelete = ws
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .help("Delete Workspace")

                Button {
                    if windowManager.isActive(ws.id) {
                        windowManager.focusWorkspace(id: ws.id)
                    } else {
                        Task {
                            await windowManager.launchWorkspace(ws) { rect in
                                store.updateSavedFrame(rect, for: ws.id)
                            }
                        }
                    }
                } label: {
                    if windowManager.isLaunching {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 4)
                    } else if windowManager.isActive(ws.id) {
                        Label("Focus Windows", systemImage: "arrow.up.forward.app.fill")
                    } else {
                        Label("Launch Workspace", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(windowManager.isLaunching || ws.slotApps.isEmpty)
                .keyboardShortcut("r", modifiers: [.command])
                .help(
                    ws.slotApps.isEmpty
                        ? "Assign an app to at least one slot first"
                        : (windowManager.isActive(ws.id) ? "Bring this launched workspace's windows to front (⌘R)" : "Launch and arrange this workspace (⌘R)")
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            if ws.slotApps.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "hand.tap")
                        .foregroundStyle(Color.accentColor)
                    Text("Click any slot below to assign an app before launching.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Layout Preset Picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Layout")
                            .font(.headline)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                if ws.customSlots != nil {
                                    LayoutThumbnail(
                                        preset: ws.preset,
                                        isSelected: true
                                    )
                                    .help("Custom captured layout")
                                }

                                ForEach(LayoutPreset.allPresets) { preset in
                                    Button {
                                        if ws.customSlots != nil {
                                            pendingPresetReplacement = preset
                                        } else {
                                            applyPreset(preset, to: workspace)
                                        }
                                    } label: {
                                        LayoutThumbnail(
                                            preset: preset,
                                            isSelected: ws.customSlots == nil && ws.presetId == preset.id
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .alert(
                            "Replace Captured Layout?",
                            isPresented: Binding(
                                get: { pendingPresetReplacement != nil },
                                set: { if !$0 { pendingPresetReplacement = nil } }
                            ),
                            presenting: pendingPresetReplacement
                        ) { preset in
                            Button("Replace with \(preset.name)", role: .destructive) {
                                applyPreset(preset, to: workspace)
                                pendingPresetReplacement = nil
                            }
                            Button("Cancel", role: .cancel) {
                                pendingPresetReplacement = nil
                            }
                        } message: { preset in
                            Text("Switching to “\(preset.name)” will discard your custom captured slot positions.")
                        }
                    }

                    // Visual Slot Assignment
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Apps & Window Positions")
                                .font(.headline)
                            Spacer()
                            Text("Click a slot to assign • Drag & drop slots to swap")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        InteractiveLayoutCanvas(
                            preset: ws.preset,
                            slotApps: ws.slotApps,
                            gap: ws.gap,
                            overflowWarnings: windowManager.overflowWarnings[ws.id] ?? [:],
                            iconProvider: { store.icon(for: $0) },
                            onSelectSlot: { slot in
                                pickingSlot = slot
                            },
                            onClearSlot: { slot in
                                workspace.wrappedValue.slotApps.removeValue(forKey: slot.id)
                            },
                            onSwapSlots: { fromId, toId in
                                var updated = workspace.wrappedValue
                                let fromApp = updated.slotApps[fromId]
                                let toApp = updated.slotApps[toId]
                                if let fromApp {
                                    updated.slotApps[toId] = fromApp
                                } else {
                                    updated.slotApps.removeValue(forKey: toId)
                                }
                                if let toApp {
                                    updated.slotApps[fromId] = toApp
                                } else {
                                    updated.slotApps.removeValue(forKey: fromId)
                                }
                                if windowManager.isActive(ws.id) {
                                    windowManager.swapActiveSlotWindows(workspaceId: ws.id, from: fromId, to: toId)
                                }
                                workspace.wrappedValue = updated
                            }
                        )
                        .frame(maxHeight: 270)
                    }

                    // Workspace Options
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Options")
                            .font(.headline)

                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                            GridRow {
                                HStack(spacing: 8) {
                                    Text("Mode:")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 56, alignment: .leading)
                                    Picker("", selection: workspace.mode) {
                                        ForEach(WorkspaceMode.allCases) { mode in
                                            Text(mode.title).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 250)
                                    .help(ws.mode.subtitle)
                                }

                                HStack(spacing: 8) {
                                    Text("Display:")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Picker("", selection: Binding(
                                        get: { ws.targetDisplayName ?? "" },
                                        set: { workspace.targetDisplayName.wrappedValue = $0.isEmpty ? nil : $0 }
                                    )) {
                                        Text("Active Display").tag("")
                                        Text("Primary Display").tag("__primary__")
                                        ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { idx, screen in
                                            Text("\(screen.localizedName) (\(idx + 1))").tag(screen.displayTag)
                                        }
                                        if let savedDisplay = ws.targetDisplayName,
                                           savedDisplay != "__primary__",
                                           !NSScreen.screens.contains(where: { $0.displayTag == savedDisplay }) {
                                            Text("\(savedDisplay) (Disconnected)").tag(savedDisplay)
                                        }
                                    }
                                    .frame(width: 170)
                                }
                            }

                            GridRow {
                                HStack(spacing: 8) {
                                    Text("Space:")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 56, alignment: .leading)
                                    Picker("", selection: workspace.spaceBehavior) {
                                        ForEach(SpaceBehavior.allCases) { behavior in
                                            Text(behavior.title).tag(behavior)
                                        }
                                    }
                                    .frame(width: 165)
                                    .help(ws.spaceBehavior.helpText)
                                }

                                HStack(spacing: 16) {
                                    Toggle("New Window if Running", isOn: workspace.openNewWindowIfRunning)
                                        .help("Opens a fresh window for apps that are already running")
                                    Toggle("Lock Layout", isOn: workspace.autoLockLayout)
                                        .help("Automatically snaps windows back if resized or moved")
                                }
                            }

                            GridRow {
                                HStack(spacing: 8) {
                                    Text("Gap:")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 56, alignment: .leading)
                                    Slider(value: workspace.gap, in: 0...16, step: 2)
                                        .frame(width: 110)
                                    Text("\(Int(ws.gap))px")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 36, alignment: .leading)
                                }
                                Color.clear.frame(height: 1)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(10)
                }
                .padding(16)
            }

            if let status = windowManager.statusMessage {
                Divider()
                HStack(spacing: 8) {
                    statusIcon(for: windowManager.statusSeverity)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(statusColor(for: windowManager.statusSeverity))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .onChange(of: ws) { _, updated in
            if windowManager.isActive(updated.id) {
                Task {
                    await windowManager.syncUpdatedWorkspace(updated)
                }
            }
        }
    }

    @ViewBuilder
    private func statusIcon(for severity: StatusSeverity) -> some View {
        switch severity {
        case .info:
            Image(systemName: "info.circle").foregroundStyle(.secondary)
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .error:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    private func applyPreset(_ preset: LayoutPreset, to workspace: Binding<SavedWorkspace>) {
        let validIds = Set(preset.slots.map(\.id))
        var updated = workspace.wrappedValue
        updated.presetId = preset.id
        updated.customSlots = nil
        updated.slotApps = updated.slotApps.filter { validIds.contains($0.key) }
        workspace.wrappedValue = updated
    }

    private func statusColor(for severity: StatusSeverity) -> Color {
        switch severity {
        case .info: return .secondary
        case .success: return .primary
        case .warning: return .orange
        case .error: return .red
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("No Workspace Selected")
                .font(.title3.bold())
            Button("Create Workspace") {
                store.addWorkspace()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MiniPresetGlyph: View {
    let preset: LayoutPreset

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(preset.slots) { slot in
                    let w = max(2, slot.rect.width * geo.size.width - 1.5)
                    let h = max(2, slot.rect.height * geo.size.height - 1.5)
                    let x = slot.rect.x * geo.size.width + 0.75
                    let y = slot.rect.y * geo.size.height + 0.75

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: w, height: h)
                        .offset(x: x, y: y)
                }
            }
        }
    }
}
