# Camera Spike Report — Canon EOS R → iPad

> **Phase 1A status:** pre-hardware preparation.
> **Physical result:** **NOT TESTED.** No iPad or EOS R connection is available. The unsigned iOS build succeeds (16.4 MB) after installing iOS 26.5; physical signing/deployment is still not configured. No CascableCore licence is available.
> **Status labels:** DONE — verified · BLOCKED — dependency/hardware unavailable · READY FOR PHYSICAL TEST · NOT STARTED.

---

## 1. Environment inspection (2026-11-09)

| Item | Result | Status |
|---|---|---|
| macOS | 26.5.1 (25F80), arm64 | DONE — verified |
| Flutter | 3.44.1 stable / Dart 3.12.1 | DONE — verified |
| Xcode | **26.6 (17F113)** installed at `/Applications/Xcode.app/Contents/Developer` | DONE — verified |
| `xcodebuild` | Works; iOS 26.5 SDK and runtime installed | DONE — verified |
| CocoaPods | **1.17.0** | DONE — verified |
| iPad / iPhone | None connected (`flutter devices`: macOS + Chrome only) | **BLOCKED** |
| Canon EOS R | Not connected to this Mac | **BLOCKED** for local verification |
| iOS project exists | `ipad_app/ios/Runner.xcodeproj` present | DONE — verified |
| `flutter build ios --no-codesign` | **Succeeds**: `Runner.app` 16.4 MB, arm64 | DONE — verified |

**Conclusion:** Xcode, CocoaPods and the iOS 26.5 runtime are installed; the unsigned device build succeeds. Physical installation still needs an Apple Development signing identity/team and an iPad. The camera path remains blocked by CascableCore licensing/adapter work.

---

## 2. Official camera findings

### 2.1 Canon EDSDK is not an iPad SDK

Canon's Camera API Package lists EDSDK for **Windows 10/11, macOS 13–15, and Linux** — not iOS/iPadOS. A custom iPad app cannot link EDSDK.

Source: <https://asia.canon/en/campaign/developerresources/cap>

**Status: BLOCKED / NO-GO.** Do not attempt EDSDK on iPad.

### 2.2 Canon CCAPI is network-only

CCAPI is Canon's HTTP API over **Wi-Fi** (wired LAN only on specific bodies, not EOS R). It is not a USB/PTP cable API. Public Canon material does not confirm EOS R CCAPI support.

**Status: NOT A CABLE SOLUTION.** It is a fallback only and would violate the agreed topology.

### 2.3 CascableCore is the only researched cable path

Cascable's official compatibility page states:

- **Canon EOS R** is supported by Cascable Studio, Cascable Pro Webcam and Cascable Transfer.
- **USB** and Wi-Fi are both supported.
- USB for EOS R requires **Cascable Studio 5.2 or later**.
- EOS R features include remote control/automation, tethered shooting, **live view**, video, photo review, **storage access** and RAW.
- CascableCore is an SDK for **iOS/iPadOS/macOS/visionOS**, supporting 250+ cameras over **Wi-Fi or USB**, with live view, shooting and file-transfer APIs.
- A **30-day fully featured evaluation licence** is available; commercial use requires a licence.

Sources:

- <https://compatibility.cascable.se/canon/eos-r/>
- <https://cascable.se/help/wired-cameras/>
- <https://developer.cascable.se/>
- <https://cascable.github.io/>
- <https://github.com/cascable/cascablecore-distribution>

**Status: documented; API signatures not compiled/verified here.** The SDK is not installed, no licence has been obtained, and no EOS R capture has been attempted.

### 2.4 What “supported APIs” means for the spike

CascableCore documents the concepts needed:

| Capability | CascableCore area (conceptual) |
|---|---|
| Discover camera | `CBLCameraDiscovery` |
| Connect/authenticate | camera connection + authentication callbacks |
| Live view | camera live-view API |
| Trigger shutter | one-shot shutter / autofocus API |
| Download original | file storage / file-system item streaming |
| Disconnect/reconnect | camera connection state / discovery restart |

Exact Swift signatures must be taken from the installed SDK headers. This report does **not** claim they have been compiled.

---

## 3. Prepared integration

### 3.1 Flutter side — DONE (scaffold)

- `lib/services/native_camera_service.dart` — MethodChannel client for `com.terabooth/camera`:
  - `connect`, `capture`, `status`.
  - Decodes base64 image bytes, width/height.
  - Returns errors; does not fake success.
- `lib/main.dart` — opt-in build flag:
  - default: `MockCameraService` (clearly labelled SIMULATED).
  - `--dart-define=USE_NATIVE_CAMERA=true`: `NativeCameraService`.
- Mock camera remains for automated UI tests.

### 3.2 Swift side — DONE (compile-safe stub), BLOCKED (adapter)

- `ios/Runner/AppDelegate.swift` registers `CameraPlugin` on `com.terabooth/camera`.
- `CameraPlugin` currently returns **`CAMERA_SDK_MISSING`** for `connect`/`capture` — no fake detection or capture.
- `ios/Runner/Cascable/CascableCameraAdapter.swift` is a **reference file, not in the Xcode target**:
  - Guarded by `#if canImport(CascableCore)`.
  - Contains the intended adapter shape and TODOs.
  - Must be added to the Runner target and completed against the licensed SDK.
