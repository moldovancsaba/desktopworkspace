import Foundation
import AppKit
import ApplicationServices

enum StatusSeverity {
    case info, success, warning, error
}

struct ActiveWorkspaceSession {
    var workspace: SavedWorkspace
    var screen: NSScreen
    var trackedSlotWindows: [Int: AXUIElement]
    var frameController: WorkspaceFrameController?
    var autoLockTask: Task<Void, Never>?
}

@MainActor
final class WindowManager: ObservableObject {
    @Published var isAccessibilityGranted: Bool = AXIsProcessTrusted()
    @Published var isLaunching: Bool = false
    @Published var statusMessage: String?
    @Published var statusSeverity: StatusSeverity = .info
    @Published var activeWorkspaceIds: Set<UUID> = []
    @Published var lastActiveWorkspaceId: UUID?
    @Published var overflowWarnings: [UUID: [Int: CGSize]] = [:]

    private var activeObserver: NSObjectProtocol?
    private var didPromptAccessibilityThisSession = false

    private var activeSessions: [UUID: ActiveWorkspaceSession] = [:]

    var hasActiveWorkspace: Bool {
        !activeSessions.isEmpty
    }

    var activeWorkspaceName: String? {
        guard let id = lastActiveWorkspaceId else { return activeSessions.values.first?.workspace.name }
        return activeSessions[id]?.workspace.name ?? activeSessions.values.first?.workspace.name
    }

    var activeWorkspaces: [SavedWorkspace] {
        activeSessions.values
            .map(\.workspace)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func isActive(_ workspaceId: UUID) -> Bool {
        activeSessions[workspaceId] != nil
    }

    func focusWorkspace(id workspaceId: UUID) {
        guard let session = activeSessions[workspaceId] else { return }
        if session.workspace.spaceBehavior == .virtualSwitch {
            hideOtherVirtualWorkspaces(except: workspaceId)
            session.frameController?.setHiddenForVirtualSwitch(false)
        }
        lastActiveWorkspaceId = workspaceId
        session.frameController?.focus()

        var activatedPids = Set<pid_t>()
        for (_, win) in session.trackedSlotWindows where isWindowAlive(win) {
            let pid = pidForElement(win)
            if !activatedPids.contains(pid), let app = NSRunningApplication(processIdentifier: pid) {
                app.activate(options: [])
                activatedPids.insert(pid)
            }
            AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(win, kAXRaiseAction as CFString)
        }
        setStatus("Focused “\(session.workspace.name)”.", severity: .info)
    }

    private func hideOtherVirtualWorkspaces(except keepId: UUID) {
        for (otherId, otherSession) in activeSessions where otherId != keepId && otherSession.workspace.spaceBehavior == .virtualSwitch {
            setTrackedWindowsMinimized(true, for: otherId)
            otherSession.frameController?.setHiddenForVirtualSwitch(true)
        }
    }

    private func screenAXBounds(_ screen: NSScreen) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let visible = screen.visibleFrame
        let topY = primaryHeight - (visible.origin.y + visible.height)
        return CGRect(x: visible.origin.x, y: topY, width: visible.width, height: visible.height)
    }

    func stopWorkspace(id workspaceId: UUID, closeWindows: Bool = true) {
        if let removed = activeSessions.removeValue(forKey: workspaceId) {
            removed.autoLockTask?.cancel()
            removed.frameController?.close()
            if closeWindows {
                for (_, win) in removed.trackedSlotWindows where isWindowAlive(win) {
                    var closeBtnRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(win, kAXCloseButtonAttribute as CFString, &closeBtnRef) == .success,
                       let closeBtn = closeBtnRef {
                        AXUIElementPerformAction(closeBtn as! AXUIElement, kAXPressAction as CFString)
                    }
                }
            }
            activeWorkspaceIds = Set(activeSessions.keys)
            if lastActiveWorkspaceId == workspaceId {
                lastActiveWorkspaceId = activeSessions.keys.first
            }
            setStatus(
                closeWindows ? "Closed “\(removed.workspace.name)”." : "Stopped tracking “\(removed.workspace.name)”.",
                severity: .info
            )
        }
    }

