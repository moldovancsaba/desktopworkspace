import Foundation
import AppKit

struct AppUpdateInfo: Equatable {
    let version: String
    let releaseNotes: String
    let downloadURL: URL
    let releasePageURL: URL
}

@MainActor
final class UpdateManager: ObservableObject {
    @Published var isChecking: Bool = false
    @Published var isInstalling: Bool = false
    @Published var availableUpdate: AppUpdateInfo?
    @Published var statusText: String?

    private let latestReleaseAPI = URL(string: "https://api.github.com/repos/moldovancsaba/desktopworkspace/releases/latest")!

    var isSupported: Bool {
        // Mac App Store sandboxed builds are updated by the App Store itself.
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil
    }

    var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0.0"
    }

    func checkForUpdates(silentIfUpToDate: Bool = false) async {
        guard isSupported else { return }
        guard !isChecking && !isInstalling else { return }

        isChecking = true
        if !silentIfUpToDate {
            statusText = "Checking for updates…"
        }
        defer { isChecking = false }

        var request = URLRequest(url: latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                if !silentIfUpToDate {
                    statusText = "Could not reach GitHub Releases."
                }
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                return
            }

            let remoteVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            guard isVersion(remoteVersion, newerThan: currentVersion) else {
                availableUpdate = nil
                if !silentIfUpToDate {
                    statusText = "You’re on the latest version (\(currentVersion))."
                }
                return
            }

            let assets = json["assets"] as? [[String: Any]] ?? []
            guard let zipAsset = assets.first(where: {
                let name = ($0["name"] as? String ?? "").lowercased()
                return name.hasSuffix(".zip") && name.contains("desktopworkspace")
            }),
            let urlStr = zipAsset["browser_download_url"] as? String,
            let downloadURL = URL(string: urlStr) else {
                if !silentIfUpToDate {
                    statusText = "Update v\(remoteVersion) found, but no .zip asset was attached."
                }
                return
            }

            let htmlURL = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? latestReleaseAPI
            let notes = (json["body"] as? String) ?? ""

            availableUpdate = AppUpdateInfo(
                version: remoteVersion,
                releaseNotes: notes,
                downloadURL: downloadURL,
                releasePageURL: htmlURL
            )
            statusText = "Update v\(remoteVersion) is available."
        } catch {
            if !silentIfUpToDate {
                statusText = "Update check failed: \(error.localizedDescription)"
            }
        }
    }

    func installUpdate(_ update: AppUpdateInfo) async {
        guard isSupported, !isInstalling else { return }
        isInstalling = true
        statusText = "Downloading v\(update.version)…"

        do {
            let (tempZipURL, response) = try await URLSession.shared.download(from: update.downloadURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                statusText = "Download failed."
                isInstalling = false
                return
            }

            let workDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("DesktopWorkspaceUpdate-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

            let zipCopy = workDir.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: tempZipURL, to: zipCopy)

            statusText = "Extracting v\(update.version)…"
            let extractDir = workDir.appendingPathComponent("extracted", isDirectory: true)
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-x", "-k", zipCopy.path, extractDir.path]
            try ditto.run()
            ditto.waitUntilExit()

            let newAppURL = extractDir.appendingPathComponent("DesktopWorkspace.app")
            guard ditto.terminationStatus == 0, FileManager.default.fileExists(atPath: newAppURL.path) else {
                statusText = "Failed to extract update archive."
                isInstalling = false
                return
            }

            let verify = Process()
            verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            verify.arguments = ["--verify", "--deep", "--strict", newAppURL.path]
            try verify.run()
            verify.waitUntilExit()
            guard verify.terminationStatus == 0 else {
                statusText = "Update signature verification failed."
                isInstalling = false
                return
            }

            let currentAppURL = Bundle.main.bundleURL
            guard FileManager.default.isWritableFile(atPath: currentAppURL.deletingLastPathComponent().path) else {
                statusText = "Move DesktopWorkspace.app to a writable folder (or update via GitHub Releases)."
                isInstalling = false
                return
            }
            let pid = ProcessInfo.processInfo.processIdentifier
            let scriptURL = workDir.appendingPathComponent("apply_update.sh")
            let currentEsc = shellQuote(currentAppURL.path)
            let newEsc = shellQuote(newAppURL.path)
            let workEsc = shellQuote(workDir.path)

            let script = """
            #!/bin/bash
            while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
            rm -rf \(currentEsc)
            mv \(newEsc) \(currentEsc)
            open \(currentEsc)
            rm -rf \(workEsc)
            """
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            statusText = "Restarting into v\(update.version)…"
            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
            launcher.arguments = [scriptURL.path]
            try launcher.run()

            NSApplication.shared.terminate(nil)
        } catch {
            statusText = "Update failed: \(error.localizedDescription)"
            isInstalling = false
        }
    }

    private func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let lhsSplit = lhs.split(separator: "-", maxSplits: 1)
        let rhsSplit = rhs.split(separator: "-", maxSplits: 1)
        let lParts = (lhsSplit.first ?? "").split(separator: ".").compactMap { Int($0) }
        let rParts = (rhsSplit.first ?? "").split(separator: ".").compactMap { Int($0) }
        let count = max(lParts.count, rParts.count)
        for i in 0..<count {
            let l = i < lParts.count ? lParts[i] : 0
            let r = i < rParts.count ? rParts[i] : 0
            if l != r { return l > r }
        }
        // Stable release (no pre-release suffix) is newer than a pre-release of the same version
        return lhsSplit.count == 1 && rhsSplit.count > 1
    }

    private func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
