# Contributing to Desktop Workspace

Thank you for your interest in contributing to Desktop Workspace!

## Development Setup
1. Clone the repository.
2. Build and run with Swift Package Manager:
   ```bash
   swift build
   ./scripts/build_app.sh
   open build/DesktopWorkspace.app
   ```
3. Or generate an Xcode project using [XcodeGen](https://github.com/yonaskolb/XcodeGen):
   ```bash
   xcodegen generate
   open DesktopWorkspace.xcodeproj
   ```

## Guidelines
- Keep dependencies minimal (pure SwiftUI / AppKit / ApplicationServices).
- Preserve existing comments and docstrings.
- Test window tiling across multiple displays and both with and without "Open on New Desktop" enabled.
- All contributions are licensed under the [MIT License](LICENSE).