    func syncUpdatedWorkspace(_ updated: SavedWorkspace) async {
        guard var session = activeSessions[updated.id] else { return }
        let old = session.workspace
        session.workspace = updated
        session.frameController?.workspaceName = updated.name

        if old.mode != updated.mode {
            await launchWorkspace(updated)
            return
        }

        if let newScreen = targetScreen(for: updated), old.targetDisplayName != updated.targetDisplayName {
            session.screen = newScreen
        }

        // Prune tracked windows for slots that were cleared or removed
        let validSlotIds = Set(updated.preset.slots.map(\.id))
        for slotId in Array(session.trackedSlotWindows.keys) {
            if !validSlotIds.contains(slotId) || updated.slotApps[slotId] == nil {
                session.trackedSlotWindows.removeValue(forKey: slotId)
            } else if old.slotApps[slotId] != updated.slotApps[slotId] {
                session.trackedSlotWindows.removeValue(forKey: slotId)
            }
        }

        if old.autoLockLayout != updated.autoLockLayout {
            session.autoLockTask?.cancel()
            activeSessions[updated.id] = session
            session.autoLockTask = makeAutoLockTask(for: updated.id)
        }
        activeSessions[updated.id] = session

        if old.gap != updated.gap ||
            old.presetId != updated.presetId ||
            old.customSlots != updated.customSlots ||
            old.spaceBehavior != updated.spaceBehavior ||
            old.slotApps != updated.slotApps ||
            old.targetDisplayName != updated.targetDisplayName {
            await realignWorkspace(id: updated.id)
        }
    }

    func swapActiveSlotWindows(workspaceId: UUID, from sourceSlotId: Int, to destSlotId: Int) {
        guard var session = activeSessions[workspaceId] else { return }
        let srcWin = session.trackedSlotWindows[sourceSlotId]
        let dstWin = session.trackedSlotWindows[destSlotId]
        session.trackedSlotWindows[destSlotId] = srcWin
        session.trackedSlotWindows[sourceSlotId] = dstWin

        // Keep session.workspace.slotApps in sync so syncUpdatedWorkspace does not treat the swap as new apps and wipe trackedSlotWindows
        let srcApp = session.workspace.slotApps[sourceSlotId]
        let dstApp = session.workspace.slotApps[destSlotId]
        if let srcApp {
            session.workspace.slotApps[destSlotId] = srcApp
        } else {
            session.workspace.slotApps.removeValue(forKey: destSlotId)
        }
        if let dstApp {
            session.workspace.slotApps[sourceSlotId] = dstApp
        } else {
            session.workspace.slotApps.removeValue(forKey: sourceSlotId)
        }

        if var warnings = overflowWarnings[workspaceId] {
            let srcWarn = warnings[sourceSlotId]
            let dstWarn = warnings[destSlotId]
            warnings[destSlotId] = srcWarn
            warnings[sourceSlotId] = dstWarn
            overflowWarnings[workspaceId] = warnings.isEmpty ? nil : warnings
        }

        activeSessions[workspaceId] = session
        Task { await realignWorkspace(id: workspaceId) }
    }

