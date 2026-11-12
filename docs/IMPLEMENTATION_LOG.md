# Terabooth Event MVP — Implementation Log (Phase 1A)

> **Project:** `/Users/Apple/Dev/terabooth-event-mvp`
> **Phase:** 1A — pre-hardware readiness (11 November session preparation)
> **Event:** Saturday 14 November 2026
> **Status labels:** DONE — verified · BLOCKED · READY FOR PHYSICAL TEST · NOT STARTED

---

## 1. Environment inspection — DONE (verified)

| Item | Result |
|---|---|
| macOS | 26.5.1 (25F80), arm64 |
| Flutter / Dart | 3.44.1 stable / 3.12.1 |
| Xcode | **26.6 (17F113)** installed at `/Applications/Xcode.app/Contents/Developer` |
| CocoaPods | **1.17.0** |
| iPad / iPhone | **None connected** (`flutter devices`: macOS + Chrome only) |
| Windows laptop | **Not available** (expected 11 Nov) |
| DNP DS-RX1HS | Not connected to this Mac (expected on Windows) |
| Canon EOS R | Not connected to this Mac (expected on iPad) |
| iOS project | `ipad_app/ios/Runner.xcodeproj` exists |
| iOS build | `flutter build ios --no-codesign` → **success**: `Runner.app` 16.4 MB; unsigned |

**Blocker:** Xcode/CocoaPods/iOS 26.5 runtime are installed and the unsigned build succeeds. Physical deployment still needs an **Apple Development signing identity/team** and an iPad.

---

## 2. Task status

### 2.1 iOS development readiness — BUILD DONE; signing BLOCKED

- Flutter iOS project exists.
- `Info.plist` has Local Network, Bonjour `_ptp._tcp`, ATS local networking, camera usage.
- `flutter analyze` clean; `flutter test` 6 passed.
- Xcode 26.6 and CocoaPods 1.17.0 are installed.
- `flutter pub get` succeeds; SPM packages resolve.
- **Unsigned iOS build exists** (`Runner.app`, 16.4 MB); it is not installable until signed.
- Swift camera scaffold type-check passes (`swiftc -typecheck` exit 0).
- No Apple signing identity/team is configured; physical deployment has not been performed.
- Exact install/build commands are in `docs/technical/CAMERA_SPIKE_REPORT.md` §4/§9.

### 2.2 CascableCore integration preparation — PARTIAL

| Item | Status |
|---|---|
| Official documentation reviewed | **DONE — verified** |
| Evaluation licence obtained | **BLOCKED** — requires Cascable developer account/request; no purchase |
| EOS R USB support confirmed by vendor docs | **DONE — documented** (Cascable compatibility page) |
| Flutter MethodChannel client | **DONE** — `NativeCameraService` |
| Swift `CameraPlugin` compile-safe stub | **DONE** — returns `CAMERA_SDK_MISSING`; no fake capture |
| Real `CascableCameraAdapter` | **NOT STARTED** — reference file only, not in Xcode target |
| Physical EOS R capture | **READY FOR PHYSICAL TEST** after licence/Xcode |
| Actual physical test | **NOT TESTED** |

### 2.3 Windows Print Bridge readiness — PARTIAL

| Item | Status |
|---|---|
| FastAPI audit | **DONE** |
| API tests | **DONE — 8 passed** (includes auth) |
| SQLite ledger / idempotency | **DONE — tested** |
| 2×6 composition dimensions | **DONE — tested** (1200×1800) |
| QR delivery | **DONE — tested on macOS HTTP** |
| Windows install/run/firewall/test scripts | **DONE — written** |
| Windows spooler adapter | **READY FOR PHYSICAL TEST** — unverified |
| DNP Hot Folder adapter | **READY FOR PHYSICAL TEST** — unverified |
| Actual DNP print | **BLOCKED** — no Windows/DNP |
| 2×6 cut/orientation | **BLOCKED** — physical test required |

### 2.4 Print output preparation — PARTIAL

- Canvas 1200×1800 @ 300 dpi; two 600×1800 panels; 2-inch cut assumed.
- Calibration generator added: `windows_bridge/scripts/make_test_sheet.py`.
- Outputs:
  - `data/test-4x6-calibration.jpg` — 1200×1800
  - `data/test-2x6-strip.jpg` — 600×1800
- **Physical dimensions/cut/orientation: BLOCKED** until DNP print.

### 2.5 Offline QR delivery — PARTIAL

- HMAC token, TTL, event/session/job scope, no login.
- QR page/original/strip/QR PNG tested over local HTTP.
- `TERABOOTH_PUBLIC_BASE_URL` rejects localhost.
- Firewall/run scripts prepared.
- **Actual guest phone + WAN-off test: BLOCKED** — no phone/router in this environment.
- Test procedure in `HARDWARE_TEST_CHECKLIST.md` §3.

### 2.6 11 November session checklist — DONE

- `docs/technical/HARDWARE_TEST_CHECKLIST.md` created with camera/printer/QR/integration steps and pass criteria.

---

## 3. Changes made in Phase 1A

### Flutter

- Added `lib/services/native_camera_service.dart`:
  - MethodChannel `com.terabooth/camera`.
  - `connect`, `capture`, `status`.
  - Decodes base64 image; no fake success.
- `lib/main.dart`: optional `--dart-define=USE_NATIVE_CAMERA=true`; default remains mock.
- iOS `AppDelegate.swift`: registers `CameraPlugin`.
- `CameraPlugin` stub returns `CAMERA_SDK_MISSING`.
- Added reference `ios/Runner/Cascable/CascableCameraAdapter.swift` (not in target).
- `Info.plist`: added `NSBonjourServices` `_ptp._tcp`.

### Python bridge

- Added `scripts/install_windows.ps1`, `run_windows.ps1`, `firewall.ps1`, `test_print.ps1`.
- Added `scripts/make_test_sheet.py`, `scripts/lan_check.py`.
- Added `TERABOOTH_PUBLIC_BASE_URL` localhost validation.
- Health response includes delivery base URL warning and printer mode.
- Pinned requirements to installed versions.

### Tests

| Suite | Result |
|---|---|
| `flutter analyze` | No issues |
| `flutter test` | **6 passed** |
| `pytest -q` | **8 passed** |
| Calibration generator | 1200×1800 and 600×1800 outputs generated |
| Live bridge smoke (macOS, mock) | health 200; submit 202; completed/confirmed; QR page/strip/QR/artefact 200 |

**No physical hardware test was performed.**

---

## 4. Exact commands to run on the Mac

### Install prerequisites

```bash
# 1. Install Xcode from the App Store:
open "macappstore://apps.apple.com/app/xcode/id497799835"

# 2. Select Xcode and accept licence:
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
sudo xcodebuild -license accept

# 3. CocoaPods (Homebrew recommended):
brew install cocoapods
pod --version

# 4. Verify:
flutter doctor -v
```

Xcode and CocoaPods must both show ✓.

### Build the iPad app

```bash
cd /Users/Apple/Dev/terabooth-event-mvp/ipad_app
flutter clean
flutter pub get
flutter build ios --no-codesign
flutter devices
```

Until the native adapter is implemented, run with the mock camera (default) for UI tests:

```bash
flutter run -d <ipad-device-id>
```

Only after CascableCore is integrated and a real capture works:

```bash
flutter run -d <ipad-device-id> --dart-define=USE_NATIVE_CAMERA=true
```

### Run the bridge tests / mock

```bash
cd /Users/Apple/Dev/terabooth-event-mvp/windows_bridge
./.venv/bin/pytest -q
./.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8787
```

### Generate calibration assets

```bash
cd /Users/Apple/Dev/terabooth-event-mvp/windows_bridge
./.venv/bin/python scripts/make_test_sheet.py --out-dir data
```

### Check LAN / QR host

```bash
./.venv/bin/python scripts/lan_check.py 8787
```

---

## 5. Exact items needed for 11 November