- `Info.plist` includes:
  - `NSLocalNetworkUsageDescription`
  - `NSAppTransportSecurity` → `NSAllowsLocalNetworking`
  - `NSBonjourServices` → `_ptp._tcp`
  - `NSCameraUsageDescription`

**Status:** scaffold DONE; real adapter **NOT STARTED**; compile **BLOCKED**.

### 3.3 What is intentionally not done

- No simulated “camera detected”.
- No fake capture bytes labeled as EOS R.
- No Wi-Fi fallback hidden behind the cable requirement.
- No Windows camera control.
- No purchase of a Cascable licence.

---

## 4. Exact steps to unblock on the Mac

### 4.1 Install Xcode and CocoaPods

> **Phase 1A.1 update:** Xcode 26.6 and CocoaPods 1.17.0 are now installed. The remaining environment step is the iOS 26.5 platform runtime (see §9). The commands below are kept for reference.

1. Install **Xcode** from the Mac App Store:
   <https://apps.apple.com/app/xcode/id497799835>
2. Select it and accept the licence:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
sudo xcodebuild -license accept
```

3. Install CocoaPods (Homebrew recommended):

```bash
brew install cocoapods
pod --version
```

Alternative: `sudo gem install cocoapods` (may require Ruby/architecture fixes).

4. Verify:

```bash
flutter doctor -v
```

Xcode and CocoaPods must show ✓ before proceeding.

### 4.2 Add CascableCore

1. Request an evaluation licence at <https://developer.cascable.se/>.
2. Open `ipad_app/ios/Runner.xcworkspace` in Xcode (after `pod install` if Flutter generates a Podfile).
3. **File → Add Package Dependencies…**
4. Add:
   `https://github.com/cascable/cascablecore-distribution`
5. Add the `CascableCore` product to the **Runner** target.
6. Install the evaluation licence per Cascable's instructions.
7. Add `ios/Runner/Cascable/CascableCameraAdapter.swift` to the Runner target.
8. Implement the adapter against the SDK headers; use the installed headers as the source of truth for Swift signatures.
9. Build and run on the iPad.

### 4.3 Build/run commands

```bash
cd /Users/Apple/Dev/terabooth-event-mvp/ipad_app
flutter clean
flutter pub get
flutter build ios --no-codesign
flutter devices
flutter run -d <ipad-device-id> --dart-define=USE_NATIVE_CAMERA=true
```

Do **not** use `USE_NATIVE_CAMERA=true` until the native adapter captures a real image; without it the app returns a clear “Camera SDK missing” error.

---

## 5. Physical camera test (11 November)

Required:

- iPad with USB-C, iPadOS current.
- Canon EOS R, charged battery/AC adapter.
- Data-capable USB-C cable; direct connection.
- CascableCore evaluation licence + compiled adapter.
- Camera Wi-Fi **disabled**; correct USB/PTP mode.

Procedure:

1. Connect EOS R directly to iPad.
2. Launch app with `USE_NATIVE_CAMERA=true`.
3. Tap Connect; confirm model/serial (or a clear failure).
4. Start live view; confirm frames.
5. Trigger capture; confirm the physical shutter fires.
6. Confirm original JPEG saved to iPad documents.
7. Preview; retake; approve.
8. Repeat 10 consecutive capture sessions.
9. Unplug/replug 5 times; confirm reconnect or a clear error.
10. Record timings, errors and evidence.

**Pass criteria:** 10/10 captures, file saved, live view usable, reconnect handled, no crash.

**If it fails:** G0 is NO-GO; use the fallback (iPad built-in camera or proven LumaBooth rig). Do not claim Canon support.

---

## 6. GO / NO-GO

| Gate | Status |
|---|---|
| Environment (Xcode/CocoaPods) | **BLOCKED** |
| CascableCore licence | **BLOCKED** (not requested/purchased) |
| SDK adapter compiled | **NOT STARTED** (blocked by above) |
| EOS R USB capture | **READY FOR PHYSICAL TEST** once above are done |
| 10/10 physical capture | **NOT TESTED** |

**Current verdict: NO-GO for camera, conditional on the 11 November session.** No physical evidence exists.

---

## 7. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| No Apple signing identity/team | No physical install | Sign into Xcode; select team; connect iPad |
| Cascable evaluation not granted/commercial terms | No cable capture | Request now; fallback to iPad camera/proven rig |
| Cascable Swift API mismatch | Adapter compile failures | Implement against installed headers; keep adapter isolated |
| EOS R USB mode/Wi-Fi conflict | No detection | Disable camera Wi-Fi; use correct USB mode; direct cable |
| USB power/cable | Disconnects | Powered iPad, data cable, no unpowered hub |
| Time (11 Nov → 14 Nov) | No buffer | Camera gate must pass 11 Nov; otherwise fallback |

---

## 9. Phase 1A.1 addendum — Xcode 26.6 verification (2026-11-09)

### Environment now verified

