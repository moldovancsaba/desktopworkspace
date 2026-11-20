import Foundation
import AppKit
import SwiftUI

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
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var items: [RunningWindowItem] = []
        var seenIds = Set<String>()

        for info in windowList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != myPid,
                  let windowNumber = info[kCGWindowNumber as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let w = boundsDict["Width"] as? Double, let h = boundsDict["Height"] as? Double,
                  w >= 120, h >= 120 else {
                continue
            }

            guard let app = NSRunningApplication(processIdentifier: pid),
                  let bundleId = app.bundleIdentifier,
                  let bundleURL = app.bundleURL else {
                continue
            }

            let appName = app.localizedName ?? (info[kCGWindowOwnerName as String] as? String) ?? bundleId
            let title = (info[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let itemId = "\(pid)-\(windowNumber)"
            guard !seenIds.contains(itemId) else { continue }
            seenIds.insert(itemId)

            let icon = app.icon ?? NSWorkspace.shared.icon(forFile: bundleURL.path)
            items.append(RunningWindowItem(
                id: itemId,
                pid: pid,
                appName: appName,
                bundleIdentifier: bundleId,
                bundlePath: bundleURL.path,
                windowTitle: title,
                icon: icon
            ))
        }

        return items.sorted {
            if $0.appName.localizedCaseInsensitiveCompare($1.appName) != .orderedSame {
                return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
            }
            return $0.windowTitle.localizedCaseInsensitiveCompare($1.windowTitle) == .orderedAscending
        }
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