    init() {
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAccessibilityStatus()
            }
        }
    }

    func refreshAccessibilityStatus() {
        isAccessibilityGranted = AXIsProcessTrusted()
    }

    private func setStatus(_ message: String, severity: StatusSeverity = .info) {
        statusMessage = message
        statusSeverity = severity
    }

    func requestAccessibilityPermission(openSettingsImmediately: Bool = true) {
        refreshAccessibilityStatus()
        if isAccessibilityGranted { return }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        isAccessibilityGranted = granted
        if !granted {
            setStatus("Grant Accessibility permission in System Settings to arrange windows.", severity: .warning)
            if openSettingsImmediately,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func targetScreen(for workspace: SavedWorkspace) -> NSScreen? {
        if let name = workspace.targetDisplayName {
            if name == "__primary__" {
                return NSScreen.screens.first
            }
            if let matchedByTag = NSScreen.screens.first(where: { $0.displayTag == name }) {
                return matchedByTag
            }
            if let matchedByName = NSScreen.screens.first(where: { $0.localizedName == name }) {
                return matchedByName
            }
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    @discardableResult
    func launchWorkspace(_ workspace: SavedWorkspace, onFrameSaved: ((CGRect) -> Void)? = nil) async -> Bool {
        guard !isLaunching else { return false }
        refreshAccessibilityStatus()
        guard isAccessibilityGranted else {
            setStatus("Accessibility permission required to move and resize windows.", severity: .error)
            if !didPromptAccessibilityThisSession {
                didPromptAccessibilityThisSession = true
                requestAccessibilityPermission(openSettingsImmediately: false)
            } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
            return false
        }

        let preset = workspace.preset
        let assignedSlots = preset.slots.compactMap { slot -> (LayoutSlot, AppAssignment)? in
            guard let app = workspace.slotApps[slot.id] else { return nil }
            return (slot, app)
        }

        guard !assignedSlots.isEmpty else {
            setStatus("Assign at least one app to a layout slot first.", severity: .warning)
            return false
        }

        isLaunching = true
        if let existing = activeSessions.removeValue(forKey: workspace.id) {
            existing.autoLockTask?.cancel()
            existing.frameController?.close()
        }
        activeWorkspaceIds = Set(activeSessions.keys)
        setStatus("Preparing workspace “\(workspace.name)”…", severity: .info)
        defer { isLaunching = false }

        guard let screen = targetScreen(for: workspace) else {
            setStatus("No display found.", severity: .error)
            return false
        }

        var desktopNote = ""
        switch workspace.spaceBehavior {
        case .newMissionControlDesktop:
            setStatus("Creating a new Desktop…", severity: .info)
            let created = await createAndSwitchToNewDesktop()
            if !created {
                desktopNote = " (arranged on current Desktop — Mission Control '+' not available)"
            } else {
                try? await Task.sleep(nanoseconds: 550_000_000)
            }
        case .virtualSwitch:
            hideOtherVirtualWorkspaces(except: workspace.id)
        case .currentDesktop:
            break
        }

        var frameContainerAXRect: CGRect?
        var newFrameController: WorkspaceFrameController?
        if workspace.mode == .framed {
            let wsId = workspace.id
            let controller = WorkspaceFrameController(workspaceName: workspace.name)
            frameContainerAXRect = controller.show(on: screen, initialFrame: workspace.savedFrame?.cgRect)
            controller.onContentRectChanged = { [weak self] contentRect in
                self?.syncWindows(for: wsId, inAXContainer: contentRect)
            }
            controller.onRealignRequested = { [weak self] in
                Task { @MainActor in
                    await self?.realignWorkspace(id: wsId)
                }
            }
            controller.onSetMinimized = { [weak self] minimized in
                self?.setTrackedWindowsMinimized(minimized, for: wsId)
            }
            controller.onRaiseMemberWindows = { [weak self] in
                self?.raiseTrackedWindows(for: wsId)
            }
            controller.onFrameSaved = { rect in
                onFrameSaved?(rect)
            }
            controller.onScreenChanged = { [weak self] newScreen in
                self?.activeSessions[wsId]?.screen = newScreen
            }
            controller.dockSlotIndexProvider = { [weak self] in
                guard let self else { return 0 }
                let usedIndices = Set(self.activeSessions.values.compactMap { session -> Int? in
                    guard session.workspace.id != wsId,
                          let fc = session.frameController,
                          fc.isDockedToSidebar else { return nil }
                    return fc.dockSlotIndex
                })
                var index = 0
                while usedIndices.contains(index) {
                    index += 1
                }
                return index
            }
            controller.onClosed = { [weak self] in
                guard let self else { return }
                if let removed = self.activeSessions.removeValue(forKey: wsId) {
                    removed.autoLockTask?.cancel()
                    self.setStatus("Closed frame for “\(removed.workspace.name)” (member windows remain open).", severity: .info)
                }
                self.overflowWarnings.removeValue(forKey: wsId)
                self.activeWorkspaceIds = Set(self.activeSessions.keys)
                if self.lastActiveWorkspaceId == wsId {
                    self.lastActiveWorkspaceId = self.activeSessions.keys.first
                }
            }
            newFrameController = controller
        }

        var usedWindowKeys = Set<String>()
        var slotWindows: [Int: AXUIElement] = [:]
        var arrangedCount = 0
        var failedApps: [String] = []
        var slotOverflows: [Int: CGSize] = [:]
        let containerBounds = frameContainerAXRect ?? screenAXBounds(screen)

        for (slot, assignment) in assignedSlots {
            setStatus("Opening \(assignment.name)…", severity: .info)
            let targetRect: CGRect
            if let container = frameContainerAXRect {
                targetRect = slot.rect.accessibilityRect(inAXContainer: container, gap: workspace.gap)
            } else {
                targetRect = slot.rect.accessibilityRect(in: screen, gap: workspace.gap)
            }

            if let window = await openOrFindWindow(
                for: assignment,
                openNewWindowIfRunning: workspace.openNewWindowIfRunning,
                excludingWindowKeys: usedWindowKeys
            ) {
                let key = windowIdentityKey(window, pid: pidForElement(window))
                usedWindowKeys.insert(key)
                slotWindows[slot.id] = window
                if let clampedSize = applyFrame(targetRect, to: window, containerBounds: containerBounds) {
                    slotOverflows[slot.id] = clampedSize
                }
                arrangedCount += 1
            } else {
                failedApps.append(assignment.name)
            }
        }

        overflowWarnings[workspace.id] = slotOverflows.isEmpty ? nil : slotOverflows

        var session = ActiveWorkspaceSession(
            workspace: workspace,
            screen: screen,
            trackedSlotWindows: slotWindows,
            frameController: newFrameController,
            autoLockTask: nil
        )
        session.autoLockTask = makeAutoLockTask(for: workspace.id)
        activeSessions[workspace.id] = session
        activeWorkspaceIds = Set(activeSessions.keys)
        lastActiveWorkspaceId = workspace.id

        if failedApps.isEmpty {
            let sev: StatusSeverity = desktopNote.isEmpty ? .success : .warning
            setStatus("Arranged \(arrangedCount)/\(assignedSlots.count) windows for “\(workspace.name)”\(desktopNote).", severity: sev)
        } else {
            setStatus("Arranged \(arrangedCount)/\(assignedSlots.count) windows (couldn't open window for: \(failedApps.joined(separator: ", ")))\(desktopNote).", severity: .warning)
        }
        return true
    }

    func realignActiveWorkspace() async {
        let targetId = lastActiveWorkspaceId ?? activeSessions.keys.first
        guard let targetId else {
            setStatus("Launch a workspace first to re-align its windows.", severity: .warning)
            return
        }
        await realignWorkspace(id: targetId)
    }

    func realignWorkspace(id workspaceId: UUID) async {
        refreshAccessibilityStatus()
        guard isAccessibilityGranted, var session = activeSessions[workspaceId] else {
            setStatus("Launch a workspace first to re-align its windows.", severity: .warning)
            return
        }

        let ws = session.workspace
        if ws.mode == .framed {
            if session.frameController?.isDockedToSidebar == true {
                session.frameController?.toggleSidebarDock()
                return
            }
            guard session.frameController != nil else {
                setStatus("Frame was closed. Launch “\(ws.name)” again to reopen it.", severity: .warning)
                return
            }
        }

        let containerAX = (ws.mode == .framed) ? session.frameController?.currentContentAXRect() : nil
        let screen = session.screen
        let containerBounds = containerAX ?? screenAXBounds(screen)
        lastActiveWorkspaceId = workspaceId

        var usedWindowKeys = Set<String>()
        for (_, win) in session.trackedSlotWindows where isWindowAlive(win) {
            usedWindowKeys.insert(windowIdentityKey(win, pid: pidForElement(win)))
        }

        var alignedCount = 0
        var slotOverflows: [Int: CGSize] = [:]
        for slot in ws.preset.slots {
            guard let assignment = ws.slotApps[slot.id] else { continue }
            let targetRect: CGRect
            if let containerAX {
                targetRect = slot.rect.accessibilityRect(inAXContainer: containerAX, gap: ws.gap)
            } else {
                targetRect = slot.rect.accessibilityRect(in: screen, gap: ws.gap)
            }

            if let existing = session.trackedSlotWindows[slot.id], isWindowAlive(existing) {
                if let clampedSize = applyFrame(targetRect, to: existing, containerBounds: containerBounds) {
                    slotOverflows[slot.id] = clampedSize
                }
                alignedCount += 1
            } else if let reopened = await openOrFindWindow(
                for: assignment,
                openNewWindowIfRunning: ws.openNewWindowIfRunning,
                excludingWindowKeys: usedWindowKeys
            ) {
                let key = windowIdentityKey(reopened, pid: pidForElement(reopened))
                usedWindowKeys.insert(key)
                session.trackedSlotWindows[slot.id] = reopened
                if let clampedSize = applyFrame(targetRect, to: reopened, containerBounds: containerBounds) {
                    slotOverflows[slot.id] = clampedSize
                }
                alignedCount += 1
            }
        }

        overflowWarnings[workspaceId] = slotOverflows.isEmpty ? nil : slotOverflows
        activeSessions[workspaceId] = session
        raiseTrackedWindows(for: workspaceId)
        setStatus("Re-aligned \(alignedCount) windows for “\(ws.name)”.", severity: .success)
    }

    private func isWindowAlive(_ window: AXUIElement) -> Bool {
        pointAttribute(window, kAXPositionAttribute) != nil
    }

    private func raiseTrackedWindows(for workspaceId: UUID) {
        guard let session = activeSessions[workspaceId] else { return }
        for (_, win) in session.trackedSlotWindows {
            AXUIElementPerformAction(win, kAXRaiseAction as CFString)
        }
    }

    private func syncWindows(for workspaceId: UUID, inAXContainer container: CGRect) {
        guard let session = activeSessions[workspaceId] else { return }
        let ws = session.workspace
        var slotOverflows: [Int: CGSize] = [:]
        for slot in ws.preset.slots {
            guard let win = session.trackedSlotWindows[slot.id] else { continue }
            let rect = slot.rect.accessibilityRect(inAXContainer: container, gap: ws.gap)
            if let clamped = applyFrame(rect, to: win, containerBounds: container) {
                slotOverflows[slot.id] = clamped
            }
        }
        overflowWarnings[workspaceId] = slotOverflows.isEmpty ? nil : slotOverflows
    }

    private func setTrackedWindowsMinimized(_ minimized: Bool, for workspaceId: UUID) {
        guard let session = activeSessions[workspaceId] else { return }
        let value: CFBoolean = minimized ? kCFBooleanTrue : kCFBooleanFalse
        for (_, win) in session.trackedSlotWindows {
            AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, value)
            if !minimized {
                AXUIElementPerformAction(win, kAXRaiseAction as CFString)
            }
        }
    }

    private func isWindowMinimized(_ window: AXUIElement) -> Bool {
        var minimizedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
              let isMin = minimizedRef as? Bool else {
            return false
        }
        return isMin
    }

    private func makeAutoLockTask(for workspaceId: UUID) -> Task<Void, Never>? {
        guard let session = activeSessions[workspaceId], session.workspace.autoLockLayout else {
            return nil
        }

        return Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard let self, !Task.isCancelled else { break }
                if !AXIsProcessTrusted() {
                    self.isAccessibilityGranted = false
                    self.setStatus("Accessibility permission was revoked.", severity: .error)
                    break
                }
                guard let session = self.activeSessions[workspaceId], session.workspace.autoLockLayout else { break }
                if session.frameController?.isDockedToSidebar == true { continue }

                let ws = session.workspace
                let containerAX: CGRect? = session.frameController?.currentContentAXRect()
                let screen = session.screen
                let containerBounds = containerAX ?? self.screenAXBounds(screen)

                for slot in ws.preset.slots {
                    guard let win = session.trackedSlotWindows[slot.id] else { continue }
                    if self.isWindowMinimized(win) { continue }
                    let expected: CGRect
                    if let containerAX {
                        expected = slot.rect.accessibilityRect(inAXContainer: containerAX, gap: ws.gap)
                    } else {
                        expected = slot.rect.accessibilityRect(in: screen, gap: ws.gap)
                    }

                    // Account for any known minimum-size constraint so Auto-Lock never loops infinitely
                    var effectiveRect = expected
                    if let minSize = self.overflowWarnings[workspaceId]?[slot.id] {
                        let w = max(expected.width, minSize.width)
                        let h = max(expected.height, minSize.height)
                        let x = max(containerBounds.minX, min(expected.origin.x, containerBounds.maxX - w))
                        let y = max(containerBounds.minY, min(expected.origin.y, containerBounds.maxY - h))
                        effectiveRect = CGRect(x: x, y: y, width: w, height: h)
                    }

                    if let curPos = self.pointAttribute(win, kAXPositionAttribute),
                       let curSize = self.sizeAttribute(win, kAXSizeAttribute) {
                        let drifted = abs(curPos.x - effectiveRect.origin.x) > 8 ||
                            abs(curPos.y - effectiveRect.origin.y) > 8 ||
                            abs(curSize.width - effectiveRect.width) > 8 ||
                            abs(curSize.height - effectiveRect.height) > 8
                        if drifted {
                            if let clamped = self.applyFrame(expected, to: win, containerBounds: containerBounds) {
                                self.overflowWarnings[workspaceId, default: [:]][slot.id] = clamped
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - New Desktop (Space) via Mission Control + Dock AX

    private func createAndSwitchToNewDesktop() async -> Bool {
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return false
        }

        let mcURL = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        _ = try? await NSWorkspace.shared.openApplication(at: mcURL, configuration: config)

        // Wait for Mission Control UI to appear in Dock's AX tree
        let dockElement = AXUIElementCreateApplication(dockApp.processIdentifier)
        var addDesktopButton: AXUIElement?

        for _ in 0..<15 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let btn = findElement(in: dockElement, maxDepth: 6, matching: { el in
                let role = stringAttribute(el, kAXRoleAttribute)
                let desc = (stringAttribute(el, kAXDescriptionAttribute) ?? "").lowercased()
                let title = (stringAttribute(el, kAXTitleAttribute) ?? "").lowercased()
                let id = (stringAttribute(el, kAXIdentifierAttribute) ?? "").lowercased()
                return role == kAXButtonRole as String &&
                    (desc.contains("add desktop") || title.contains("add desktop") || id.contains("add") || title == "+" || desc == "+")
            }) {
                addDesktopButton = btn
                break
            }
        }

        guard let addBtn = addDesktopButton else {
            // Exit Mission Control if we opened it
            sendEscapeKey()
            return false
        }

        // Count existing desktop buttons before adding
        let beforeCount = findDesktopButtons(in: dockElement).count
        AXUIElementPerformAction(addBtn, kAXPressAction as CFString)

        // Wait for the new desktop button to appear, then press the last one to switch to it
        try? await Task.sleep(nanoseconds: 350_000_000)
        let desktopButtons = findDesktopButtons(in: dockElement)

        if desktopButtons.count > beforeCount, let newestDesktop = desktopButtons.last {
            AXUIElementPerformAction(newestDesktop, kAXPressAction as CFString)
            return true
        }

        if let lastDesktop = desktopButtons.last {
            AXUIElementPerformAction(lastDesktop, kAXPressAction as CFString)
            return true
        }

        sendEscapeKey()
        return false
    }

    private func findDesktopButtons(in root: AXUIElement) -> [AXUIElement] {
        findAllElements(in: root, maxDepth: 6, matching: { el in
            guard stringAttribute(el, kAXRoleAttribute) == kAXButtonRole as String else { return false }
            let desc = (stringAttribute(el, kAXDescriptionAttribute) ?? "").lowercased()
            let title = (stringAttribute(el, kAXTitleAttribute) ?? "").lowercased()
            let id = (stringAttribute(el, kAXIdentifierAttribute) ?? "").lowercased()
            if id.contains("add") || desc.contains("add") || title == "+" {
                return false
            }
            if desc.hasPrefix("desktop ") || title.hasPrefix("desktop ") || id.contains("desktop") || id.contains("space") {
                return true
            }
            // Locale-independent fallback: Mission Control space thumbnails typically have a localized label ending in a space + number (e.g. "Íróasztal 2", "Schreibtisch 2")
            let label = title.isEmpty ? desc : title
            return label.split(separator: " ").last.flatMap({ Int($0) }) != nil
        })
    }

    private func sendEscapeKey() {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - App Launching & Window Discovery

    private func openOrFindWindow(
        for assignment: AppAssignment,
        openNewWindowIfRunning: Bool,
        excludingWindowKeys: Set<String>
    ) async -> AXUIElement? {
        let existingRunning = NSRunningApplication.runningApplications(withBundleIdentifier: assignment.bundleIdentifier).first

        if let running = existingRunning {
            let pid = running.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)
            let existingWindows = standardWindows(of: appElement)
            let existingKeys = Set(existingWindows.map { windowIdentityKey($0, pid: pid) })

            // If user picked an already-open window (preferredWindowNumber or preferredWindowTitle), match it first
            let unused = existingWindows.filter { !excludingWindowKeys.contains(windowIdentityKey($0, pid: pid)) }
            if let winNum = assignment.preferredWindowNumber,
               let cgBounds = cgWindowBounds(windowNumber: winNum),
               let matchedByBounds = unused.min(by: { a, b in
                   let ar = CGRect(origin: pointAttribute(a, kAXPositionAttribute) ?? .zero, size: sizeAttribute(a, kAXSizeAttribute) ?? .zero)
                   let br = CGRect(origin: pointAttribute(b, kAXPositionAttribute) ?? .zero, size: sizeAttribute(b, kAXSizeAttribute) ?? .zero)
                   let da = abs(ar.origin.x - cgBounds.origin.x) + abs(ar.origin.y - cgBounds.origin.y) + abs(ar.width - cgBounds.width)
                   let db = abs(br.origin.x - cgBounds.origin.x) + abs(br.origin.y - cgBounds.origin.y) + abs(br.width - cgBounds.width)
                   return da < db
               }) {
                return matchedByBounds
            }
            if let preferred = assignment.preferredWindowTitle, !preferred.isEmpty {
                if let exact = unused.first(where: { (stringAttribute($0, kAXTitleAttribute) ?? "") == preferred }) {
                    return exact
                }
                if let partial = unused.first(where: {
                    (stringAttribute($0, kAXTitleAttribute) ?? "").localizedCaseInsensitiveContains(preferred)
                }) {
                    return partial
                }
                if let anyUnused = unused.first {
                    return anyUnused
                }
            }

            if openNewWindowIfRunning || existingWindows.isEmpty {
                running.activate(options: [.activateAllWindows])
                try? await Task.sleep(nanoseconds: 180_000_000)

                if !existingWindows.isEmpty {
                    // Try File -> New Window / New via AXMenuBar first, fallback to Cmd+N
                    if !triggerNewWindowMenuItem(on: appElement) {
                        sendCommandN()
                    }
                } else {
                    // App had 0 windows; opening its URL creates a fresh window on current desktop
                    await launchAppBundle(assignment)
                }

                // Wait for a brand new window
                for _ in 0..<25 {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    let current = standardWindows(of: appElement)
                    if let brandNew = current.first(where: {
                        let key = windowIdentityKey($0, pid: pid)
                        return !existingKeys.contains(key) && !excludingWindowKeys.contains(key)
                    }) {
                        return brandNew
                    }
                }
            }

            // Fallback: pick an unused existing window
            if let fallback = standardWindows(of: appElement).first(where: {
                !excludingWindowKeys.contains(windowIdentityKey($0, pid: pid))
            }) {
                return fallback
            }
            return standardWindows(of: appElement).first
        } else {
            guard let running = await launchAppBundle(assignment) else {
                return nil
            }
            let pid = running.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)

            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 150_000_000)
                let windows = standardWindows(of: appElement)
                if let win = windows.first(where: { !excludingWindowKeys.contains(windowIdentityKey($0, pid: pid)) }) {
                    return win
                }
            }
            return nil
        }
    }

    @discardableResult
    private func launchAppBundle(_ assignment: AppAssignment) async -> NSRunningApplication? {
        let url: URL?
        if FileManager.default.fileExists(atPath: assignment.path) {
            url = URL(fileURLWithPath: assignment.path)
        } else {
            url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: assignment.bundleIdentifier)
        }
        guard let appURL = url else { return nil }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        return try? await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
    }

    private func triggerNewWindowMenuItem(on appElement: AXUIElement) -> Bool {
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBar = menuBarRef else {
            return false
        }

        let menuBarEl = menuBar as! AXUIElement

        // 1. Locale-independent lookup: any menu item bound to Cmd+N
        if let cmdNItem = findElement(in: menuBarEl, maxDepth: 4, matching: { el in
            guard stringAttribute(el, kAXRoleAttribute) == kAXMenuItemRole as String else { return false }
            let cmdChar = (stringAttribute(el, kAXMenuItemCmdCharAttribute) ?? "").uppercased()
            var modRef: CFTypeRef?
            let modVal: Int = (AXUIElementCopyAttributeValue(el, kAXMenuItemCmdModifiersAttribute as CFString, &modRef) == .success)
                ? ((modRef as? Int) ?? 0)
                : 0
            return cmdChar == "N" && modVal == 0
        }) {
            return AXUIElementPerformAction(cmdNItem, kAXPressAction as CFString) == .success
        }

        // 2. Fallback: English menu titles
        let candidateTitles = ["new window", "new private window", "new document", "new tab", "new"]
        if let item = findElement(in: menuBarEl, maxDepth: 4, matching: { el in
            let role = stringAttribute(el, kAXRoleAttribute)
            guard role == kAXMenuItemRole as String else { return false }
            let title = (stringAttribute(el, kAXTitleAttribute) ?? "").lowercased()
            return candidateTitles.contains(where: { title == $0 || title.hasPrefix($0 + " ") })
        }) {
            return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
        }
        return false
    }

    private func sendCommandN() {
        let src = CGEventSource(stateID: .hidSystemState)
        // 'n' virtual key is 45
        let down = CGEvent(keyboardEventSource: src, virtualKey: 45, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: 45, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Window Framing

    @discardableResult
    private func applyFrame(_ rect: CGRect, to window: AXUIElement, containerBounds: CGRect? = nil) -> CGSize? {
        // Unminimize if needed
        var minimizedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
           let isMin = minimizedRef as? Bool, isMin {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        var origin = rect.origin
        var size = rect.size

        if let posVal = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        }
        if let sizeVal = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
        }

        // Smart Overflow Guard: read back actual size in case the app enforced a minimum width/height
        var overflowSize: CGSize?
        if let actualSize = sizeAttribute(window, kAXSizeAttribute) {
            let wOverflow = actualSize.width - rect.width > 8
            let hOverflow = actualSize.height - rect.height > 8
            if wOverflow || hOverflow {
                overflowSize = actualSize
                if let bounds = containerBounds {
                    if actualSize.width > rect.width {
                        origin.x = max(bounds.minX, min(origin.x, bounds.maxX - actualSize.width))
                    }
                    if actualSize.height > rect.height {
                        origin.y = max(bounds.minY, min(origin.y, bounds.maxY - actualSize.height))
                    }
                }
            }
        }

        // Re-apply position after size change / overflow clamping
        if let posVal = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        }

        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        return overflowSize
    }

    // MARK: - AX Helpers

    private func standardWindows(of appElement: AXUIElement) -> [AXUIElement] {
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return []
        }

        return windows.filter { win in
            let role = stringAttribute(win, kAXRoleAttribute)
            guard role == kAXWindowRole as String else { return false }
            let subrole = stringAttribute(win, kAXSubroleAttribute)
            if let subrole, subrole != kAXStandardWindowSubrole as String && subrole != kAXDialogSubrole as String {
                return false
            }
            return true
        }
    }

    private func cgWindowBounds(windowNumber: Int) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for info in list {
            if let num = info[kCGWindowNumber as String] as? Int, num == windowNumber,
               let b = info[kCGWindowBounds as String] as? [String: Any],
               let x = b["X"] as? Double, let y = b["Y"] as? Double,
               let w = b["Width"] as? Double, let h = b["Height"] as? Double {
                return CGRect(x: x, y: y, width: w, height: h)
            }
        }
        return nil
    }

    private func windowIdentityKey(_ window: AXUIElement, pid: pid_t) -> String {
        let title = stringAttribute(window, kAXTitleAttribute) ?? ""
        let pos = pointAttribute(window, kAXPositionAttribute) ?? .zero
        let size = sizeAttribute(window, kAXSizeAttribute) ?? .zero
        return "\(pid)-\(title)-\(Int(pos.x))-\(Int(pos.y))-\(Int(size.width))-\(Int(size.height))"
    }

    private func pidForElement(_ element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func pointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let axVal = value else { return nil }
        var pt = CGPoint.zero
        return AXValueGetValue(axVal as! AXValue, .cgPoint, &pt) ? pt : nil
    }

    private func sizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let axVal = value else { return nil }
        var sz = CGSize.zero
        return AXValueGetValue(axVal as! AXValue, .cgSize, &sz) ? sz : nil
    }

    private func findElement(
        in root: AXUIElement,
        maxDepth: Int,
        matching predicate: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        guard maxDepth >= 0 else { return nil }
        if predicate(root) { return root }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }
        for child in children {
            if let match = findElement(in: child, maxDepth: maxDepth - 1, matching: predicate) {
                return match
            }
        }
        return nil
    }

    private func findAllElements(
        in root: AXUIElement,
        maxDepth: Int,
        matching predicate: (AXUIElement) -> Bool
    ) -> [AXUIElement] {
        guard maxDepth >= 0 else { return [] }
        var results: [AXUIElement] = []
        if predicate(root) { results.append(root) }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return results
        }
        for child in children {
            results.append(contentsOf: findAllElements(in: child, maxDepth: maxDepth - 1, matching: predicate))
        }
        return results
    }
}
