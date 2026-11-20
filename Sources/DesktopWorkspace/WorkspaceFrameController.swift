import AppKit
import SwiftUI

@MainActor
final class WorkspaceFrameController: NSObject, ObservableObject, NSWindowDelegate {
    static let headerHeight: CGFloat = 36

    @Published var isDockedToSidebar: Bool = false
    @Published var isMaximized: Bool = false

    let workspaceName: String
    private var window: NSWindow?
    private var savedExpandedFrame: CGRect?
    private var savedPreMaximizeFrame: CGRect?
    private var pendingSyncWorkItem: DispatchWorkItem?

    var onContentRectChanged: ((CGRect) -> Void)?
    var onRealignRequested: (() -> Void)?
    var onSetMinimized: ((Bool) -> Void)?
    var onRaiseMemberWindows: (() -> Void)?
    var onFrameSaved: ((CGRect) -> Void)?
    var onScreenChanged: ((NSScreen) -> Void)?
    var onClosed: (() -> Void)?

    init(workspaceName: String) {
        self.workspaceName = workspaceName
        super.init()
    }

    func show(on screen: NSScreen, initialFrame: CGRect? = nil) -> CGRect {
        let visible = screen.visibleFrame
        let initialRect: CGRect
        if let saved = initialFrame, saved.width >= 360, saved.height >= 260,
           NSScreen.screens.contains(where: { $0.visibleFrame.intersects(saved) }) {
            initialRect = saved
        } else {
            let initialWidth = round(visible.width * 0.92)
            let initialHeight = round(visible.height * 0.92)
            let initialX = round(visible.origin.x + (visible.width - initialWidth) / 2)
            let initialY = round(visible.origin.y + (visible.height - initialHeight) / 2)
            initialRect = CGRect(x: initialX, y: initialY, width: initialWidth, height: initialHeight)
        }

        if let existing = window {
            existing.setFrame(initialRect, display: true)
            existing.orderBack(nil)
            return currentContentAXRect() ?? initialRect
        }

        let win = NSWindow(
            contentRect: initialRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = workspaceName
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 360, height: 260)
        // Transparent & non-opaque so the interior never obscures or blocks clicks on member windows
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.delegate = self

        let rootView = WorkspaceFrameHeaderView(
            controller: self,
            onRealign: { [weak self] in self?.onRealignRequested?() },
            onToggleSidebar: { [weak self] in self?.toggleSidebarDock() },
            onToggleMaximize: { [weak self] in self?.toggleMaximize() }
        )
        win.contentView = NSHostingView(rootView: rootView)
        win.orderFrontRegardless()
        self.window = win

        return currentContentAXRect() ?? initialRect
    }

    func focus() {
        if isDockedToSidebar {
            toggleSidebarDock()
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        pendingSyncWorkItem?.cancel()
        window?.delegate = nil
        window?.close()
        window = nil
    }

    /// Returns the content area below the 36pt header bar in Accessibility top-left screen coordinates.
    func currentContentAXRect() -> CGRect? {
        guard let win = window, !isDockedToSidebar else { return nil }
        let frame = win.frame
        let primaryHeight = NSScreen.screens.first?.frame.height ?? win.screen?.frame.height ?? 1080

        let topOfWindowAX = primaryHeight - frame.maxY
        let contentTopAX = topOfWindowAX + Self.headerHeight
        let contentHeight = max(120, frame.height - Self.headerHeight)

        return CGRect(
            x: round(frame.origin.x),
            y: round(contentTopAX),
            width: round(frame.width),
            height: round(contentHeight)
        )
    }

    func toggleMaximize() {
        guard let win = window else { return }
        if isDockedToSidebar {
            toggleSidebarDock()
        }

        let screen = win.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }

        if isMaximized, let restore = savedPreMaximizeFrame {
            isMaximized = false
            win.setFrame(restore, display: true, animate: true)
        } else {
            savedPreMaximizeFrame = win.frame
            isMaximized = true
            win.setFrame(visible, display: true, animate: true)
        }
        scheduleSync()
    }

    func toggleSidebarDock() {
        guard let win = window else { return }
        let screen = win.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }

        if isDockedToSidebar {
            isDockedToSidebar = false
            win.level = .normal
            if let restore = savedExpandedFrame {
                win.setFrame(restore, display: true, animate: true)
            }
            onSetMinimized?(false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.onRealignRequested?()
            }
        } else {
            savedExpandedFrame = win.frame
            isDockedToSidebar = true
            onSetMinimized?(true)
            let dockRect = CGRect(
                x: visible.origin.x + 8,
                y: round(visible.midY - 90),
                width: 76,
                height: 180
            )
            win.level = .floating
            win.setFrame(dockRect, display: true, animate: true)
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        if !isDockedToSidebar {
            scheduleSync()
        }
    }

    func windowDidResize(_ notification: Notification) {
        if !isDockedToSidebar {
            scheduleSync()
        }
    }

    func windowWillMiniaturize(_ notification: Notification) {
        onSetMinimized?(true)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        onSetMinimized?(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.onRealignRequested?()
        }
    }

    func windowWillClose(_ notification: Notification) {
        pendingSyncWorkItem?.cancel()
        onClosed?()
    }

    private func scheduleSync() {
        pendingSyncWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, let win = self.window, let rect = self.currentContentAXRect() else { return }
            if let screen = win.screen {
                self.onScreenChanged?(screen)
            }
            if !self.isMaximized && !self.isDockedToSidebar {
                self.onFrameSaved?(win.frame)
            }
            self.onContentRectChanged?(rect)
            self.onRaiseMemberWindows?()
        }
        pendingSyncWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: item)
    }
}

private struct WorkspaceFrameHeaderView: View {
    @ObservedObject var controller: WorkspaceFrameController
    let onRealign: () -> Void
    let onToggleSidebar: () -> Void
    let onToggleMaximize: () -> Void

    var body: some View {
        if controller.isDockedToSidebar {
            VStack(spacing: 10) {
                Button(action: onToggleSidebar) {
                    VStack(spacing: 6) {
                        Image(systemName: "sidebar.left")
                            .font(.title3)
                        Text(controller.workspaceName)
                            .font(.caption2.bold())
                            .lineLimit(3)
                            .multilineTextAlignment(.center)
                        Text("Restore")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5)
            )
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Spacer().frame(width: 64) // leave room for traffic lights

                    Image(systemName: "rectangle.3.group")
                        .foregroundStyle(Color.accentColor)
                        .font(.caption)

                    Text(controller.workspaceName)
                        .font(.caption.bold())
                        .lineLimit(1)

                    Spacer()

                    Button(action: onRealign) {
                        Label("Re-Align", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Reset all windows in this frame to their proper alignment (and reopen closed apps)")

                    Button(action: onToggleSidebar) {
                        Image(systemName: "sidebar.left")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Dock this workspace set to the sidebar")

                    Button(action: onToggleMaximize) {
                        Image(systemName: controller.isMaximized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(controller.isMaximized ? "Restore frame size" : "Maximize frame to full screen")
                }
                .padding(.horizontal, 10)
                .frame(height: WorkspaceFrameController.headerHeight)
                .background(.ultraThinMaterial)

                // Completely clear, click-through body with a subtle 2px frame border
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        Rectangle()
                            .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 2)
                    )
            }
        }
    }
}
