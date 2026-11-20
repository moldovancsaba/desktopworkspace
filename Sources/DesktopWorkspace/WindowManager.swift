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
        setStatus("Brought “\(session.workspace.name)” to front.", severity: .info)
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

        if let newScreen = targetScreen(for: updated), old.targetDisplayName != updated.targetDisplayName {
            session.screen = newScreen
        }

        // Prune tracked windows for slots that were cleared or removed
        let validSlotIds = Set(updated.preset.slots.map(\.id))
        for slotId in Array(session.trackedSlotWindows.keys) {
            if !validSlotIds.contains(slotId) || updated.slotApps[slotId] == nil {
                session.trackedSlotWindows.removeValue(forKey: slotId)
            } else if old.slotApps[slotId] != updated.slotApps[slotId] {
                // App assignment changed for this slot -> clear old window so realign opens/matches the new one
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
        activeSessions[workspaceId] = session
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
            if let matched = NSScreen.screens.first(where: { $0.localizedName == name }) {
                return matched
            }
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    @discardableResult
    func launchWorkspace(_ workspace: SavedWorkspace, onFrameSaved: ((CGRect) -> Void)? = nil) async -> Bool {
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
        if workspace.createNewDesktop {
            setStatus("Creating a new Desktop…", severity: .info)
            let created = await createAndSwitchToNewDesktop()
            if !created {
                desktopNote = " (arranged on current Desktop — Mission Control '+' not available)"
            } else {
                try? await Task.sleep(nanoseconds: 550_000_000)
            }
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
            controller.onClosed = { [weak self] in
                guard let self else { return }
                if let removed = self.activeSessions.removeValue(forKey: wsId) {
                    removed.autoLockTask?.cancel()
                }
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
                applyFrame(targetRect, to: window)
                arrangedCount += 1
            } else {
                failedApps.append(assignment.name)
            }
        }

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
        lastActiveWorkspaceId = workspaceId

        var usedWindowKeys = Set<String>()
        for (_, win) in session.trackedSlotWindows where isWindowAlive(win) {
            usedWindowKeys.insert(windowIdentityKey(win, pid: pidForElement(win)))
        }

        var alignedCount = 0
        for slot in ws.preset.slots {
            guard let assignment = ws.slotApps[slot.id] else { continue }
            let targetRect: CGRect
            if let containerAX {
                targetRect = slot.rect.accessibilityRect(inAXContainer: containerAX, gap: ws.gap)
            } else {
                targetRect = slot.rect.accessibilityRect(in: screen, gap: ws.gap)
            }

            if let existing = session.trackedSlotWindows[slot.id], isWindowAlive(existing) {
                applyFrame(targetRect, to: existing)
                alignedCount += 1
            } else if let reopened = await openOrFindWindow(
                for: assignment,
                openNewWindowIfRunning: ws.openNewWindowIfRunning,
                excludingWindowKeys: usedWindowKeys
            ) {
                let key = windowIdentityKey(reopened, pid: pidForElement(reopened))
                usedWindowKeys.insert(key)
                session.trackedSlotWindows[slot.id] = reopened
                applyFrame(targetRect, to: reopened)
                alignedCount += 1
            }
        }

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
        for slot in ws.preset.slots {
            guard let win = session.trackedSlotWindows[slot.id] else { continue }
            let rect = slot.rect.accessibilityRect(inAXContainer: container, gap: ws.gap)
            applyFrame(rect, to: win)
        }
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

                for slot in ws.preset.slots {
                    guard let win = session.trackedSlotWindows[slot.id] else { continue }
                    if self.isWindowMinimized(win) { continue }
                    let expected: CGRect
                    if let containerAX {
                        expected = slot.rect.accessibilityRect(inAXContainer: containerAX, gap: ws.gap)
                    } else {
                        expected = slot.rect.accessibilityRect(in: screen, gap: ws.gap)
                    }

                    if let curPos = self.pointAttribute(win, kAXPositionAttribute),
                       let curSize = self.sizeAttribute(win, kAXSizeAttribute) {
                        let drifted = abs(curPos.x - expected.origin.x) > 6 ||
                            abs(curPos.y - expected.origin.y) > 6 ||
                            abs(curSize.width - expected.width) > 6 ||
                            abs(curSize.height - expected.height) > 6
                        if drifted {
                            self.applyFrame(expected, to: win)
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
                    (desc.contains("add desktop") || title.contains("add desktop") || id.contains("add"))
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
        let beforeCount = countDesktopButtons(in: dockElement)
        AXUIElementPerformAction(addBtn, kAXPressAction as CFString)

        // Wait for the new desktop button to appear, then press the last one to switch to it
        try? await Task.sleep(nanoseconds: 350_000_000)
        let desktopButtons = findAllElements(in: dockElement, maxDepth: 6, matching: { el in
            let role = stringAttribute(el, kAXRoleAttribute)
            let desc = (stringAttribute(el, kAXDescriptionAttribute) ?? "").lowercased()
            let title = (stringAttribute(el, kAXTitleAttribute) ?? "").lowercased()
            return role == kAXButtonRole as String &&
                (desc.hasPrefix("desktop ") || title.hasPrefix("desktop "))
        })

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

    private func countDesktopButtons(in root: AXUIElement) -> Int {
        findAllElements(in: root, maxDepth: 6, matching: { el in
            let role = stringAttribute(el, kAXRoleAttribute)
            let desc = (stringAttribute(el, kAXDescriptionAttribute) ?? "").lowercased()
            let title = (stringAttribute(el, kAXTitleAttribute) ?? "").lowercased()
            return role == kAXButtonRole as String &&
                (desc.hasPrefix("desktop ") || title.hasPrefix("desktop "))
        }).count
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

            // If user picked an already-open window (preferredWindowTitle), match it first
            if let preferred = assignment.preferredWindowTitle, !preferred.isEmpty {
                let unused = existingWindows.filter { !excludingWindowKeys.contains(windowIdentityKey($0, pid: pid)) }
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

    private func applyFrame(_ rect: CGRect, to window: AXUIElement) {
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
        // Re-apply position after size change in case app clamped bounds
        if let posVal = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        }

        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
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
