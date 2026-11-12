# iPad Deployment Readiness — Phase 1A.2

> **Audit date:** 2026-11-09 23:05 (Asia/Kuala_Lumpur)
> **Mode:** read-only post-build audit. No source, UI, architecture, signing or credentials were changed.
> **Physical result:** **No iPad deployment performed.** No iPad is connected; no Apple Development identity is installed.

---

## 1. Build artifact verification — PASS

Command:

```bash
cd /Users/Apple/Dev/terabooth-event-mvp/ipad_app
flutter build ios --no-codesign
```

Result:

```text
Xcode build done. 6.5s
✓ Built build/ios/iphoneos/Runner.app (16.4MB)
```

| Check | Result |
|---|---|
| Bundle path | `build/ios/iphoneos/Runner.app` |
| Size | **16.4 MB** (16 MB on disk) |
| Main executable | `Runner`, Mach-O 64-bit **arm64** |
| Bundle identifier | `com.terabooth.teraboothIpad` |
| Version | `1.0.0` (build `1`) |
| Minimum OS | **iOS 13.0** |
| Device family | iPhone + iPad (`UIDeviceFamily = 1,2`) |
| Required capability | `arm64` |
| App icon | `AppIcon60x60@2x.png`, `AppIcon76x76@2x~ipad.png`, `Assets.car` |
| Flutter assets | `App.framework/flutter_assets` (Material icons, shaders, manifests) |
| Camera MethodChannel | `com.terabooth/camera` string present in `Runner` binary |
| Embedded framework | `@rpath/Flutter.framework/Flutter` linked |
| Code signature | **None** (`code object is not signed at all`) |
| Provisioning profile | **None** (`embedded.mobileprovision` absent) |

### Bundle contents

Expected and present:

```text
Runner.app/
  Runner
  Info.plist
  PkgInfo
  Assets.car
  AppIcon60x60@2x.png
  AppIcon76x76@2x~ipad.png
  Frameworks/
    App.framework/              (5.4 MB; Dart AOT + flutter_assets)
    Flutter.framework/          (9.8 MB)
    objective_c.framework/      (224 KB; native-assets runtime for path_provider FFI)
```

`App.framework`, `Flutter.framework`, and `objective_c.framework` are ad-hoc signed; `Runner.app` itself is unsigned. This is expected from `--no-codesign`.

`path_provider_foundation` has no separate framework because it is implemented via Dart FFI + `objective_c.framework` (`native_build: false`). The empty `GeneratedPluginRegistrant` is therefore expected for this plugin version; the camera plugin is registered explicitly in `AppDelegate.swift`.

---

## 2. Flutter and Python tests — PASS

| Suite | Command | Result |
|---|---|---|
| Flutter analyze | `flutter analyze` | **No issues found** |
| Flutter tests | `flutter test` | **6 passed** |
| Python bridge tests | `./.venv/bin/pytest -q` | **8 passed** (1 Starlette deprecation warning) |

No test failures.

---

## 3. Xcode Runner target — inspected

| Setting | Value |
|---|---|
| Product bundle identifier | `com.terabooth.teraboothIpad` |
| Deployment target | **iOS 13.0** (Xcode recommends 15.0) |
| Supported platforms | `iphoneos` |
| Targeted device family | iPhone + iPad |
| Swift version | 5.0 |
| Bitcode | disabled (`ENABLE_BITCODE = NO`) |
| Code signing allowed/required | `YES` / `YES` |
| Code sign identity | `iPhone Developer` |
| Development team | **empty** |
| Provisioning style | automatic default; no team/profile |
| Entitlements file | **none** |
| Capabilities | **none configured** |
| Valid code-signing identities | **0** |
| Provisioning profiles | **none found** |

### Permissions in source + built Info.plist — PASS

| Key | Value |
|---|---|
| `NSLocalNetworkUsageDescription` | “Terabooth uses the local network to send photos to the print bridge and to reach the camera.” |
| `NSCameraUsageDescription` | “Terabooth uses the camera to capture guest photos.” |
| `NSBonjourServices` | `_ptp._tcp` |
| `NSAppTransportSecurity` → `NSAllowsLocalNetworking` | `true` |

These are privacy descriptions, not Xcode capabilities. No `NSPhotoLibraryAddUsageDescription` is needed because originals are stored in the app’s own documents directory. No microphone/location/Bluetooth permission is declared.

---

## 4. Can this deploy to a physical iPad after signing? — YES, with signing blockers cleared

The artifact is structurally deployable:

- arm64 executable.
- iPad supported.
- iOS 13+ deployment target.
- Correct bundle ID.
- Required Flutter frameworks/assets embedded.
- Permissions present.

### Current signing blockers

