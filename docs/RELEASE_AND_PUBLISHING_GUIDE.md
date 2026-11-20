# Desktop Workspace — Complete Build, Signing, Notarization & Publishing Guide

This document records the exact end-to-end process used to build, sign, notarize, publish on GitHub, and submit **Desktop Workspace** (`com.moldovancsaba.DesktopWorkspace`) to the **Mac App Store**, along with a repeatable task list for future releases.

---

## 1. Distribution Channels

| Channel | Signing Certificate | Entitlements | Output Artifacts |
| :--- | :--- | :--- | :--- |
| **Direct / GitHub Releases** | `Developer ID Application` (`GZE5C5C4L8`) | `Resources/DesktopWorkspace-Direct.entitlements` (non-sandboxed, full Accessibility window tiling) | `.app`, `.dmg`, `.zip` (notarized & stapled) |
| **Mac App Store** | `Apple Distribution` + `Mac Installer Distribution` | `Resources/DesktopWorkspace-AppStore.entitlements` (`app-sandbox = true`) | `.xcarchive` → App Store Connect `.pkg` |

---

## 2. One-Time Setup Checklist (Completed for `v1.0.0`)

### A. Apple Developer Portal (`developer.apple.com`)
1. **App ID:** Registered explicit Bundle ID `com.moldovancsaba.DesktopWorkspace` (`Desktop Workspace`).
2. **CSR & Private Key:** Generated 2048-bit RSA key (`~/.apple-csr/apple_dev.key`) + CSR (`CertificateSigningRequest.certSigningRequest`) and imported the private key into `~/Library/Keychains/login.keychain-db`.
3. **Certificates Created & Installed:**
   - **Apple Development** (`272R3SY2XG`)
   - **Apple Distribution** (`GZE5C5C4L8`) — for Mac App Store app signing
   - **Mac Installer Distribution** (`2J26Q5ULAG`) — for Mac App Store `.pkg` signing
   - **Developer ID Application** (`GZE5C5C4L8`) — for direct `.app` / `.dmg` / `.zip` signing
   - **Apple Intermediate CAs:** Installed `AppleWWDRCAG3.cer` and `DeveloperIDG2CA.cer` into `login.keychain-db` so `security find-identity -v -p codesigning` validates all chains.
4. **Provisioning Profile:**
   - Created Mac App Store profile `DesktopWorkspace Mac App Store` (`Z7H257V4R8`) for `GZE5C5C4L8.com.moldovancsaba.DesktopWorkspace`.
   - Installed into `~/Library/MobileDevice/Provisioning Profiles/<UUID>.provisionprofile` and `~/Library/Developer/Xcode/UserData/Provisioning Profiles/<UUID>.provisionprofile`.

### B. App Store Connect (`appstoreconnect.apple.com`)
1. **API Key (for CLI Notarization & Upload):**
   - Created `DesktopWorkspace Notarization` (`Key ID: J29633LL65`, `Issuer ID: 50da2e06-9a19-4a5f-a183-13f82dff3137`, Role: `Developer`).
   - Saved to `~/.appstoreconnect/private_keys/AuthKey_J29633LL65.p8` (`chmod 600`).
2. **App Record (`Apple ID: 6837278519`):**
   - Name: `Desktop Workspace`, Platform: `macOS`, SKU: `DESKTOPWORKSPACE001`.
   - Category: `Productivity`, Price: `$0.00 (Free)` across 175 countries/regions.
   - Privacy Policy: `https://github.com/moldovancsaba/desktopworkspace/blob/main/PRIVACY.md` (`Data Not Collected`, published).
   - Age Rating: `4+`, Content Rights: `No third-party content`.
   - Compliance: China Mainland AIGC (`No`), China Mainland Security Assessment (`No`), EU Digital Services Act (`Non-trader`, Active).
   - Screenshots: 3 × `2560×1600` PNGs generated via `scripts/generate_screenshots.swift` in `docs/screenshots/`.

---

## 3. Repeatable Task List for Future Releases (e.g. `v1.0.1`, `v1.1.0`)

Follow these steps in order for every new release:

### Step 1 — Bump Version & Changelog
- [ ] Update `CFBundleShortVersionString` (e.g. `1.0.1`) and increment `CFBundleVersion` (e.g. `2`) in `Resources/Info.plist`.
- [ ] Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
- [ ] Document changes in `CHANGELOG.md`.

### Step 2 — Regenerate Assets & Xcode Project (if changed)
- [ ] If icon changed: run `swift scripts/generate_icon.swift Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png` and rebuild `Resources/AppIcon.icns`.
- [ ] If screenshots changed: run `swiftc -parse-as-library -O scripts/generate_screenshots.swift -o /tmp/gen_shots && /tmp/gen_shots && rm -f /tmp/gen_shots`.
- [ ] Regenerate Xcode project: `xcodegen generate`.

