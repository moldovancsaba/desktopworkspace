import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum PickerSourceTab: String, CaseIterable, Identifiable {
    case installed = "Installed Apps"
    case running = "Open Windows"
    var id: String { rawValue }
}

struct AppPickerSheet: View {
    let slot: LayoutSlot
    let apps: [InstalledApp]
    let isLoading: Bool
    let runningWindowsProvider: () -> [RunningWindowItem]
    let onPick: (AppAssignment) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedTab: PickerSourceTab = .installed
    @State private var runningWindows: [RunningWindowItem] = []

    private var filteredApps: [InstalledApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredWindows: [RunningWindowItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return runningWindows }
        return runningWindows.filter {
            $0.appName.localizedCaseInsensitiveContains(query) ||
            $0.windowTitle.localizedCaseInsensitiveContains(query) ||
            $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose App for \(slot.label)")
                        .font(.headline)
                    Text("Pick an installed app or an already-open window")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Browse…") {
                    browseForApp()
                }
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            HStack(spacing: 8) {
                Picker("", selection: $selectedTab) {
                    ForEach(PickerSourceTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                if selectedTab == .running {
                    Button {
                        runningWindows = runningWindowsProvider()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .help("Refresh open windows")
                }
            }
            .padding(.horizontal)
            .padding(.top, 10)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(selectedTab == .installed ? "Search apps…" : "Search open windows…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.vertical, 10)

            if selectedTab == .installed {
                installedAppsList
            } else {
                runningWindowsList
            }
        }
        .frame(width: 460, height: 520)
        .onAppear {
            runningWindows = runningWindowsProvider()
        }
    }

    @ViewBuilder
    private var installedAppsList: some View {
        if isLoading && apps.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("Scanning installed apps…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredApps.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(filteredApps) { app in
                Button {
                    onPick(app.toAssignment())
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(nsImage: app.icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(app.bundleIdentifier)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var runningWindowsList: some View {
        if filteredWindows.isEmpty {
            ContentUnavailableView(
                "No Matching Open Windows",
                systemImage: "macwindow",
                description: Text("Open the app windows you want to arrange, then click Refresh.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(filteredWindows) { item in
                Button {
                    onPick(item.toAssignment())
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(nsImage: item.icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.appName)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(item.windowTitle.isEmpty ? item.bundleIdentifier : item.windowTitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
    }

    private func browseForApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url,
           let bundle = Bundle(url: url),
           let bundleId = bundle.bundleIdentifier {
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            onPick(AppAssignment(bundleIdentifier: bundleId, name: name, path: url.path))
            dismiss()
        }
    }
}