- iPad (USB-C, current iPadOS) with charger.
- Canon EOS R + charged battery/AC adapter.
- Data-capable USB-C cable (short, direct; no unpowered hub).
- CascableCore evaluation/commercial licence.
- Mac with full Xcode + CocoaPods installed.
- Windows 11 laptop + charger.
- DNP DS-RX1HS + USB cable + power.
- DNP 4×6 media (at least 700 prints) and 2×6-compatible media if available.
- Travel router + 2 Ethernet cables.
- Guest phone (iPhone or Android).
- Printer driver installer, DNP HFP/Status App if used.
- Power strip/UPS, tripod, ruler, calibration print.
- This checklist and the evidence sheet.

---

## 6. Critical risks

1. **No Xcode/CocoaPods** — no iPad build at all. Highest immediate risk.
2. **CascableCore licence + adapter** — without it, no EOS R cable capture; fallback needed.
3. **DNP driver on Windows 11** — RX1 driver is listed for Win7/8/10; HFP is listed for Win10/11. Must test.
4. **2×6 cut/orientation** — unverified; wrong output fails the product.
5. **QR network isolation** — without a travel router/no AP isolation, guests cannot download.
6. **Time** — 11 Nov hardware, 14 Nov event; almost no buffer.

**Fallback:** if camera or print gates fail, use the proven LumaBooth iPad + Windows print rig for the event. Do not claim Terabooth hardware support.

---

## 7. Documentation

- `docs/technical/CAMERA_SPIKE_REPORT.md`
- `docs/technical/WINDOWS_DNP_READINESS.md`
- `docs/technical/HARDWARE_TEST_CHECKLIST.md`
- `docs/technical/IMPLEMENTATION_PLAN.md`
- `docs/technical/MVP_ARCHITECTURE.md`
- `docs/technical/IMPLEMENTATION_LOG.md` (Phase 0 log)
- `README.md`

---

*No physical hardware test passed. No source outside this project was modified.*

---

## Phase 1A.1 — Post-Xcode verification (2026-11-09 19:24–19:36) — historical; superseded by Phase 1A.2

### Verified

- Xcode **26.6 (17F113)** at `/Applications/Xcode.app/Contents/Developer`.
- `xcodebuild -checkFirstLaunchStatus` → exit 0; licence check OK.
- iOS SDK **26.5** present.
- CocoaPods **1.17.0**.
- `flutter pub get` → succeeded.
- SPM: `FlutterFramework` + `FlutterGeneratedPluginSwiftPackage` resolved.
- Swift camera scaffold type-check:
  `swiftc -typecheck AppDelegate.swift SceneDelegate.swift` against iOS 26.5 SDK and built Flutter framework → **exit 0**.
- No `ios/Podfile`; current plugins use SPM.

### Build result

`flutter build ios --no-codesign` → **FAILED**:

- `Unable to find a destination ... iOS 26.5 is not installed`.
- Direct target build reaches asset/storyboard compilation, then:
  - `No available simulator runtimes for platform iphonesimulator. SimServiceContext supportedRuntimes=[]`
  - `Main.storyboard: error: iOS 26.5 Platform Not Installed.`
- Cause: **iOS 26.5 platform/simulator runtime component is not installed**. This is not a Swift or project-code error.

### Action in progress

`xcodebuild -downloadPlatform iOS` — attempted, **cancelled at 10.5% (893 MB of 8.52 GB)** with `Download was cancelled (com.apple.MobileAsset.iOSSimulatorRuntime)`. No runtime installed. The command returned exit 0 despite cancellation. Do not mark the build passed.

### Status

| Item | Status |
|---|---|
| Xcode/CocoaPods | DONE — verified |
| `flutter pub get` | DONE — verified |
| SPM resolution | DONE — verified |
| Swift camera scaffold type-check | DONE — verified |
| Full iOS build | **BLOCKED** — iOS 26.5 runtime not installed (download cancelled 10.5%) |
| iPad deployment | **NOT READY** — build/signing/device |
| CascableCore integration | **BLOCKED** — licence + platform + device |
| EOS R capture | **NOT TESTED** |

### Next

1. Install iOS 26.5 via Xcode → Settings → Components (resumable), or retry `xcodebuild -downloadPlatform iOS`.
2. Run `xcrun simctl list runtimes` and `flutter doctor -v`.
3. Re-run `flutter build ios --no-codesign`.
4. Add Apple development team/signing; connect iPad.
5. Request CascableCore evaluation (no purchase without approval) and complete the adapter.

---

## Phase 1A.2 — Post-build / iPad deployment audit (2026-11-09 23:05)

### Build artifact

- `flutter build ios --no-codesign` → **success**: `build/ios/iphoneos/Runner.app` **16.4 MB**.
- Main executable arm64; bundle ID `com.terabooth.teraboothIpad`; version 1.0.0 (1); minimum iOS 13.0.
- Frameworks: `App.framework` (5.4 MB), `Flutter.framework` (9.8 MB), `objective_c.framework` (224 KB).
- Flutter assets present: manifests, Material icons, shaders.
- Camera MethodChannel string `com.terabooth/camera` present in the `Runner` binary.
- **Unsigned:** no code signature, no `embedded.mobileprovision`.
- `path_provider_foundation` uses Dart FFI + `objective_c.framework`; no separate plugin framework is expected.

### Tests

| Suite | Result |
|---|---|
| `flutter analyze` | No issues |
| `flutter test` | **6 passed** |
| `pytest -q` | **8 passed** |

### Signing / target

- Bundle ID: `com.terabooth.teraboothIpad`
- Deployment target: iOS 13.0
- Device family: iPhone + iPad
- Code signing required: yes; identity `iPhone Developer`; **no team**
- Valid code-signing identities: **0**
- Provisioning profiles: **none**
- Entitlements file: **none**
- Capabilities: **none configured**
- No iPad connected.

**Physical deployment is possible after Apple Development signing is configured**, but was **not performed**. No credentials were used.

### Permissions

- `NSLocalNetworkUsageDescription` present.
- `NSCameraUsageDescription` present.
- `NSBonjourServices` `_ptp._tcp` present.
- `NSAllowsLocalNetworking` true.

### Camera

- Still mock-only. `CameraPlugin` returns `CAMERA_SDK_MISSING`.
- CascableCore licence/adapter/physical test remain blockers.
- No EOS R integration claim.

### Documentation

- `docs/technical/IPAD_DEPLOYMENT_READINESS.md` created.

### Next action

Sign into Xcode with the Apple ID/team, select the Runner team, connect the iPad with Developer Mode enabled, and run `flutter run -d <ipad-id>`; in parallel request CascableCore evaluation (no purchase).

---

## Phase 1B — CascableCore SDK research (documentation-only)

**Date:** 2026-11-09
**Status:** documentation complete; integration blocked on CascableCore licence and physical hardware. No source changed.

### Documents created

- `docs/technical/CASCABLECORE_SDK_RESEARCH.md`
- `docs/technical/CASCABLECORE_INTEGRATION_PLAN.md`
- `docs/technical/CASCABLECORE_API_MAPPING.md`
- `docs/technical/CASCABLECORE_TEST_PLAN.md`

### Official sources verified

- Developer portal (accessible).
- CascableCore distribution `README.md` and `Package.swift`.
- CascableCoreSwift `README.md` and `Package.swift`.
- CascableCore demo `README.md` and Getting Started guide; Swift discovery/live-view/shooting source.
- CascableCore API reference (`cascable.github.io`).
- Canon EOS R compatibility page.
- Cascable wired-camera guide.

### Confirmed facts

- SPM distribution: `https://github.com/cascable/cascablecore-distribution`, product/module `CascableCore`.
- Swift package: `https://github.com/cascable/cascablecore-swift`, product/module `CascableCoreSwift`, depends on distribution from 18.0.2.
- Minimum iOS: **14.0**; current app target is 13.0 and must be raised before adding the SDK.
- Evaluation: 30-day fully featured trial; approval required; no purchase.
- EOS R: vendor compatibility lists USB support (Studio 5.2+), live view, remote control, storage access; **not physically tested**.
- USB is not supported in the iOS Simulator; physical iPad required.
- Required Info.plist keys already present: ATS local networking, local network description, `_ptp._tcp`, camera description.
- Multicast entitlement is for SSDP/Wi-Fi discovery, not USB-only; not added.

