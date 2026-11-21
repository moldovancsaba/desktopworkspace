import Foundation
import AppKit

enum SpaceBehavior: String, Codable, CaseIterable, Identifiable {
    case currentDesktop = "current"
    case newMissionControlDesktop = "newDesktop"
    case virtualSwitch = "virtual"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentDesktop: return "Current Desktop"
        case .newMissionControlDesktop: return "New Desktop"
        case .virtualSwitch: return "Virtual Switch"
        }
    }

    var helpText: String {
        switch self {
        case .currentDesktop: return "Arranges windows on the current Desktop Space"
        case .newMissionControlDesktop: return "Creates and switches to a new Mission Control Desktop before opening apps"
        case .virtualSwitch: return "Instantly hides other virtual workspaces and reveals this one on the current Space"
        }
    }
}

enum WorkspaceMode: String, Codable, CaseIterable, Identifiable {
    case tiled = "tiled"
    case framed = "framed"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tiled: return "Full Screen Tiled"
        case .framed: return "Framed Group"
        }
    }

    var subtitle: String {
        switch self {
        case .tiled: return "Fills the entire desktop"
        case .framed: return "Resizable frame you can move, maximize, or dock to sidebar"
        }
    }
}

/// Normalized rectangle in top-left screen coordinates (0.0...1.0).
struct NormalizedRect: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    /// Converts this normalized rect into an Accessibility-compatible screen rect
    /// (origin at top-left of the primary display) inside `screen.visibleFrame`.
    func accessibilityRect(in screen: NSScreen, gap: Double) -> CGRect {
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let visible = screen.visibleFrame
        let topY = primaryScreenHeight - (visible.origin.y + visible.height)
        let containerAX = CGRect(x: visible.origin.x, y: topY, width: visible.width, height: visible.height)
        return accessibilityRect(inAXContainer: containerAX, gap: gap)
    }

    /// Converts this normalized rect into an Accessibility-compatible rect inside an arbitrary
    /// top-left-origin container rect (such as a Framed Group window's content area).
    func accessibilityRect(inAXContainer container: CGRect, gap: Double) -> CGRect {
        let rawX = container.origin.x + x * container.width
        let rawY = container.origin.y + y * container.height
        let rawW = width * container.width
        let rawH = height * container.height

        let halfGap = gap / 2.0
        let leftInset = x > 0.001 ? halfGap : gap
        let rightInset = (x + width) < 0.999 ? halfGap : gap
        let topInset = y > 0.001 ? halfGap : gap
        let bottomInset = (y + height) < 0.999 ? halfGap : gap

        return CGRect(
            x: round(rawX + leftInset),
            y: round(rawY + topInset),
            width: max(100, round(rawW - leftInset - rightInset)),
            height: max(100, round(rawH - topInset - bottomInset))
        )
    }
}

struct LayoutSlot: Identifiable, Codable, Hashable {
    let id: Int
    var label: String
    var rect: NormalizedRect
}

