# Publishing Checklist (Mac App Store & Direct Distribution)

This repository includes the icon assets (`Resources/Assets.xcassets/AppIcon.appiconset`, `Resources/AppIcon.icns`), `Resources/Info.plist`, entitlements, and `project.yml` needed to package and submit **Desktop Workspace**.

> **Important Technical Note on Mac App Store Sandbox:**
> Every app submitted to the Mac App Store **must** enable App Sandbox (`com.apple.security.app-sandbox = true`, configured in `Resources/DesktopWorkspace-AppStore.entitlements`).
> Under macOS App Sandbox, cross-app Accessibility window manipulation (`AXUIElementSetAttributeValue` on other apps) and Mission Control UI scripting are restricted by the sandbox and closely scrutinized by App Review.
> - If you want **full unrestricted window tiling & Mission Control Space creation**, distribute via **Developer ID + Notarization** outside the Mac App Store (using `Resources/DesktopWorkspace-Direct.entitlements`).
> - If you submit to the **Mac App Store**, test the sandboxed archive thoroughly on your target macOS version and be prepared to explain the Accessibility workflow in App Review notes (or adjust windowing to Apple-approved APIs if requested by App Review).

---

## Option A: Mac App Store Submission (via Xcode)

1. **Install Full Xcode**
   - Ensure full Xcode (not only Command Line Tools) is installed from the Mac App Store and selected:
     ```bash
     sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
     ```

2. **Generate the Xcode Project**
   - Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) and run:
     ```bash
     xcodegen generate
     open DesktopWorkspace.xcodeproj
     ```

3. **Configure Signing & Bundle Identifier**
   - In Xcode → **DesktopWorkspace** target → **Signing & Capabilities**:
     - Select your **Apple Developer Team**.
     - Change `PRODUCT_BUNDLE_IDENTIFIER` from `com.local.DesktopWorkspace` to your unique reverse-DNS identifier (e.g., `com.yourname.DesktopWorkspace`) in both Xcode and `Resources/Info.plist`.
     - Update `NSHumanReadableCopyright` in `Resources/Info.plist`.

4. **Create the App Record in App Store Connect**
   - Go to [App Store Connect](https://appstoreconnect.apple.com) → **My Apps → + → New App** (macOS).
   - Match the exact Bundle ID, set Primary Language, SKU, and Category (**Productivity**).
   - Host `PRIVACY.md` at a public URL and enter it as your Privacy Policy URL.
   - Capture macOS screenshots (1280×800, 1440×900, 2560×1600, or 2880×1800) showing:
     1. Main workspace editor with **3 Columns**
     2. **2 Top + 1 Bottom** layout with apps assigned
     3. Menu bar quick-launch menu

5. **Archive & Upload**
   - In Xcode: **Product → Destination → Any Mac (Apple Silicon, Intel)** → **Product → Archive**.
   - In the Organizer window: **Validate App** → **Distribute App → App Store Connect → Upload**.

---

## Option B: Direct Distribution (Developer ID + Notarization)

For full Accessibility window tiling outside the Mac App Store:

```bash
# 1. Build, sign with Developer ID Application, and package DMG
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
CREATE_DMG=1 \
./scripts/build_app.sh

# 2. Notarize with Apple
xcrun notarytool submit build/DesktopWorkspace.dmg \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "@keychain:AC_PASSWORD" \
  --wait

# 3. Staple the notarization ticket
xcrun stapler staple build/DesktopWorkspace.dmg
```