### Confirmed API areas

- `CameraDiscovery` / `CBLCameraDiscovery` with `.usbOnly`, wired authorization, delegate.
- `connect(authenticationRequestCallback:authenticationResolvedCallback:completionCallback:)`.
- `beginStream(...)` / `liveViewPublisher(...)`.
- `invokeOneShotShutterExplicitlyEngagingAutoFocus(...)`.
- `addCameraInitiatedTransferHandler`, `executeTransfer`, `writeRepresentation`.
- `storageDevices`, `loadChildren`, `streamItem`.
- `CascableCoreLicenseVerification.apply(license:)`.

### Critical findings

- Shutter completion callback does **not** prove the shutter fired; require transfer/file evidence.
- Camera-initiated transfer requests expire; `isOnlyDestinationForImage` can mean data loss if ignored.
- Switching to filesystem access may stop live view.
- Capture/connection must have timeouts and no auto-retry after ambiguous results.
- Licence must be applied before any SDK API; fail closed.
- No EOS R capture has been performed.

### Status

| Item | Status |
|---|---|
| SDK documentation research | DONE |
| API/source mapping | DONE |
| Integration plan | DONE |
| Test plan | DONE |
| Evaluation licence | BLOCKED — not approved |
| SDK added to Xcode | NOT STARTED — prohibited this phase |
| Source changes | NONE |
| Physical EOS R test | NOT TESTED |

### Next action

Wait for CascableCore licence approval. Then follow `CASCABLECORE_INTEGRATION_PLAN.md` in order: raise iOS target to 14, add SPM package, install licence, implement adapter, pass channel tests, then run the 10/10 physical plan.

---

## Phase 1C — SDK-independent camera pipeline (2026-11-09/10)

**Status:** implemented and tested with the mock/fake camera. CascableCore was **not** installed; no physical camera test was performed.

### Files inspected

- `lib/services/camera_service.dart`, `native_camera_service.dart`, `storage_service.dart`
- `lib/booth_controller.dart`, `lib/main.dart`, `lib/models.dart`
- `lib/screens/*` (capture/review/print/welcome)
- `ios/Runner/AppDelegate.swift`, `ios/Runner/Cascable/CascableCameraAdapter.swift`
- Existing Flutter tests and Python bridge tests

### Implemented

- Explicit `CameraConnectionState` and `CameraCaptureState`; separate fields in `CameraPipelineState`.
- `CameraStateMachine` with validated transitions.
- `CameraPipeline` capture coordinator:
  - one in-flight capture, sequential queue for different slots;
  - duplicate-slot rejection;
  - unique `captureId` per request (retake = new ID);
  - configurable timeout; no automatic retry;
  - explicit success only after saved/verified image;
  - disconnect/background fail the active capture, never success.
- `ImageValidator`:
  - JPEG/PNG signature check (PNG only for simulated camera);
  - byte-size bounds;
  - JPEG SOF/PNG IHDR dimension parsing without full 30 MP decode;
  - small decode for integrity;
  - minimum long/short edge and pixel cap.
- `ImageIngestor`:
  - capture-ID association; duplicate delivery rejection;
  - atomic save; reopen/revalidate; no recompression.
- `StorageService`:
  - unique `original_<slot>_<captureId>.<ext>` filenames, no overwrite;
  - temp-in-same-directory + flush + rename;
  - length/reopen verification;
  - explicit `StorageException`;
  - `recoverIncompleteWrites()` removing temp/partial files only.
- `BoothController` now uses the pipeline while preserving 3-photo/review/retake/approve and bridge/QR flow.
- App lifecycle forwarding for background/foreground.
- SDK-independent Method/EventChannel constants in `camera_contract.dart`.
- Native stub remains unchanged in behavior: `CAMERA_SDK_MISSING`; no fake capture.

### Tests

- `flutter analyze`: **No issues**
- `flutter test`: **38 passed**
- `pytest -q`: **9 passed**

Added tests: state transitions, duplicate capture, sequential queue, timeout/no-retry, disconnect during capture, disconnect during transfer, background failure, image validation (valid/invalid/low-res/PNG), duplicate image delivery, atomic/no-temp storage, storage failure, incomplete-write recovery, retake ID, 3-photo workflow regression.

### Remaining SDK-dependent work

- CascableCore licence, SPM package, iOS 14 target, native adapter, event channel implementation, physical 10/10 EOS R test.
- No physical camera/print result is claimed.

### Documentation

- `docs/technical/CAMERA_PIPELINE_RELIABILITY.md`

---

## Phase 1D — Final reliability hardening (2026-11-10)

**Status:** implemented/tested with synthetic EXIF fixtures and fake cameras. No CascableCore; no physical iPad/EOS R test.

### Findings before changes

- JPEG validation used raw SOF dimensions and ignored EXIF orientation.
- Flutter's display codec applies EXIF orientation (verified 1–8); print composition already used `ImageOps.exif_transpose`.
- Complete originals left unreferenced after an interrupted metadata write were not tracked.
- The 15 s timeout covered only `camera.capture()`, not validation/storage; late-image behavior needed an explicit test.
- No Apple signing identity/team; no iPad.

### Implemented

- `exif_orientation.dart`: JPEG APP1/TIFF orientation parser; effective dimension swap for 5–8.
- `ImageValidationResult`/`CapturedImage` carry orientation and effective dimensions; original bytes unchanged.
- `ImageIngestor` verifies orientation on reopen; metadata includes orientation.
- Display codec orientation verified; no rotation wrapper added (avoids double rotation).
- Print compositor tests cover all eight orientations; production compositor unchanged.
- `StorageService.recoverOrphans()` records complete unreferenced originals in `orphans.json` with `assigned_to_session:false`; never deletes/assigns/session-references them.
- `BoothController.startSession()` runs temp cleanup + orphan recovery.
- Late-image-after-timeout regression test proves expired captures cannot later succeed; timeout remains 15 s.
- Physical iPad signing/deployment checklist documented; no credentials used.

### Tests/results

- `flutter analyze`: **No issues**
- `flutter test`: **38 passed**
- `pytest -q`: **9 passed**
- `flutter build ios --no-codesign`: **Success — 16.5 MB**
- Physical deployment/capture: **not performed**

### Documentation

- `docs/technical/PHASE_1D_RELIABILITY_HARDENING.md`

---

## Phase 1E — Deployment readiness & event operations (2026-11-10)

**Status:** repository/build/network/printer audit complete. No physical hardware test. No CascableCore installed.

### Concrete defects found and fixed

1. `windows_bridge/scripts/run_windows.ps1` did not load `.env`, although the install procedure told operators to create it. Added a process-scoped `.env` loader (explicit process environment wins) and startup warnings for placeholder token/secret/mock printer.
2. `INSTALL_WINDOWS` now creates `.env` from `..\.env.example` when absent.
3. The bridge API token had no iPad counterpart. Added `String.fromEnvironment('TERABOOTH_API_TOKEN')` to the iPad `BridgeClient`; matching build define documented.

No Flutter camera/print-layout/Python bridge behavior changed. No new dependencies.

### Audit findings

- iPad bundle ID `com.terabooth.teraboothIpad`; deployment target **13.0**; automatic signing; **0 valid identities, no team/profile**; no iPad.
- Bridge binds `0.0.0.0:8787` via `run_windows.ps1`; health/print/QR endpoint flow reviewed.
- QR uses `TERABOOTH_PUBLIC_BASE_URL` or request Host; app rejects configured localhost; iPad default URL is a LAN IP but must match actual Windows IP.
- Print: 1200×1800 4×6, two 600×1800 2×6 strips, 300 dpi, EXIF-aware cover; idempotency/reprint/unknown status reviewed.
- Windows bridge restart does not resume in-flight background jobs; operator inspection/reprint required.
- No auto job resume or duplicate prevention beyond idempotency; documented.
- No physical DNP/Windows/phone verification.