struct LayoutPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let slots: [LayoutSlot]

    static let allPresets: [LayoutPreset] = [
        LayoutPreset(
            id: "3-columns",
            name: "3 Columns",
            slots: [
                LayoutSlot(id: 0, label: "Left", rect: NormalizedRect(x: 0, y: 0, width: 1.0/3.0, height: 1)),
                LayoutSlot(id: 1, label: "Center", rect: NormalizedRect(x: 1.0/3.0, y: 0, width: 1.0/3.0, height: 1)),
                LayoutSlot(id: 2, label: "Right", rect: NormalizedRect(x: 2.0/3.0, y: 0, width: 1.0/3.0, height: 1))
            ]
        ),
        LayoutPreset(
            id: "2-top-1-bottom",
            name: "2 Top + 1 Bottom",
            slots: [
                LayoutSlot(id: 0, label: "Top Left", rect: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)),
                LayoutSlot(id: 1, label: "Top Right", rect: NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 0.5)),
                LayoutSlot(id: 2, label: "Bottom Wide", rect: NormalizedRect(x: 0, y: 0.5, width: 1.0, height: 0.5))
            ]
        ),
        LayoutPreset(
            id: "1-top-2-bottom",
            name: "1 Top + 2 Bottom",
            slots: [
                LayoutSlot(id: 0, label: "Top Wide", rect: NormalizedRect(x: 0, y: 0, width: 1.0, height: 0.5)),
                LayoutSlot(id: 1, label: "Bottom Left", rect: NormalizedRect(x: 0, y: 0.5, width: 0.5, height: 0.5)),
                LayoutSlot(id: 2, label: "Bottom Right", rect: NormalizedRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
            ]
        ),
        LayoutPreset(
            id: "2-columns",
            name: "2 Columns",
            slots: [
                LayoutSlot(id: 0, label: "Left", rect: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)),
                LayoutSlot(id: 1, label: "Right", rect: NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1))
            ]
        ),
        LayoutPreset(
            id: "1-left-2-right",
            name: "1 Left + 2 Right",
            slots: [
                LayoutSlot(id: 0, label: "Left Main", rect: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)),
                LayoutSlot(id: 1, label: "Top Right", rect: NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 0.5)),
                LayoutSlot(id: 2, label: "Bottom Right", rect: NormalizedRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
            ]
        ),
        LayoutPreset(
            id: "2-left-1-right",
            name: "2 Left + 1 Right",
            slots: [
                LayoutSlot(id: 0, label: "Top Left", rect: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)),
                LayoutSlot(id: 1, label: "Bottom Left", rect: NormalizedRect(x: 0, y: 0.5, width: 0.5, height: 0.5)),
                LayoutSlot(id: 2, label: "Right Main", rect: NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1))
            ]
        ),
        LayoutPreset(
            id: "2x2-grid",
            name: "2×2 Grid",
            slots: [
                LayoutSlot(id: 0, label: "Top Left", rect: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)),
                LayoutSlot(id: 1, label: "Top Right", rect: NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 0.5)),
                LayoutSlot(id: 2, label: "Bottom Left", rect: NormalizedRect(x: 0, y: 0.5, width: 0.5, height: 0.5)),
                LayoutSlot(id: 3, label: "Bottom Right", rect: NormalizedRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
            ]
        ),
        LayoutPreset(
            id: "3-rows",
            name: "3 Rows",
            slots: [
                LayoutSlot(id: 0, label: "Top", rect: NormalizedRect(x: 0, y: 0, width: 1, height: 1.0/3.0)),
                LayoutSlot(id: 1, label: "Middle", rect: NormalizedRect(x: 0, y: 1.0/3.0, width: 1, height: 1.0/3.0)),
                LayoutSlot(id: 2, label: "Bottom", rect: NormalizedRect(x: 0, y: 2.0/3.0, width: 1, height: 1.0/3.0))
            ]
        ),
        LayoutPreset(
            id: "full-screen",
            name: "Full Screen",
            slots: [
                LayoutSlot(id: 0, label: "Full", rect: NormalizedRect(x: 0, y: 0, width: 1, height: 1))
            ]
        )
    ]

    static func preset(for id: String) -> LayoutPreset {
        allPresets.first(where: { $0.id == id }) ?? allPresets[0]
    }
}

struct AppAssignment: Codable, Hashable {
    var bundleIdentifier: String
    var name: String
    var path: String
    var preferredWindowTitle: String? = nil
    var preferredWindowNumber: Int? = nil
}

struct RunningWindowItem: Identifiable, Hashable {
    let id: String
    let pid: pid_t
    let windowNumber: Int
    let appName: String
    let bundleIdentifier: String
    let bundlePath: String
    let windowTitle: String
    let icon: NSImage

    func toAssignment() -> AppAssignment {
        AppAssignment(
            bundleIdentifier: bundleIdentifier,
            name: appName,
            path: bundlePath,
            preferredWindowTitle: windowTitle.isEmpty ? nil : windowTitle,
            preferredWindowNumber: windowNumber
        )
    }