| Item | Result |
|---|---|
| Xcode | **26.6 (17F113)**, `/Applications/Xcode.app/Contents/Developer` |
| First launch | `xcodebuild -checkFirstLaunchStatus` → exit 0 |
| Licence | `xcodebuild -license check` → OK |
| iOS SDK | **iOS 26.5** (`iphoneos26.5`) present |
| CocoaPods | **1.17.0** |
| Simulator runtimes | **None installed** (`simctl list runtimes` empty) |
| Flutter doctor | Xcode 26.6 detected; warning: unable to get simulator runtimes |
| `flutter pub get` | **Succeeded** |
| SPM packages | `FlutterFramework` + `FlutterGeneratedPluginSwiftPackage` resolved |
| CocoaPods integration | No `ios/Podfile`; Flutter uses SPM for the current plugins |

### Exact build result

`flutter build ios --no-codesign`:

```
Building com.terabooth.teraboothIpad for device (ios-release)...
Xcode build done. 2.5s
Failed to build iOS app
Uncategorized (Xcode): Unable to find a destination matching the provided destination specifier:
  { generic:1, platform:iOS }
Ineligible destinations for the "Runner" scheme:
  { platform:iOS, id:dvtdevice-DVTiPhonePlaceholder-iphoneos:placeholder,
    name:Any iOS Device, error:iOS 26.5 is not installed. }
```

Direct target build gets further and fails in asset/storyboard compilation:

```
error: No available simulator runtimes for platform iphonesimulator.
       SimServiceContext supportedRuntimes=[]
...
Main.storyboard: error: iOS 26.5 Platform Not Installed.
LaunchScreen.storyboard: error: iOS 26.5 Platform Not Installed.
```

**Cause:** Xcode 26.6 has the iOS SDK but the **iOS 26.5 platform/simulator runtime component is not installed**. This is an Xcode component issue, not a Swift/project code error.

A download was attempted:

```bash
xcodebuild -downloadPlatform iOS
```

It was **cancelled at 10.5% (893 MB of 8.52 GB)** with `Download was cancelled (Asset download for com.apple.MobileAsset.iOSSimulatorRuntime)`. It was subsequently installed successfully (iOS 26.5, 23F77), and the unsigned build then succeeded. The command had returned exit code 0 despite the cancellation, so do not rely on its exit code.

### Native camera scaffold compile verification

A direct Swift type-check of the app's Swift sources against the iOS 26.5 SDK and the built Flutter framework succeeded:

```bash
cd /Users/Apple/Dev/terabooth-event-mvp/ipad_app
xcrun --sdk iphoneos swiftc -typecheck   ios/Runner/AppDelegate.swift ios/Runner/SceneDelegate.swift   -sdk "$(xcrun --sdk iphoneos --show-sdk-path)"   -target arm64-apple-ios13.0   -F ios/build/Debug-iphoneos -I ios/build/Debug-iphoneos   -import-objc-header ios/Runner/Runner-Bridging-Header.h
# exit 0
```

This verifies the **Flutter MethodChannel scaffold + Swift `CameraPlugin`** type-check. It does **not** verify a full `.app` link, storyboard/asset compilation, signing, deployment, or camera capture. `CascableCameraAdapter.swift` is not in the Xcode target and is not compiled.

### Current status

| Item | Status |
|---|---|
| Xcode first launch/licence | **DONE — verified** |
| CocoaPods | **DONE — verified** |
| `flutter pub get` | **DONE — verified** |
| SPM package resolution | **DONE — verified** |
| Swift camera scaffold type-check | **DONE — verified** |
| Full iOS build | **DONE — verified** — `flutter build ios --no-codesign` succeeded (16.4 MB) |
| Physical iPad deployment | **NOT READY** — no Apple signing identity/team, no iPad |
| CascableCore integration | **BLOCKED** — no licence, no adapter, no iPad |
| EOS R capture | **NOT TESTED** |

### Next action

1. ~~Install iOS 26.5 runtime~~ — **DONE** (iOS 26.5, 23F77 installed).
2. Confirm:
   ```bash
   xcrun simctl list runtimes
   flutter doctor -v
   ```
3. Re-run:
   ```bash
   cd /Users/Apple/Dev/terabooth-event-mvp/ipad_app
   flutter build ios --no-codesign
   ```
4. The unsigned build succeeded. Physical iPad deployment now requires an Apple Development team/signing and a connected device. See `IPAD_DEPLOYMENT_READINESS.md`.

---

## 10. Sources


- Canon CAP: <https://asia.canon/en/campaign/developerresources/cap>
- Cascable EOS R compatibility: <https://compatibility.cascable.se/canon/eos-r/>
- Cascable wired guide: <https://cascable.se/help/wired-cameras/>
- CascableCore: <https://developer.cascable.se/>
- CascableCore docs: <https://cascable.github.io/>
- CascableCore distribution: <https://github.com/cascable/cascablecore-distribution>
- Apple ExternalAccessory: <https://developer.apple.com/documentation/externalaccessory>
- Apple DriverKit for iPadOS: <https://developer.apple.com/documentation/driverkit/creating-drivers-for-ipados>