### Tests/build

- `flutter analyze`: **No issues**
- `flutter test`: **46 passed**
- `pytest -q`: **9 passed**
- `flutter build ios --no-codesign`: **Success — 16.5 MB**
- Physical deployment: **not performed**

### Documentation

- `docs/technical/PHASE_1E_DEPLOYMENT_READINESS.md`
- `docs/EVENT_DAY_RUNBOOK.md`

---

## Phase 2A — Individual retake fix & template/GIF readiness (2026-11-10)

**Status:** retake fixed/tested; Template Engine and GIF are plans only, not implemented.

### Root cause

- Slot replacement logic was correct.
- `MockCameraService` produced **byte-identical images** for all captures, so a successful simulator retake looked unchanged.
- A failed retake previously changed the whole controller to `error`, hiding the prior approved image.

### Fixes

- Mock images now include per-capture number/accent colour; still explicitly SIMULATED.
- `BoothController` has `retakingSlot`/`retakeError`; one retake at a time.
- Previous slot image is preserved until the new image is validated/saved/reopened.
- Metadata-write failure restores the previous slot; new file remains an orphan for recovery.
- Review UI shows loading/error; retake-all/approve disabled during retake.
- Late images after timeout cannot overwrite a slot.

### Tests

- `flutter analyze`: **No issues**
- `flutter test`: **46 passed**
- `pytest -q`: **9 passed**
- Existing 3-photo/retake-all/mock/print bridge regression preserved.
- New tests: success, failure, metadata failure, timeout, late image, repeated retakes, per-slot UI buttons, visibly distinct mock captures.

### Plans created (not implemented)

- `docs/technical/TEMPLATE_ENGINE_IMPLEMENTATION_PLAN.md`
- `docs/technical/ANIMATED_GIF_IMPLEMENTATION_PLAN.md`
- `docs/technical/PHASE_2A_RETAKE_FIX.md`

### Remaining

- No physical EOS R/DNP/phone test.
- Template Engine and GIF require approval and a later phase.

---

## Phase 1F — Physical deployment & hardware validation preparation (2026-11-10)

**Status:** documentation/audit only. No code changes. No physical hardware operation.

### Signing audit

- Xcode 26.6, CocoaPods 1.17.0, iOS 26.5 runtime.
- Bundle ID `com.terabooth.teraboothIpad`; deployment target 13.0; automatic signing.
- **0 valid code-signing identities, no team, no provisioning profile, no physical iPad.**
- Only iPad (A16) Simulator is detected; simulator build is not physical deployment.
- Added exact Apple ID/Personal Team/automatic-signing/Trust/Developer Mode/install instructions.

### Windows bridge audit

- Python 3.11.9; dependencies pinned.
- `.env` is loaded by `run_windows.ps1`; `install_windows.ps1` creates it from `.env.example` if absent.
- Printer name, LAN IP and token are configurable/placeholder; no invented values.
- Firewall TCP 8787 Private; bind `0.0.0.0:8787`; SQLite/data directory documented.
- QR public base URL/localhost guard/24h token documented.
- Windows execution and DNP physical print remain unverified.

### Procedures created

- Canon EOS R: USB/auth/connect/live view/single/JPEG/3-photo/retake/disconnect/reconnect/10 sessions; **blocked** pending CascableCore/native adapter.
- DNP: driver/media/4×6/two 2×6/cut/color/20 prints/failure/recovery; **blocked**.
- QR: iPhone/Android/same LAN/WAN-off/AP isolation/token; **blocked**.
- Operator checklist: `docs/PHYSICAL_VALIDATION_CHECKLIST.md`.

### Tests/build

- `flutter analyze`: **No issues**
- `flutter test`: **46 passed**
- `pytest -q`: **9 passed**
- `flutter build ios --simulator`: **Success** (144 MB debug simulator app)
- Physical hardware: **not tested**

### Docs

- `docs/technical/PHASE_1F_PHYSICAL_VALIDATION.md`
- `docs/PHYSICAL_VALIDATION_CHECKLIST.md`
- `docs/EVENT_DAY_RUNBOOK.md` updated

---

## Phase 1F-R — Event MVP scope correction (2026-11-10)

**Documentation-only change. No application source, camera, print logic or Windows Bridge changes.**

- Removed individual per-photo retake from active event validation.
- Active event docs now require **Retake All** only: complete 3-photo recapture, all replacements valid, previous session originals preserved, review/approval after recapture.
- Updated:
  - `docs/EVENT_DAY_RUNBOOK.md`
  - `docs/PHYSICAL_VALIDATION_CHECKLIST.md`
  - `docs/technical/PHASE_1F_PHYSICAL_VALIDATION.md`
  - `docs/technical/HARDWARE_TEST_CHECKLIST.md`
  - `README.md`
- Historical implementation references remain in Phase 1D/2A and pipeline/API docs, explicitly marked historical/non-event.
- Hardware blockers remain BLOCKED: signing/iPad install, CascableCore/EOS R, Windows Bridge execution, DNP print, guest QR/network.
- No source/test changes; existing Phase 2A results remain 46 Flutter tests / 9 Python tests.

---

## Phase 1G — Windows Bridge & integration final audit (2026-11-10)

**Audit-only except one low-risk fix.** No camera, print geometry, template/GIF or hardware changes.

### Audit results

- iPad/FastAPI contract matches for the JPEG event path: auth, idempotency, 3-image upload, status polling, reprint, QR.
- Observations documented: server-generated session ID differs from client session ID; client effective EXIF dimensions vs server raw minimum check; client TTL ignored in favor of server config; input validation is Pillow-permissive rather than explicit JPEG; reprint image filename/DB ID naming inconsistency; random reprint key per client call.
- Print geometry confirmed: 1200×1800 4×6, two 600×1800 2×6 strips, EXIF-aware cover crop.
- QR token/HMAC/expiry/page/original/strip/QR headers audited; no GIF endpoint.
- Windows scripts/`.env`/firewall/LAN/data/startup audited statically; no Windows execution.
- Runbook corrected to use `curl.exe` on Windows PowerShell 5.1.

### Low-risk fix

- `windows_bridge/app/main.py`: original-image delivery now detects actual JPEG/PNG format and serves correct MIME/filename instead of always `image/jpeg`.
- New Python regression test: PNG original returns `image/png` and `.png`.
- No print layout or camera change.

### Tests/build

- `flutter analyze`: **No issues**
- `flutter test`: **46 passed**
- `pytest -q`: **10 passed**
- `flutter build ios --simulator`: **Success** (144 MB debug simulator app)
- Windows/DNP/QR physical: **not tested**

### Docs

- `docs/technical/PHASE_1G_WINDOWS_BRIDGE_AUDIT.md`
- `docs/EVENT_DAY_RUNBOOK.md` (curl.exe + audit link)
- `docs/technical/ANIMATED_GIF_IMPLEMENTATION_PLAN.md` (input-validation assumption corrected)

---

## Phase 2 — Software-only end-to-end integration (2026-11-10)

**Status:** software workflow complete with mock camera/MockClient; no physical hardware, no Windows execution.

### Implemented

- Event create/select with persisted `event_catalog.json` and welcome-screen event picker.
- Bridge-generated composition retrieval (`/v1/print-jobs/{id}/artefact`) and viewer.
- Selectable/copyable QR delivery URL.
- Duplicate-approve guard; typed bridge exceptions and configurable timeouts.
- Disposal guards for async composition/polling work.
- End-to-end mock workflow tests: capture → retake → approve → status → composition → QR URL.
- Event catalog persistence/load; welcome event-selector UI test.
- Event scope remains Retake All only; individual retake is software-only/non-event.

### Architecture decision

The Windows bridge remains the canonical 1200×1800/300 dpi/4×6 compositor. iPad submits the three originals via the existing API and retrieves the finished composition; no print API/layout change.