    static func == (lhs: RunningWindowItem, rhs: RunningWindowItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct InstalledApp: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let bundleIdentifier: String
    let path: String
    let icon: NSImage

    func toAssignment() -> AppAssignment {
        AppAssignment(bundleIdentifier: bundleIdentifier, name: name, path: path)
    }

    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool {
        lhs.path == rhs.path
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
}

struct CodableRect: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.width
        self.height = rect.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct SavedWorkspace: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var presetId: String
    var customSlots: [LayoutSlot]? = nil
    /// Keyed by slot index (0, 1, 2, ...)
    var slotApps: [Int: AppAssignment] = [:]
    var gap: Double = 0
    var spaceBehavior: SpaceBehavior = .newMissionControlDesktop
    var openNewWindowIfRunning: Bool = true
    var mode: WorkspaceMode = .tiled
    var autoLockLayout: Bool = false
    var targetDisplayName: String? = nil
    var savedFrame: CodableRect? = nil

    var effectivePreset: LayoutPreset {
        if let customSlots, !customSlots.isEmpty {
            return LayoutPreset(id: "custom", name: "Captured", slots: customSlots)
        }
        return LayoutPreset.preset(for: presetId)
    }

    var preset: LayoutPreset {
        effectivePreset
    }

    enum CodingKeys: String, CodingKey {
        case id, name, presetId, customSlots, slotApps, gap, createNewDesktop, spaceBehavior, openNewWindowIfRunning, mode, autoLockLayout, targetDisplayName, savedFrame
    }

    init(
        id: UUID = UUID(),
        name: String,
        presetId: String,
        customSlots: [LayoutSlot]? = nil,
        slotApps: [Int: AppAssignment] = [:],
        gap: Double = 0,
        spaceBehavior: SpaceBehavior = .newMissionControlDesktop,
        openNewWindowIfRunning: Bool = true,
        mode: WorkspaceMode = .tiled,
        autoLockLayout: Bool = false,
        targetDisplayName: String? = nil,
        savedFrame: CodableRect? = nil
    ) {
        self.id = id
        self.name = name
        self.presetId = presetId
        self.customSlots = customSlots
        self.slotApps = slotApps
        self.gap = gap
        self.spaceBehavior = spaceBehavior
        self.openNewWindowIfRunning = openNewWindowIfRunning
        self.mode = mode
        self.autoLockLayout = autoLockLayout
        self.targetDisplayName = targetDisplayName
        self.savedFrame = savedFrame
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        presetId = try c.decode(String.self, forKey: .presetId)
        customSlots = try c.decodeIfPresent([LayoutSlot].self, forKey: .customSlots)
        slotApps = try c.decodeIfPresent([Int: AppAssignment].self, forKey: .slotApps) ?? [:]
        gap = try c.decodeIfPresent(Double.self, forKey: .gap) ?? 0
        if let behavior = try c.decodeIfPresent(SpaceBehavior.self, forKey: .spaceBehavior) {
            spaceBehavior = behavior
        } else {
            let legacyNewDesktop = try c.decodeIfPresent(Bool.self, forKey: .createNewDesktop) ?? true
            spaceBehavior = legacyNewDesktop ? .newMissionControlDesktop : .currentDesktop
        }
        openNewWindowIfRunning = try c.decodeIfPresent(Bool.self, forKey: .openNewWindowIfRunning) ?? true
        mode = try c.decodeIfPresent(WorkspaceMode.self, forKey: .mode) ?? .tiled
        autoLockLayout = try c.decodeIfPresent(Bool.self, forKey: .autoLockLayout) ?? false
        targetDisplayName = try c.decodeIfPresent(String.self, forKey: .targetDisplayName)
        savedFrame = try c.decodeIfPresent(CodableRect.self, forKey: .savedFrame)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(presetId, forKey: .presetId)
        try c.encodeIfPresent(customSlots, forKey: .customSlots)
        try c.encode(slotApps, forKey: .slotApps)
        try c.encode(gap, forKey: .gap)
        try c.encode(spaceBehavior, forKey: .spaceBehavior)
        try c.encode(openNewWindowIfRunning, forKey: .openNewWindowIfRunning)
        try c.encode(mode, forKey: .mode)
        try c.encode(autoLockLayout, forKey: .autoLockLayout)
        try c.encodeIfPresent(targetDisplayName, forKey: .targetDisplayName)
        try c.encodeIfPresent(savedFrame, forKey: .savedFrame)
    }
}
