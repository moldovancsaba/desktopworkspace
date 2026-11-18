// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DesktopWorkspace",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DesktopWorkspace", targets: ["DesktopWorkspace"])
    ],
    targets: [
        .executableTarget(
            name: "DesktopWorkspace",
            path: "Sources/DesktopWorkspace"
        )
    ]
)