### Tests/build

- `flutter analyze`: **No issues**
- `flutter test`: **58 passed**
- `pytest -q`: **10 passed**
- `flutter build ios --simulator`: **Success** (144 MB debug simulator app)
- Windows/physical: **not tested**

### Docs

- `docs/technical/PHASE_2_SOFTWARE_INTEGRATION.md`
- `docs/EVENT_DAY_RUNBOOK.md` event selection/composition/copy updates
- event docs restored to Retake All only; individual retake is software-only/non-event

---

## Phase 2B — Live local network integration (2026-11-10)

**PASS** for macOS-hosted FastAPI + mock printer + iPad A16 Simulator. No Windows/printer/physical-device validation.

### Network/test

- LAN IP: `192.168.8.105`; temporary port `8790`; mock printer.
- Real job: `job_971d4ba7a4cb497cbf90eb77025aade4`; `completed/confirmed`.
- Composition: 1200×1800 JPEG, 300×300 dpi, 255,866 bytes.
- 3 mock originals: PNG 1200×1800; strip and QR downloaded/validated.
- iPhone 17 Simulator loaded guest page; physical iPhone unavailable.
- Invalid/missing API token 401; invalid/expired guest token 404; missing artefact 404; duplicate key 200 same job; job persisted across restart.

### Fixes

- Missing API token build-define application in `lib/main.dart` fixed.
- Review UI now presents **Retake All only**; individual retake is controller/test-only/non-event.
- Added `integration_test/live_bridge_test.dart` and `integration_test` dev dependency.
- Test-only URL/token passed via `--dart-define`; no credentials committed.

### Tests

- `flutter analyze`: **No issues**
- `flutter test`: **58 passed**
- `pytest -q`: **10 passed**
- `flutter build ios --simulator`: **Success** (144 MB)
- Live simulator integration: **passed**
- Windows/physical: **not tested**

### Cleanup

Temporary server stopped; temp data/env removed; iPhone simulator erased; test app uninstalled then default app reinstalled; port 8790 closed; unrelated port 8787 untouched.

---

## Phase 2C — Windows Bridge deployment & DNP validation (2026-11-10)

**Status: BLOCKED.** Actual Windows event PC was not reachable and DNP DS-RX1HS was unavailable. No Windows execution, Windows mock HTTP test, DNP print, physical cut or 20-print run was performed.

### Audit

- Entry point `app.main:app`; Python 3.11.9 local; pinned dependencies inspected.
- Windows scripts, `.env` loading, SQLite/data paths, spooler/hotfolder/mock adapters, firewall and 1200×1800 composition audited statically.
- `install_windows.ps1` prints but does not enforce Python >=3.11 (documented risk).
- No source changes; no temporary credentials committed.

### Tests

- `flutter analyze`: **No issues**
- `flutter test`: **58 passed**
- `pytest -q`: **10 passed**
- Windows runtime: **not tested**
- DNP physical: **not tested**

### Docs

- `docs/technical/PHASE_2C_WINDOWS_DNP_VALIDATION.md`

---

## Phase 2D — Operator experience & UI/UX refinement (2026-11-10)

**Software-only.** No hardware, Windows or printer changes.

### Completed

- Added shared design system (`tb_theme.dart`, `tb_ui.dart`) and iPad landscape-first layouts.
- Redesigned welcome/event console with empty state, selected event, settings access and large Start action.
- Redesigned capture screen with camera/capture states, progress steps, countdown and mock labels.
- Redesigned review with template context, Retake All confirmation and duplicate-approval protection.
- Redesigned print screen with job ID, acceptance-vs-completion distinction, composition preview, QR copy and failed/unknown recovery.
- Added settings screen with persisted bridge URL, connectivity test and bridge-reported diagnostics.
- Fixed stale event-catalog load overwriting a newly created/selected event.
- Added `hasSelectedEvent`, bridge health state and settings persistence.

### Tests

- `flutter analyze`: **No issues**
- `flutter test`: **65 passed**
- Live MacBook FastAPI mock integration: **passed** (job `job_2c8332dbe3874b20932c38dd9ece9949`, completed/confirmed)
- `flutter build ios --simulator`: **Success** (145 MB)
- Windows/physical: **not tested**

### Docs

- `docs/technical/PHASE_2D_OPERATOR_EXPERIENCE.md`

---

## Phase 2E — Template Engine & Smart Auto-Fit (2026-11-10)

**Software-only.** No hardware/Windows/printer changes.

### Completed

- Added versioned data-driven template model and three built-ins:
  - Classic 2×6 Duo (default geometry unchanged)
  - Editorial Collage
  - Minimal Stack
- Added template gallery with previews, selection and session lock.
- Added Smart/Fit/Manual crop metadata, planner, safe fallback and manual editor.
- Added native Apple Vision face detection channel and detector abstraction.
- Added Flutter composition preview with normalized crop rendering.
- Extended bridge with optional `template_version` and `crops`, validated metadata, canonical Pillow rendering, DB persistence and legacy fallback.
- Added template/crop metadata to session persistence and bridge requests.
- Added public-domain Vision fixture; simulator returned `Could not create inference context`, so the real-Vision test skips explicitly and the live job used Fit fallback.

### Tests

- `flutter analyze`: **No issues**
- `flutter test`: **75 passed**
- `pytest -q`: **20 passed**
- `flutter build ios --simulator`: **Success** (145 MB)
- Live MacBook FastAPI mock integration: **PASS** (job `job_97516cda64eb47638ffa1d3522b8dea1`, default template v1, fit crops, 1200×1800 300 dpi)
- Real Apple Vision: **skipped/unavailable on simulator**
- Windows/physical: **not tested**

---

## Phase 2F — Animated GIF & guest delivery (2026-11-10)

**Software-only.** No Windows/physical printer validation.

### Completed

- Added 3-frame 360×540 GIF89a generator using Pillow, 1800 ms/frame, infinite loop, Fit/Contain, EXIF transpose, atomic output and reopen validation.
- Added persisted GIF state/path/error/size and atomic generation claim.
- Added independent background generation; GIF failure cannot affect print composition/submission.
- Added authenticated `/v1/print-jobs/{id}/gif`, guest `/d/{token}/gif`, guest-page link and pending/failed states.
- Added Flutter `gif_state`, authenticated fetch, independent controller loading, animated `Image.memory` preview and GIF result card.
- Preserved originals, strip, QR, HMAC, idempotency and no-auto-resubmit.

### Evidence

- Live job `job_38d1e31bd10642fc81ac0f2189d9b9e2`; print completed/confirmed; GIF ready.
- GIF: 360×540, 3 frames, 1800 ms each, loop=0, GIF89a, 281,515 bytes.
- Guest and authenticated GIF endpoints 200; guest page link present.
- Flutter/API tests inspect real Pillow frame count/duration/size/loop/order.

### Tests

- `flutter analyze`: **No issues**
- `flutter test`: **78 passed**
- `pytest -q`: **28 passed**
- `flutter build ios --simulator`: **Success** (145 MB)
- Live MacBook FastAPI integration: **PASS**
- Windows/physical: **not tested**

---

## Phase 2G — Final software QA (2026-11-10)

**Overall: PASS for software/simulator QA; physical hardware remains unverified.**

### Fixes

- GIF startup recovery: stale processing release, valid ready preservation without overwrite, attempt limits, temp cleanup, safe failed state.
- Session recovery: explicit resume of complete unsubmitted review; approved sessions excluded.
- Mock print status corrected: “Mock print complete — no physical print”; failed/unknown never show “Complete.”
- Post-submission metadata failure no longer hides accepted print job.
- Guest DB expiry enforced with HMAC; API token compare constant-time.
- Guest GIF pending/failed states tested; temp permissions restricted.
- UI/lifecycle/regression tests expanded.

### Evidence