### Step 3 — Build & Sign Direct Release Packages
- [ ] Run `./scripts/package_all.sh` (auto-selects `Developer ID Application: Csaba Moldovan (GZE5C5C4L8)`).
- [ ] Verify signature:
  ```bash
  codesign -dvvv build/DesktopWorkspace.app 2>&1 | grep -E "Authority|Identifier|TeamIdentifier|Runtime"
  ```
- [ ] Install locally to `/Applications/DesktopWorkspace.app` if testing locally:
  ```bash
  rm -rf /Applications/DesktopWorkspace.app && cp -R build/DesktopWorkspace.app /Applications/DesktopWorkspace.app
  ```

### Step 4 — Notarize & Staple for Gatekeeper
- [ ] Submit `.dmg` to Apple Notary Service:
  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun notarytool submit build/DesktopWorkspace-<VERSION>.dmg \
    --key ~/.appstoreconnect/private_keys/AuthKey_J29633LL65.p8 \
    --key-id J29633LL65 \
    --issuer 50da2e06-9a19-4a5f-a183-13f82dff3137 \
    --wait
  ```
- [ ] Staple and validate both `.dmg` and `.app`, then re-zip `.app` and update checksums:
  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun stapler staple build/DesktopWorkspace-<VERSION>.dmg
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun stapler validate build/DesktopWorkspace-<VERSION>.dmg
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun stapler staple build/DesktopWorkspace.app
  rm -f build/DesktopWorkspace-<VERSION>.zip
  ditto -c -k --sequesterRsrc --keepParent build/DesktopWorkspace.app build/DesktopWorkspace-<VERSION>.zip
  (cd build && shasum -a 256 DesktopWorkspace-<VERSION>.dmg DesktopWorkspace-<VERSION>.zip DesktopWorkspace-<VERSION>.pkg > SHA256SUMS.txt)
  ```

### Step 5 — Publish GitHub Release
- [ ] Commit, push `main`, tag `v<VERSION>`, and create release:
  ```bash
  git add . && git commit -m "Release v<VERSION>" && git push origin main
  git tag -a v<VERSION> -m "Desktop Workspace v<VERSION>" && git push origin v<VERSION>
  gh release create v<VERSION> \
    build/DesktopWorkspace-<VERSION>.dmg \
    build/DesktopWorkspace-<VERSION>.pkg \
    build/DesktopWorkspace-<VERSION>.zip \
    build/SHA256SUMS.txt \
    --title "Desktop Workspace v<VERSION>"
  ```

### Step 6 — Archive & Upload to App Store Connect
- [ ] Archive with Xcode:
  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild archive \
    -project DesktopWorkspace.xcodeproj \
    -scheme DesktopWorkspace \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath build/DesktopWorkspace.xcarchive \
    -allowProvisioningUpdates \
    -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_J29633LL65.p8 \
    -authenticationKeyID J29633LL65 \
    -authenticationKeyIssuerID 50da2e06-9a19-4a5f-a183-13f82dff3137
  ```
- [ ] Export and upload to App Store Connect:
  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -exportArchive \
    -archivePath build/DesktopWorkspace.xcarchive \
    -exportOptionsPlist build/ExportOptions-AppStore.plist \
    -exportPath build/AppStoreExport \
    -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_J29633LL65.p8 \
    -authenticationKeyID J29633LL65 \
    -authenticationKeyIssuerID 50da2e06-9a19-4a5f-a183-13f82dff3137
  ```

### Step 7 — Submit New Version in App Store Connect
- [ ] Open `https://appstoreconnect.apple.com/apps/6837278519` → **+ macOS App Version**.
- [ ] Enter "What's New in This Version", attach the processed build, and click **Add for Review → Submit to App Review**.

---

## 4. Troubleshooting Notes (Lessons Learned)
- **XcodeGen overwrites `Info.plist` / `.entitlements` if declared as top-level `info:` / `entitlements:` blocks:** Always keep `INFOPLIST_FILE` and `CODE_SIGN_ENTITLEMENTS` under `settings.base` in `project.yml` so `xcodegen generate` references your files without overwriting them.
- **Executable name mismatch (`CodeSign` error):** Keep `PRODUCT_NAME: DesktopWorkspace` (no space) in `project.yml` to match `CFBundleExecutable: DesktopWorkspace` in `Resources/Info.plist`, while `CFBundleDisplayName` and `CFBundleName` remain `"Desktop Workspace"`.
- **Accessibility permission resets after rebuild:** Avoid ad-hoc signing (`codesign --sign -`), which changes the `CDHash` on every build. Signing `/Applications/DesktopWorkspace.app` consistently with `Developer ID Application` keeps macOS Accessibility permissions intact across updates.
- **`security find-identity` shows `0 valid identities` after importing `.cer`:** Install Apple's intermediate CAs (`AppleWWDRCAG3.cer` and `DeveloperIDG2CA.cer`) into `login.keychain-db`.