| Blocker | Status |
|---|---|
| No Apple Development code-signing identity | **BLOCKED** — `security find-identity` → 0 valid |
| No `DEVELOPMENT_TEAM` set | **BLOCKED** |
| No provisioning profile | **BLOCKED** |
| `Runner.app` is unsigned | **BLOCKED** for install |
| No iPad connected | **BLOCKED** until 11 Nov |
| No Xcode account/team configured in this environment | **BLOCKED** |

**No signing was attempted and no credentials were used.**

Once an Apple ID/team is signed into Xcode and a team is selected for Runner, this project can be signed and installed. If using a **free Personal Team**, expect 7-day provisioning expiry and device limits; sign close to the event. A paid Apple Developer Program account is more robust but is not required for this audit and was not purchased.

---

## 5. Exact deployment procedure — day the iPad arrives

### A. Prepare the iPad

1. Update iPadOS to a current version.
2. Connect the iPad to the Mac with a data-capable USB-C cable.
3. On the iPad, tap **Trust This Computer**.
4. Enable **Developer Mode**:
   **Settings → Privacy & Security → Developer Mode → On**, then restart the iPad.
5. Keep the iPad unlocked during install.

### B. Configure Apple signing

1. Open **Xcode → Settings → Accounts**.
2. Add the Apple ID that owns the development team.
3. Select the team and create/download the **Apple Development** certificate if prompted.
4. Open the workspace:

```bash
cd /Users/Apple/Dev/terabooth-event-mvp/ipad_app
open ios/Runner.xcworkspace
```

5. Select **Runner** target → **Signing & Capabilities**.
6. Enable **Automatically manage signing**.
7. Select the correct **Team**.
8. Confirm the bundle identifier is unique:
   `com.terabooth.teraboothIpad`.
   If it is already registered by another team, change only the bundle identifier in Xcode.
9. Wait for Xcode to create the provisioning profile and register the iPad.

### C. Verify device visibility

```bash
flutter devices
```

The iPad should appear with a device ID. If not, check Trust, Developer Mode, cable and Xcode Devices window.

### D. Install/run

For the first run:

```bash
cd /Users/Apple/Dev/terabooth-event-mvp/ipad_app
flutter run -d <ipad-device-id>
```

Or press **Run** in Xcode with the iPad selected.

For a standalone build:

```bash
flutter build ios --release
flutter build ipa --release
```

The signed `.app`/`.ipa` is then installed via Xcode, Apple Configurator or an MDM. Do not use the unsigned `--no-codesign` artifact for installation.

### E. First-launch checks on iPad

- App launches without crash.
- **Local Network** permission prompt appears; allow it.
- Enter the Windows bridge URL; health request succeeds.
- Mock camera is visibly labelled **SIMULATED CAMERA**.
- Capture 3 mock images; originals written; review/retake works.
- QR screen displays.
- App restart preserves originals.
- No claim of EOS R capture is made.

---

## 6. Remaining camera integration blockers

The current build is a **mock-camera app**, not a working EOS R booth.

| Blocker | Status |
|---|---|
| CascableCore evaluation licence | **NOT OBTAINED** — do not purchase without approval |
| CascableCore SPM package in Runner | **NOT ADDED** |
| Real `CascableCameraAdapter` implementation | **NOT STARTED** — reference file not in target |
| `CameraPlugin` stub | Returns `CAMERA_SDK_MISSING`; no fake capture |
| Default app camera | `MockCameraService` — clearly simulated |
| Real EOS R USB capture | **NOT TESTED** |
| 10/10 camera sessions | **NOT TESTED** |

The app can be deployed and tested with the mock camera, but it is **not camera-ready for the event** until CascableCore is licensed, integrated, compiled and physically tested with the EOS R on the iPad.

---

## 7. Status summary

| Task | Status |
|---|---|
| Verify `Runner.app` bundle | **DONE — verified** |
| Flutter analyze/tests | **DONE — verified** |
| Python bridge tests | **DONE — verified** |
| Inspect Runner target | **DONE — verified** |
| Verify permissions | **DONE — verified** |
| Determine physical deployability | **YES after signing**; currently **BLOCKED** by no identity/team/profile/device |
| Document iPad procedure | **DONE** |
| Camera integration | **BLOCKED** — licence/adapter/physical test |
| Physical deployment | **NOT PERFORMED** |

---

## 8. Exact next action

1. Sign into Xcode with the Apple ID/team and select the Runner team; connect the iPad and enable Developer Mode.
2. Run `flutter devices`, then `flutter run -d <ipad-id>` to install the mock-camera build.
3. In parallel, request CascableCore evaluation (no purchase) and integrate the adapter; do not claim EOS R support until the 11 Nov 10/10 test passes.

**No credentials were used, no signing was performed, and no physical iPad/camera result is claimed.**