- Live job `job_638f196bc01a44b99b6c5b2e1a06c0e0`; mock print completed; GIF ready 360×540, 3 frames, 1800 ms, loop=0, GIF89a, 281,515 bytes; guest/API GIF 200.
- `flutter analyze` clean, **81 Flutter tests**, **35 Python tests**, simulator build **145 MB**.
- Real Vision remains skipped on simulator; no physical claim.

---

## Phase 2H — Operational security & submitted-job reconciliation (2026-11-10)

**Software PASS.** Physical hardware remains unverified.

### Completed

- Central log redaction for guest `/d/<token>` paths, Authorization headers, query tokens and configured secrets; access/application/exception formatters covered.
- Local submitted-job records with event/session/job/template/status/GIF/delivery metadata.
- Startup GET-only reconciliation; offline retention; manual refresh/dismiss; no new POST/resubmit.
- Print screen refresh action and offline welcome banner.
- Session recovery from Phase 2G retained.

### Evidence

- Live bridge `172.20.10.6:8796`, job `job_9acedd5ff2cc4b2c8c065e51d1624df3`; mock print completed; GIF ready 360×540, 3 frames, 1800 ms, loop=0, 281,515 bytes; guest GIF 200.
- Access log contained `/d/<redacted>/gif`; raw guest token, API token and delivery secret absent.
- Flutter reconciliation tests show POST count 0; unknown stays unknown.
- `flutter analyze` clean; **87 Flutter tests**, **39 Python tests**, build **145 MB**.


---

## Phase 3A-1 — CascableCore SDK setup & simulated camera (2026-11-12)

**Status: BLOCKED — licence bytes absent; EOS 60D compatibility unverified.**

- Added official SPM packages: CascableCore 18.0.2, CascableCoreSwift 18.0.2,
  CascableCoreSimulatedCamera 1.0.14; iOS minimum raised to 14.
- Added `Debug-CascableDemo` / `se.cascable.CascableCoreiOSDemo`; production
  bundle ID `com.terabooth.teraboothIpad` preserved.
- Demo build succeeded and launched; SDK loaded the simulated plugin.
- Licence verification returned `invalidLicense` because no licence artifact
  exists in the workspace; probe is fail-closed before discovery.
- Production simulator build succeeded at 174 MB; Flutter analyze clean;
  87 Flutter and 39 Python tests pass.
- Remote Xcode SPM clone stalled; validation used the same official binaries
  via a temporary local package. Remote refs restored; Package.resolved absent.
- EOS 60D is absent from Cascable's official Canon compatibility list; no
  claims for USB, remote shutter, Live View, PTP or original JPEG. No physical
  EOS 60D test was performed.
- Full report: `docs/technical/PHASE_3A_1_CASCABLE_SETUP.md`.


---

## Phase 3A-1A — Licence activation & SPM stabilization (2026-11-12)

**PARTIAL — licence and SPM PASS; simulated camera PASS; EOS 60D still BLOCKED.**

- Supplied demo archive contained the official licence source; converted its
  byte array to the ignored `CascableCoreLicense.licence` (471 bytes, 0600),
  never printed or committed. Demo bundle contains it; production bundle does
  not.
- Official SDK verification result: **0 / success**.
- Official remote SPM resolution succeeded with `Package.resolved` pins:
  distribution 18.0.2, Swift 18.0.2, Simulated Camera 1.0.14. No temporary
  local package remains; the full-history Git clone stall was bypassed only by
  seeding SwiftPM's cache with shallow official repositories.
- Demo build and launch PASS with `se.cascable.CascableCoreiOSDemo`.
  Production build PASS with `com.terabooth.teraboothIpad`, 174 MB, no licence.
- Simulated camera: discovery, connection/state, 864×576 Live View frame,
  shutter request, 864×576 preview transfer, and disconnect all PASS.
- Original JPEG transfer NOT validated; simulated plugin does not support
  camera-initiated original transfer. EOS 60D remains unlisted/unverified.
- `flutter analyze` clean; 87 Flutter and 39 Python tests pass.
- Full report: `docs/technical/PHASE_3A_1A_LICENCE_AND_SPM.md`.


---

## Phase 3A-1B — Canon EOS 60D macOS SDK physical validation (2026-11-12)

**PASS for tested macOS subset; PARTIAL overall. iPadOS/image transfer remain blocked.**

- Created isolated native AppKit target `macos_cascable_demo/TeraboothCascableMacDemo`
  with licensed Mac bundle ID `se.cascable.CascableCoreMacDemo`; production
  iPad project and bundle ID untouched.
- Official remote CascableCore 18.0.2 resolved; `Package.resolved` pinned.
- Licence applied successfully: `CASCABLE_MAC_LICENSE_RESULT=0`.
- Physical EOS 60D over USB: discovery, model identification, connection,
  77 settings readable, 1056×704 Live View frame, one shutter request accepted,
  disconnect and USB reconnect all PASS.
- Connection warning: `LowerThanExpectedFunctionality` / `RemoteControl`;
  recorded but not fatal.
- No SD card: storage devices 0, shots available 0, image quality nil. No
  original JPEG transfer was tested or claimed.
- Comparison: reproduces Cascable Studio's USB, settings, Live View and control
  results; image transfer untested in both.
- Full report: `docs/technical/PHASE_3A_1B_CANON_60D_MAC_SDK_VALIDATION.md`.


---

## Phase 3A-2A — iOS CascableCore adapter foundation (2026-11-12)

**PARTIAL — adapter foundation complete and builds; physical iPad validation BLOCKED.**

- Added native `CascableCameraAdapter` with discovery, wired authorization,
  connection/disconnect, serializable events, Live View, shutter request, and
  camera-initiated original transfer handling.
- Capture completes only after original bytes arrive; shutter request alone
  never returns an image. Timeout/late-transfer/disconnect/no-duplicate rules
  are enforced.
- Added `NativeCameraService` initialize/licence gate and `CascableCameraService`
  delegation wrapper; MockCameraService remains default; CameraPipeline and
  ImageIngestor unchanged.
- Added serializable `CameraAdapterEvent` parser and adapter boundary tests.
- Investigated `LowerThanExpectedFunctionality`/`RemoteControl`: warning is a
  capability classification with no per-feature detail; use supported
  functionality/properties. Not dismissed or suppressed.
- `flutter analyze` clean; **96 Flutter tests**, **39 Python tests**; iOS demo and
  production builds pass. Production bundle ID preserved; production contains
  no licence.
- No physical iPad or original JPEG transfer claim.
- Full report: `docs/technical/PHASE_3A_2A_IOS_CAMERA_ADAPTER_FOUNDATION.md`.


---

## Phase 3A-2B — EOS 60D original transfer/capability validation (2026-11-12)

**BLOCKED — no USB camera enumerated during this phase; no SD card.**

- Extended the isolated macOS harness with supported-functionality/command-
  category/property metadata logging, writable-value discovery, original-only
  camera-initiated transfer handling, temporary JPEG/EXIF validation, transfer
  timeout, duplicate-callback guard, optional disconnect-during-transfer and
  clean reconnect.
- Harness refuses to shutter when storage is absent; no shutter was triggered
  in this phase.
- Current runs reached licence success and USB discovery start, but no Canon
  device appeared. No capability, transfer, original JPEG, settings or lifecycle
  results were fabricated.
- Prior Phase 3A-1B physical evidence remains: EOS 60D USB/connection, 77
  properties, 1056×704 Live View, one shutter request, reconnect, and the
  `LowerThanExpectedFunctionality`/`RemoteControl` warning.
- macOS harness build PASS; iOS production build PASS (175 MB, bundle ID
  unchanged, no licence); Flutter 96/Python 39 PASS.
- Full report: `docs/technical/PHASE_3A_2B_CANON_60D_ORIGINAL_TRANSFER_VALIDATION.md`.


---

## Phase 3A-2C — EOS 60D USB recovery/preflight (2026-11-12)

**PASS for USB/diagnostic preflight; no shutter/transfer/settings write.**

- `ioreg` confirmed Canon EOS 60D USB (`idVendor` 1193 / `idProduct` 12821,
  location 34668544) before launching the harness.
