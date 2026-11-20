import AppKit
import SwiftUI

struct ScreenshotScene: View {
    let headline: String
    let subheadline: String
    let activePreset: String
    let slots: [(String, Double, Double, Double, Double, String?)]
    let modeLabel: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.11, blue: 0.22),
                    Color(red: 0.12, green: 0.18, blue: 0.34),
                    Color(red: 0.08, green: 0.12, blue: 0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 36) {
                VStack(spacing: 12) {
                    Text(headline)
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subheadline)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                }
                .padding(.top, 56)

                // Mockup macOS App Window
                HStack(spacing: 0) {
                    // Sidebar
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            Circle().fill(Color.red).frame(width: 14, height: 14)
                            Circle().fill(Color.yellow).frame(width: 14, height: 14)
                            Circle().fill(Color.green).frame(width: 14, height: 14)
                        }
                        .padding(.bottom, 12)

                        Text("SAVED WORKSPACES")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))

                        sidebarRow("3 Columns", "3 Columns • 3/3 apps", selected: activePreset == "3 Columns")
                        sidebarRow("2 Top + 1 Bottom", "2 Top + 1 Bottom • 3/3 apps", selected: activePreset == "2 Top + 1 Bottom")
                        sidebarRow("Dev Framed Set", "1 Left + 2 Right • 3/3 apps", selected: activePreset == "1 Left + 2 Right")

                        Spacer()

                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundStyle(.green)
                            Text("Accessibility Ready")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(8)
                    }
                    .padding(24)
                    .frame(width: 320)
                    .background(Color(red: 0.11, green: 0.13, blue: 0.17))

                    Divider().background(Color.white.opacity(0.12))

                    // Detail Area
                    VStack(alignment: .leading, spacing: 24) {
                        HStack {
                            Text(activePreset)
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(.white)
                            Spacer()
                            HStack(spacing: 12) {
                                Label("Re-Align", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.12))
                                    .cornerRadius(8)

                                Label("Launch Workspace", systemImage: "play.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(Color.accentColor)
                                    .cornerRadius(8)
                            }
                        }

                        // Layout Canvas
                        GeometryReader { geo in
                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(red: 0.08, green: 0.09, blue: 0.12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1.5)
                                    )

                                ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                                    let (label, x, y, w, h, appName) = slot
                                    let pad: CGFloat = 10
                                    let rw = w * geo.size.width - pad * 2
                                    let rh = h * geo.size.height - pad * 2
                                    let rx = x * geo.size.width + pad
                                    let ry = y * geo.size.height + pad

                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.accentColor.opacity(0.16))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 2)
                                            )

                                        VStack(spacing: 10) {
                                            Image(systemName: "app.badge.checkmark.fill")
                                                .font(.system(size: 42))
                                                .foregroundStyle(Color.accentColor)
                                            Text(appName ?? "Choose App")
                                                .font(.system(size: 22, weight: .semibold))
                                                .foregroundStyle(.white)
                                            Text(label)
                                                .font(.system(size: 15))
                                                .foregroundStyle(.white.opacity(0.65))
                                        }
                                    }
                                    .frame(width: rw, height: rh)
                                    .offset(x: rx, y: ry)
                                }
                            }
                        }
                        .frame(height: 520)

                        // Options Bar
                        HStack(spacing: 28) {
                            Text("Mode: \(modeLabel)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.accentColor.opacity(0.25))
                                .cornerRadius(8)

                            Label("Open on New Desktop", systemImage: "checkmark.square.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white.opacity(0.85))
                            Label("Auto-Lock Alignment", systemImage: "checkmark.square.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white.opacity(0.85))
                            Spacer()
                            Text("Gap: 4 px")
                                .font(.system(size: 16))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(18)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(12)
                    }
                    .padding(32)
                    .background(Color(red: 0.14, green: 0.16, blue: 0.21))
                }
                .frame(width: 1960, height: 1080)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.55), radius: 40, y: 20)

                Spacer()
            }
        }
        .frame(width: 2560, height: 1600)
    }

    private func sidebarRow(_ title: String, _ sub: String, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
            Text(sub)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.accentColor.opacity(0.32) : Color.clear)
        .cornerRadius(10)
    }
}

@MainActor
func render(_ view: some View, to path: String) throws {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1.0
    guard let nsImage = renderer.nsImage,
          let tiff = nsImage.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to render \(path)")
    }
    try png.write(to: URL(fileURLWithPath: path))
    print("Wrote \(path)")
}

@main
struct Gen {
    static func main() async throws {
        let outDir = "/Users/Shared/Projects/desktopworkspace/docs/screenshots"
        try render(
            ScreenshotScene(
                headline: "3-Column Tiled Workspaces in One Click",
                subheadline: "Assign your favorite apps and launch them edge-to-edge on a fresh Desktop",
                activePreset: "3 Columns",
                slots: [
                    ("Left", 0, 0, 1.0/3.0, 1.0, "Safari"),
                    ("Center", 1.0/3.0, 0, 1.0/3.0, 1.0, "Notes"),
                    ("Right", 2.0/3.0, 0, 1.0/3.0, 1.0, "Terminal")
                ],
                modeLabel: "Full Screen Tiled"
            ),
            to: "\(outDir)/1_three_columns.png"
        )
        try render(
            ScreenshotScene(
                headline: "Flexible Multi-Window Layouts",
                subheadline: "2 Top + 1 Bottom, 2×2 Grid, 1 Left + 2 Right, and more built-in presets",
                activePreset: "2 Top + 1 Bottom",
                slots: [
                    ("Top Left", 0, 0, 0.5, 0.5, "Messages"),
                    ("Top Right", 0.5, 0, 0.5, 0.5, "Calendar"),
                    ("Bottom Wide", 0, 0.5, 1.0, 0.5, "Xcode")
                ],
                modeLabel: "Full Screen Tiled"
            ),
            to: "\(outDir)/2_two_top_one_bottom.png"
        )
        try render(
            ScreenshotScene(
                headline: "Framed Group, Re-Align & Auto-Lock",
                subheadline: "Move or resize your entire app set together, dock to sidebar, or snap back anytime",
                activePreset: "1 Left + 2 Right",
                slots: [
                    ("Left Main", 0, 0, 0.5, 1.0, "Xcode"),
                    ("Top Right", 0.5, 0, 0.5, 0.5, "Safari"),
                    ("Bottom Right", 0.5, 0.5, 0.5, 0.5, "Terminal")
                ],
                modeLabel: "Framed Group"
            ),
            to: "\(outDir)/3_framed_group.png"
        )
    }
}
