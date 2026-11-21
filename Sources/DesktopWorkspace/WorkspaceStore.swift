import Foundation
import AppKit
import SwiftUI
import ApplicationServices

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var workspaces: [SavedWorkspace] = []
    @Published var selectedWorkspaceId: UUID? {
        didSet {
            if let id = selectedWorkspaceId {
                UserDefaults.standard.set(id.uuidString, forKey: "selectedWorkspaceId")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedWorkspaceId")
            }
        }
    }
    @Published var installedApps: [InstalledApp] = []
    @Published var isLoadingApps: Bool = false

    private let saveURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("DesktopWorkspace", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.saveURL = folder.appendingPathComponent("workspaces.json")

        loadWorkspaces()
        loadInstalledApps()
    }

    var selectedWorkspace: SavedWorkspace? {
        guard let id = selectedWorkspaceId else { return workspaces.first }
        return workspaces.first(where: { $0.id == id })
    }

    func binding(for id: UUID) -> Binding<SavedWorkspace>? {
        guard let idx = workspaces.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.workspaces[idx] },
            set: { newValue in
                self.workspaces[idx] = newValue
                self.saveWorkspaces()
            }
        )
    }

    func addWorkspace() {
        let count = workspaces.count + 1
        let ws = SavedWorkspace(
            name: "Workspace \(count)",
            presetId: "3-columns"
        )
        workspaces.append(ws)
        selectedWorkspaceId = ws.id
        saveWorkspaces()
    }

    func duplicateWorkspace(_ ws: SavedWorkspace) {
        var copy = ws
        copy.id = UUID()
        copy.name = "\(ws.name) Copy"
        workspaces.append(copy)
        selectedWorkspaceId = copy.id
        saveWorkspaces()
    }

    func deleteWorkspace(_ id: UUID) {
        workspaces.removeAll { $0.id == id }
        if selectedWorkspaceId == id {
            selectedWorkspaceId = workspaces.first?.id
        }
        saveWorkspaces()
    }

    func icon(for assignment: AppAssignment) -> NSImage {
        if FileManager.default.fileExists(atPath: assignment.path) {
            return NSWorkspace.shared.icon(forFile: assignment.path)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: assignment.bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    func updateSavedFrame(_ rect: CGRect, for workspaceId: UUID) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspaceId }) else { return }
        workspaces[idx].savedFrame = CodableRect(rect)
        saveWorkspaces()
    }

    func saveWorkspaces() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(workspaces)
            try data.write(to: saveURL, options: .atomic)
        } catch {
            print("Failed to save workspaces: \(error)")
        }
    }

    private func loadWorkspaces() {
        if let data = try? Data(contentsOf: saveURL),
           let decoded = try? JSONDecoder().decode([SavedWorkspace].self, from: data),
           !decoded.isEmpty {
            self.workspaces = decoded
            if let savedIdStr = UserDefaults.standard.string(forKey: "selectedWorkspaceId"),
               let savedId = UUID(uuidString: savedIdStr),
               decoded.contains(where: { $0.id == savedId }) {
                self.selectedWorkspaceId = savedId
            } else {
                self.selectedWorkspaceId = decoded.first?.id
            }
            return
        }

        // Seed starter templates on first run
        let starter1 = SavedWorkspace(
            name: "3 Columns",
            presetId: "3-columns"
        )
        let starter2 = SavedWorkspace(
            name: "2 Top + 1 Bottom",
            presetId: "2-top-1-bottom"
        )
        self.workspaces = [starter1, starter2]
        self.selectedWorkspaceId = starter1.id
        saveWorkspaces()
    }

    func loadInstalledApps() {
        isLoadingApps = true
        Task.detached(priority: .userInitiated) {
            let searchDirs = [
                "/Applications",
                "/System/Applications",
                "/System/Applications/Utilities",
                NSHomeDirectory() + "/Applications"
            ]
            var found: [InstalledApp] = []
            var seenBundleIds = Set<String>()
            let fm = FileManager.default

            for dir in searchDirs {
                let dirURL = URL(fileURLWithPath: dir)
                guard let items = try? fm.contentsOfDirectory(
                    at: dirURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) else { continue }

                for url in items {
                    if url.pathExtension == "app" {
                        if let app = Self.makeInstalledApp(from: url, seen: &seenBundleIds) {
                            found.append(app)
                        }
                    } else {
                        // One level deeper for subfolders like /Applications/Utilities
                        var isDir: ObjCBool = false
                        if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                            if let subItems = try? fm.contentsOfDirectory(
                                at: url,
                                includingPropertiesForKeys: nil,
                                options: [.skipsHiddenFiles]
                            ) {
                                for sub in subItems where sub.pathExtension == "app" {
                                    if let app = Self.makeInstalledApp(from: sub, seen: &seenBundleIds) {
                                        found.append(app)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            let sorted = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            await MainActor.run {
                self.installedApps = sorted
                self.isLoadingApps = false
            }
        }
    }

    func loadRunningWindows() -> [RunningWindowItem] {
        let myPid = ProcessInfo.processInfo.processIdentifier
        let regularApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular &&
            !$0.isTerminated &&
            $0.processIdentifier != myPid &&
            $0.bundleIdentifier != nil &&
            $0.bundleURL != nil
        }

        // Map CGWindow bounds for windowNumber lookup
        let cgList = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        var cgByPid: [pid_t: [(num: Int, bounds: CGRect, layer: Int, alpha: Double, onScreen: Bool, name: String)]] = [:]
        for info in cgList {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let num = info[kCGWindowNumber as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let x = boundsDict["X"] as? Double, let y = boundsDict["Y"] as? Double,
                  let w = boundsDict["Width"] as? Double, let h = boundsDict["Height"] as? Double else {
                continue
            }
            let alpha = (info[kCGWindowAlpha as String] as? Double) ?? 1.0
            let onScreen = (info[kCGWindowIsOnscreen as String] as? Bool) ?? false
            let name = (info[kCGWindowName as String] as? String) ?? ""
            cgByPid[pid, default: []].append((num, CGRect(x: x, y: y, width: w, height: h), layer, alpha, onScreen, name))
        }

        var items: [RunningWindowItem] = []

        if AXIsProcessTrusted() {
            for app in regularApps {
                guard let bundleId = app.bundleIdentifier, let bundleURL = app.bundleURL else { continue }
                let pid = app.processIdentifier
                let appName = app.localizedName ?? bundleURL.deletingPathExtension().lastPathComponent
                let icon = app.icon ?? NSWorkspace.shared.icon(forFile: bundleURL.path)
                let appEl = AXUIElementCreateApplication(pid)

                var windowsRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                      let axWindows = windowsRef as? [AXUIElement] else {
                    continue
                }

                var winIdx = 0
                for win in axWindows {
                    guard axString(win, kAXRoleAttribute) == kAXWindowRole as String else { continue }
                    if let subrole = axString(win, kAXSubroleAttribute),
                       subrole != kAXStandardWindowSubrole as String {
                        continue
                    }

                    guard let pos = axPoint(win, kAXPositionAttribute),
                          let sz = axSize(win, kAXSizeAttribute),
                          sz.width >= 150, sz.height >= 150 else {
                        continue
                    }

                    winIdx += 1
                    let isMin = axBool(win, kAXMinimizedAttribute) ?? false
                    let rawTitle = (axString(win, kAXTitleAttribute) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let displayTitle: String
                    if !rawTitle.isEmpty {
                        displayTitle = isMin ? "\(rawTitle) (Minimized)" : rawTitle
                    } else {
                        displayTitle = "Window #\(winIdx) (\(Int(sz.width))×\(Int(sz.height)))\(isMin ? " (Minimized)" : "")"
                    }

                    // Match CGWindowNumber by closest bounds
                    let axRect = CGRect(origin: pos, size: sz)
                    let matchedCG = cgByPid[pid]?.min(by: { a, b in
                        let da = abs(a.bounds.origin.x - axRect.origin.x) + abs(a.bounds.origin.y - axRect.origin.y) + abs(a.bounds.width - axRect.width)
                        let db = abs(b.bounds.origin.x - axRect.origin.x) + abs(b.bounds.origin.y - axRect.origin.y) + abs(b.bounds.width - axRect.width)
                        return da < db
                    })
                    let winNum = matchedCG?.num ?? (Int(pid) * 1000 + winIdx)

                    items.append(RunningWindowItem(
                        id: "\(pid)-\(winNum)-\(winIdx)",
                        pid: pid,
                        windowNumber: winNum,
                        appName: appName,
                        bundleIdentifier: bundleId,
                        bundlePath: bundleURL.path,
                        windowTitle: displayTitle,
                        icon: icon
                    ))
                }
            }
        } else {
            // Fallback when Accessibility is not yet granted: visible on-screen windows of regular GUI apps only
            let regularByPid = Dictionary(uniqueKeysWithValues: regularApps.map { ($0.processIdentifier, $0) })
            for (pid, windows) in cgByPid {
                guard let app = regularByPid[pid],
                      let bundleId = app.bundleIdentifier,
                      let bundleURL = app.bundleURL else { continue }
                let appName = app.localizedName ?? bundleURL.deletingPathExtension().lastPathComponent
                let icon = app.icon ?? NSWorkspace.shared.icon(forFile: bundleURL.path)

                for (idx, wInfo) in windows.enumerated() where wInfo.onScreen && wInfo.alpha > 0 && wInfo.bounds.width >= 150 && wInfo.bounds.height >= 150 {
                    let title = wInfo.name.isEmpty
                        ? "Window #\(idx + 1) (\(Int(wInfo.bounds.width))×\(Int(wInfo.bounds.height)))"
                        : wInfo.name
                    items.append(RunningWindowItem(
                        id: "\(pid)-\(wInfo.num)",
                        pid: pid,
                        windowNumber: wInfo.num,
                        appName: appName,
                        bundleIdentifier: bundleId,
                        bundlePath: bundleURL.path,
                        windowTitle: title,
                        icon: icon
                    ))
                }
            }
        }

        return items.sorted {
            if $0.appName.localizedCaseInsensitiveCompare($1.appName) != .orderedSame {
                return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
            }
            return $0.windowTitle.localizedCaseInsensitiveCompare($1.windowTitle) == .orderedAscending
        }
    }

    /// Captures all currently visible standard windows on the main/active screen into a new Custom workspace.
    @discardableResult
    func captureCurrentDesktop() -> SavedWorkspace? {
        guard AXIsProcessTrusted() else { return nil }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let visible = screen.visibleFrame
        let containerTopAX = primaryHeight - (visible.origin.y + visible.height)
        let containerAX = CGRect(x: visible.origin.x, y: containerTopAX, width: visible.width, height: visible.height)

        let myPid = ProcessInfo.processInfo.processIdentifier
        let regularApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != myPid && $0.bundleIdentifier != nil && $0.bundleURL != nil
        }

        var slots: [LayoutSlot] = []
        var slotApps: [Int: AppAssignment] = [:]
        var slotIndex = 0

        for app in regularApps {
            guard let bundleId = app.bundleIdentifier, let bundleURL = app.bundleURL else { continue }
            let pid = app.processIdentifier
            let appName = app.localizedName ?? bundleURL.deletingPathExtension().lastPathComponent
            let appEl = AXUIElementCreateApplication(pid)

            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let axWindows = windowsRef as? [AXUIElement] else {
                continue
            }

            for win in axWindows {
                guard axString(win, kAXRoleAttribute) == kAXWindowRole as String else { continue }
                if let sub = axString(win, kAXSubroleAttribute), sub != kAXStandardWindowSubrole as String { continue }
                if axBool(win, kAXMinimizedAttribute) == true { continue }
                guard let pos = axPoint(win, kAXPositionAttribute),
                      let sz = axSize(win, kAXSizeAttribute),
                      sz.width >= 150, sz.height >= 150 else { continue }

                let winRect = CGRect(origin: pos, size: sz)
                let clipped = winRect.intersection(containerAX)
                guard !clipped.isNull, clipped.width >= 100, clipped.height >= 100 else { continue }

                let norm = NormalizedRect(
                    x: max(0, min(1, (clipped.origin.x - containerAX.origin.x) / containerAX.width)),
                    y: max(0, min(1, (clipped.origin.y - containerAX.origin.y) / containerAX.height)),
                    width: max(0.1, min(1, clipped.width / containerAX.width)),
                    height: max(0.1, min(1, clipped.height / containerAX.height))
                )

                let rawTitle = (axString(win, kAXTitleAttribute) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                slots.append(LayoutSlot(id: slotIndex, label: appName, rect: norm))
                slotApps[slotIndex] = AppAssignment(
                    bundleIdentifier: bundleId,
                    name: appName,
                    path: bundleURL.path,
                    preferredWindowTitle: rawTitle.isEmpty ? nil : rawTitle
                )
                slotIndex += 1
            }
        }

        guard !slots.isEmpty else { return nil }
        let ws = SavedWorkspace(
            name: "Captured \(workspaces.count + 1)",
            presetId: "custom",
            customSlots: slots,
            slotApps: slotApps,
            spaceBehavior: .currentDesktop
        )
        workspaces.append(ws)
        selectedWorkspaceId = ws.id
        saveWorkspaces()
        return ws
    }

    private func axString(_ el: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private func axBool(_ el: AXUIElement, _ attr: String) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success else { return nil }
        return ref as? Bool
    }

    private func axPoint(_ el: AXUIElement, _ attr: String) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success, let v = ref else { return nil }
        var pt = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &pt) ? pt : nil
    }

    private func axSize(_ el: AXUIElement, _ attr: String) -> CGSize? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success, let v = ref else { return nil }
        var sz = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &sz) ? sz : nil
    }

    nonisolated private static func makeInstalledApp(from url: URL, seen: inout Set<String>) -> InstalledApp? {
        guard let bundle = Bundle(url: url),
              let bundleId = bundle.bundleIdentifier else {
            return nil
        }
        guard !seen.contains(bundleId) else { return nil }
        seen.insert(bundleId)

        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: url.path)

        return InstalledApp(
            name: displayName,
            bundleIdentifier: bundleId,
            path: url.path,
            icon: icon
        )
    }
}