- Cascable Studio was running and held/competed with the camera. With Studio
  open, SDK discovery/connection succeeded but reported 0 known properties and
  nil values. After quitting Studio, the same camera/harness reported 78 known
  properties, full settings/valid values, 1 storage device, 724 shots, and a
  1056×704 Live View frame.
- Warning preserved: `LowerThanExpectedFunctionality` / `RemoteControl`
  (type 0/category 0).
- Clean disconnect and USB rediscovery/reconnect succeeded.
- No shutter, transfer, settings write or camera-file operation was performed.
- SD is not mounted as a macOS volume; CascableCore reports storage/shot
  capacity, consistent with an inserted card.
- macOS harness build PASS; iOS production build PASS (175 MB, Bundle ID
  unchanged, no licence); Flutter 96/Python 39 PASS.
- Full report: `docs/technical/PHASE_3A_2C_CANON_60D_USB_PREFLIGHT.md`.


---

## Phase 3A-2D — EOS 60D original JPEG transfer (2026-11-12)

**BLOCKED — camera not USB-enumerated; no shutter/transfer/JPEG.**

- Preflight found no `Canon Digital Camera` in `ioreg`; no Cascable Studio/EOS
  Utility/Image Capture user app running; no SD volume mounted.
- Prior 3A-2C capability evidence (78 properties, 1 storage, 724 shots) is
  historical and was not substituted for this test.
- Hardened the Mac harness with a unique `/tmp/.../` output directory, atomic
  write/modes 0700/0600, and a full-resolution guard (long edge ≥3000, short
  ≥2000) before accepting a result as original.
- No shutter, transfer request, original data, JPEG validation, settings write
  or exact camera-file comparison occurred.
- macOS harness build PASS; iOS production build PASS (175 MB, Bundle ID
  unchanged, no licence); Flutter 96/Python 39 PASS.
- Full report: `docs/technical/PHASE_3A_2D_CANON_60D_ORIGINAL_JPEG_TRANSFER.md`.


---

## Phase 3A-2E — EOS 60D stable USB/capability validation (2026-11-12)

**PASS for capability-only; original transfer remains unverified.**

- Confirmed the same physical USB session (`22286902512247`, location
  34734080, 480 Mbps, vendor 1193/product 12821) before and after the SDK run.
- Cascable Studio and user camera apps were closed; no physical reconnect.
- Added/used a `--capability-only` harness mode: no shutter, no transfer, stop
  Live View, clean disconnect, exit without reconnect.
- SDK discovered/connected to Canon EOS 60D over USB; warning type 0/category 0
  preserved.
- 78 known properties; `supportedFunctionality` raw 447936; command categories
  stillsShooting + filesystemAccess; one storage device; 724 shots.
- Selected settings and valid settable values recorded; no settings changed.
- Live View delivered a 1056×704 frame and terminated normally.
- Clean disconnect; final USB enumeration retained the same session ID.
- No original-transfer request or `.original` availability test; no claim.
- Mac harness build PASS; iOS production build PASS (175 MB, bundle unchanged,
  no licence); Flutter 96/Python 39 PASS.
- Full report: `docs/technical/PHASE_3A_2E_EOS60D_STABLE_USB_CAPABILITY_VALIDATION.md`.


---

## Phase 3A-2F — EOS 60D single-shot original transfer (2026-11-12)

**BLOCKED — no shutter sent.**

- Preflight PASS: EOS 60D USB/connected, warning preserved (type 0/category 0),
  78 properties, 1 storage device, 724 shots, Live View 1056×704, clean
  disconnect/exit without reconnect.
- CascableCore 18.0.2 exposes `CameraInitiatedTransferRequest` only after a
  photograph; no pre-capture API can confirm `canProvide(.original)`.
- The mandatory Step 2 condition therefore cannot be satisfied. No shutter,
  transfer, JPEG, SHA-256 or camera-file operation was performed.
- Mac harness build PASS; iOS production build PASS (175 MB, bundle unchanged,
  no licence); Flutter 96/Python 39 PASS.
- Full report: `docs/technical/PHASE_3A_2F_EOS60D_SINGLE_SHOT_ORIGINAL_TRANSFER.md`.


---

## Phase 3A-2G — Authorized single-shot original transfer (2026-11-12)

**PARTIAL — one shutter; `.original` received as CR2, not JPEG; no JPEG saved.**

- Exactly one shutter request issued; no retry/second capture.
- Transfer handler registered before capture; capture ID
  `cap_146a585b-1a31-4f15-8e42-fe21b81a51de`.
- Transfer request valid, `canProvide(.original)=true`, predicted and received
  original bytes both 14,069,528; filename `IMG_9646.CR2`.
- JPEG signature false; CR2 SHA-256
  `a3e23b566c5595495da8ef98637579df63448e57d563ea37a76442fa32211742`.
- No preview substitution; no JPEG saved; no camera file modification.
- A second transfer request for the same capture was ignored; its nature is not
  claimed.
- Clean Live View stop/disconnect; no reconnect; camera remained USB-enumerated.
- Next: user must set camera JPEG-only and authorize a new single-shot test.
- Mac harness build PASS; iOS production build PASS (175 MB, bundle unchanged,
  no licence); Flutter 96/Python 39 PASS.
- Full report: `docs/technical/PHASE_3A_2G_AUTHORIZED_SINGLE_SHOT_ORIGINAL_TRANSFER.md`.


---

## Phase 3A-2H — JPEG-only single-shot validation (2026-11-12)

**BLOCKED — discovery failed before shutter; no JPEG.**

- USB enumeration present; camera session `22310120635878`; no user camera app.
- Earlier no-shutter preflight: EOS 60D connected, 78 properties, 1 storage,
  3014 shots, Live View 1056×704, warning type 0/category 0; Image Quality
  property current=nil.
- Authorized transfer run: USB-only discovery started but timed out with no
  discovered/connected/transfer/shutter event.
- No shutter, transfer, JPEG, SHA or camera-file operation; no second attempt.
- Mac harness build PASS; iOS production build PASS (175 MB, bundle unchanged,
  no licence); Flutter 96/Python 39 PASS.
- Full report: `docs/technical/PHASE_3A_2H_SINGLE_SHOT_ORIGINAL_JPEG_VALIDATION.md`.


---

## Phase 3A-2J — Test orchestration safety hardening (2026-11-12)

**PASS — safe orchestration only; no camera/Studio interaction.**

- Added canonical `macos_cascable_demo/orchestration/run-safe-test.sh` with
  explicit `source`, `process`, gated `capability`, and gated `transfer` modes.
- Removed destructive orchestration from the active path: no executable
  osascript/pkill/killall/launchctl/external-process termination.
- Added a read-only competing-camera-app guard using `ps`/`grep`; it aborts
  with a manual-close instruction and never terminates another app.
- Source/process modes executed with `CAMERA_COMMAND=false`; hardware modes
  refused without explicit flags/authorization. Synthetic guard fixture
  aborted safely (RC 2) with no process action.
- Logs now record timestamp, command, mode, guard result, abort state and
  camera-command flag.
- No shutdown, discovery, connection, shutter, transfer, settings or file
  operation occurred; Studio was not terminated.
- Full report: `docs/technical/PHASE_3A_2J_TEST_ORCHESTRATION_SAFETY.md`.


---

## Phase 3A-2K — Clean capability preflight through safe orchestration (2026-11-12)

**PARTIAL — capability PASS; Live View cleanup error.**

- Safe orchestration invocation: `--mode capability --allow-hardware
  --authorization capability-preflight`; guard PASS; no transfer/single-shot.
- USB before/after: Canon EOS 60D, session 22335655082079, location 34668544,
  480 Mbps, vendor 1193/product 12821.
- Discovery/connection PASS; 78 properties; `supportedFunctionality` 447936;
  stillsShooting/filesystemAccess; 1 storage, 3014 shots; warning type 0/category 0.
- Live View real 1056×704 frame. On cleanup, Live View terminated with reason 2 /
  error 1008; SDK disconnect completed with no error; camera remained USB.
- Image Quality property nil/unknown; JPEG-only not independently verified.
- No shutter, transfer, settings change, camera file operation, Studio
  termination, retry or reconnect.
- No production integration changed.
- Full report: `docs/technical/PHASE_3A_2K_CLEAN_USB_CAPABILITY_PREFLIGHT.md`.


---

## Phase 3A-2L — Live View lifecycle cleanup correction (2026-11-12)

**PASS for source/static correction; hardware unverified.**

- Investigated SDK docs: `endStream()` is asynchronous and the termination
  handler is the only supported stop confirmation; reason 2 = Failed; error 1008
  = NotAvailable (not NotConnected).
- Corrected cleanup to request `endStream()`, wait for termination callback, then
  remove transfer handler and disconnect; 3s bounded fallback logs an
  unconfirmed stop and never pretends clean termination. Cleanup is once-only;
  camera retained until disconnect callback.
- Shutter/transfer code unchanged; no hardware run, no discovery/connection,
  no shutter/transfer/settings/file/Studio operation.
- macOS harness build PASS; Flutter analyze PASS; safe source/process modes PASS.
- Full report: `docs/technical/PHASE_3A_2L_LIVE_VIEW_LIFECYCLE_CLEANUP_CORRECTION.md`.


---

## Phase 3A-2M — Live View lifecycle hardware verification (2026-11-12)

**PARTIAL — cleanup ordering works; camera still fails normal endStream.**

- One capability-only run through safe orchestration; guard PASS; no shutter/
  transfer flags.
- USB before/after: Canon EOS 60D, session 22351073318200, location 17956864,
  480 Mbps, vendor 1193/product 12821.
- Discovery/connection PASS; warning type 0/category 0; 78 properties;
  1 storage, 3014 shots; Live View 1056×704.
- `endStream()` requested; termination callback arrived **before** disconnect
  with reason 2/error 1008 (NotAvailable). The 3-second fallback was not used.
- Disconnect completed with no error after the callback; no reconnect; camera
  remained USB-enumerated. No shutter/transfer/settings/files/Studio operation.
- Conclusion: 2L ordering fix is correct but insufficient; endStream failure is
  a camera/SDK lifecycle limitation, not solely a disconnect race.
- Full report: `docs/technical/PHASE_3A_2M_LIVE_VIEW_LIFECYCLE_HARDWARE_VERIFICATION.md`.


---

## Phase 4A — Event management and booth session foundation (2026-11-12)

**PASS — software vertical slice verified with MockCameraService; no hardware changes.**

- Baseline 96 Flutter tests; final **110 Flutter tests passing**, Flutter analyze
  clean, **39 Python bridge tests passing**.
- Added typed event status/configuration and session records; additive JSON
  fields and safe defaults for existing events/sessions; no new database.
- Added event list search/filter, full create/edit forms, explicit lifecycle
  transitions, archive/draft-delete rules, event details, session history and
  selected-event persistence.
- Added active session clock/status/end confirmation, interrupted-session
  recovery, complete review restore, session photo counts and event-level
  template configuration.
- `flutter build ios --simulator --no-codesign` PASS; production bundle
  `com.terabooth.teraboothIpad`; no demo licence embedded.
- No camera, bridge, QR, GIF, printer or Windows behavior changed.
- Full report: `docs/technical/PHASE_4A_EVENT_MANAGEMENT_AND_SESSION_FOUNDATION.md`.


---

## Phase 4B — Configurable capture, branding and session close-out (2026-11-12)

**PASS for software slice; no hardware.**

- Configurable event photo count 1–4 and countdown Off/3/5/10; session snapshots;
  variable review/retake; countdown cancellation before shutter.
- Added 1/2/4-photo bridge templates and branding metadata/logo upload; bridge
  renders branded 1200×1800 derived JPEGs while originals stay unchanged.
- Added branding editor/logo validation/local atomic asset storage and preview;
  session branding snapshot independent of later event edits.
- Added explicit interrupted-session Resume / Close & recover / Cancel UI;
  trailing-slot resume preserves originals/capture IDs; missing files disable
  resume and close marks recovered.
- Added EventReport CSV export for event/session close-out.
- Verification: 123 Flutter tests, 42 bridge tests, analyze clean, iOS simulator
  build PASS, bundle `com.terabooth.teraboothIpad`, no demo licence.
- Known limit: bridge GIF generation remains 3-frame, so 1/2/4-photo sessions do
  not produce a guest GIF. No QR/GIF code changed.
- Full report: `docs/technical/PHASE_4B_CONFIGURABLE_CAPTURE_BRANDING_AND_SESSION_CLOSEOUT.md`.


---

## Phase 4C — Guest experience, local gallery and QR delivery (2026-11-12)

**PASS for software slice; LAN service smoke-tested; no physical phone/camera/DNP.**

- Extended existing `/d/{token}` delivery path rather than a second gallery:
  short opaque tokens, revocation/regeneration, expiry, scoped originals/strip/GIF,
  mobile-first gallery, manifest and ZIP download.
- Added session asset manifest (persisted atomically), guest logo/color/title,
  security headers and no-path manifest.
- GIF generation now supports 1–4 approved frames in photo order; one-photo GIF
  is a valid still GIF; missing/invalid frames fail explicitly; regeneration is
  idempotent and originals remain untouched.
- Added LAN URL discovery/`TERABOOTH_PUBLIC_BASE_URL`, non-loopback QR generation,
  operator revoke/regenerate/copy QR actions and asset readiness feedback.
- Verification: 124 Flutter tests, 47 bridge tests, analyze clean, simulator
  build PASS; actual uvicorn bound to 0.0.0.0 reached through LAN IP with page,
  manifest and ZIP 200. Physical guest phone/Windows/DNP not tested.
- Report: `docs/technical/PHASE_4C_GUEST_EXPERIENCE_LOCAL_QR_DELIVERY.md`.


---

## Phase 5A-1 — Windows bridge portability/low-resource foundation (2026-11-12)

**PASS for portable software foundation; no physical Windows test.**

- Added validated env/file configuration (host/port/assets/data), generated
  persisted delivery secret (no source secret default), and startup diagnostics.
- Added OS-backed single-instance lock, port preflight, portable foreground
  launcher, clean task cancellation, runtime-only dependency file, Python
  version check and configurable firewall port.
- Bounded print/GIF/ZIP work with semaphores; ZIP now streams from a temp file,
  not memory; manifest/GIF replacements use retrying atomic replaces.
- Added lightweight `/v1/diagnostics` (RSS/CPU/queue/active tasks/disk).
- Benchmarked macOS: startup 0.417s, idle 57.7MB, post-4-photo GIF 108.9MB,
  post guest requests 109.2MB, 5 page+5 ZIP requests 0.09s. Composed JPEGs also use retrying atomic replacement.
- Tests: 53 bridge passed, 124 Flutter passed, analyze clean, iOS build PASS.
  Manual launcher checks: second instance/port conflict RC 2.
- Report: `docs/technical/PHASE_5A_1_WINDOWS_BRIDGE_PORTABILITY_AND_LOW_RESOURCE_FOUNDATION.md`.


---

## Phase 5A-2 — Actual Windows runtime validation (2026-11-12)

**BLOCKED — no Windows host accessible from this session; no Windows results claimed.**

- Inspected Phase 5A-1 launcher/config/runtime/tests.
- Added runtime-only Windows validation package under `windows_bridge/validation/`
  (preflight, approved runtime install, import/filesystem checks, disposable
  bridge/guest/restart validation).
- No Windows installation, startup, filesystem, memory, network or restart test
  was performed; all such items are NOT TESTED.
- Mac-side regression remains 53 bridge tests, 124 Flutter tests, clean analyze
  and simulator build. These are not Windows evidence.
- Validation report: `docs/technical/PHASE_5A_2_ACTUAL_WINDOWS_RUNTIME_VALIDATION.md`.
