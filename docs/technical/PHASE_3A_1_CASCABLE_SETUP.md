# Phase 3A-1 — CascableCore SDK Setup, Demo Build & Simulated Camera

**Date:** 2026-11-12  
**Result:** **PARTIAL — licence/SPM resolved, simulated validation passed, and the EOS 60D macOS physical subset later passed (Phase 3A-1B); iPadOS/image transfer remain blocked.**  
**Stated licence expiry:** 12 December 2026 (not verifiable without the issued licence bytes).  
The SDK is linked, a dedicated demo build is configured, the demo app launches with the licensed bundle ID, licence verification succeeds, and the official Simulated Camera completes discovery/connection/Live View/shutter/preview/disconnect. No physical EOS 60D is available.

> **Follow-up:** see [PHASE_3A_1A_LICENCE_AND_SPM.md](PHASE_3A_1A_LICENCE_AND_SPM.md) for activation and SPM evidence.

> **Target correction:** the camera is a **Canon EOS 60D**, not a Canon EOS R. Older documents that mention EOS R are superseded for camera decisions by this document. Do not claim EOS 60D compatibility.

---

## 1. Official dependencies and versions

| Package | URL | Version used | Products |
|---|---|---|---|
| CascableCore distribution | `https://github.com/Cascable/cascablecore-distribution` | `18.0.2` | `CascableCore` (includes `StopKit`) |
| CascableCoreSwift | `https://github.com/Cascable/cascablecore-swift` | `18.0.2` | `CascableCoreSwift` |
| CascableCore Simulated Camera | `https://github.com/Cascable/cascablecore-simulated-camera` | `1.0.14` | `CascableCoreSimulatedCamera` |

Verified from the official `Package.swift` files:

- Swift tools version: **5.9**
- Minimum platforms: **iOS 14**, macOS 11, Mac Catalyst 15, visionOS 1.1
- Distribution has no external package dependencies.
- `CascableCoreSwift` depends on `cascablecore-distribution` from `18.0.2`.
- Simulated Camera depends on `cascablecore-distribution` from `18.0.1`.
- `CascableCoreSwift` was added because official Swift examples use it for
  `CameraDiscovery.shared`, Combine live view, and Swift convenience APIs.
  The demo probe itself uses the binary `CascableCore` API only.

**No proprietary SDK source or licence material was copied into this repository.**

---

## 2. Xcode/SPM installation

### Project changes

- Added the three official SPM package references above.
- Linked `CascableCore`, `CascableCoreSwift`, and `CascableCoreSimulatedCamera`
  to the `Runner` target.
- Raised **all** Runner/project deployment targets from iOS 13 to **iOS 14**
  because CascableCore requires iOS 14.
- Existing production bundle ID remains **`com.terabooth.teraboothIpad`**.
- Added a separate **`Debug-CascableDemo`** build configuration:
  - Bundle ID: **`se.cascable.CascableCoreiOSDemo`**
  - Swift condition: `DEBUG CASCABLE_DEMO`
  - iOS deployment target: 14.0
  - Product name unchanged: `Runner.app`
- Added shared scheme **`Runner-CascableDemo`** based on the working Flutter
  Runner scheme (including Flutter's prepare action).
- Existing production `Runner` scheme and production bundle configuration are
  preserved.

### SPM resolution

Official remote resolution now succeeds. The initial full-history Git transport
stall was isolated to Xcode's clone operation. Shallow official repositories were
used only to seed SwiftPM's cache; the project references only the official
remote URLs and contains `Package.resolved` with 18.0.2 / 1.0.14 pins. See
`PHASE_3A_1A_LICENCE_AND_SPM.md` for the diagnosis and commands.

---

## 3. Bundle IDs and signing

| Configuration | Bundle ID | Status |
|---|---|---|
| Debug | `com.terabooth.teraboothIpad` | Preserved |
| Release | `com.terabooth.teraboothIpad` | Preserved |
| Profile | `com.terabooth.teraboothIpad` | Preserved |
| Debug-CascableDemo | `se.cascable.CascableCoreiOSDemo` | Added |

Verified from the built demo app:

```text
bundle=se.cascable.CascableCoreiOSDemo
```

Verified from the production build:

```text
prod_bundle=com.terabooth.teraboothIpad
```

**Signing:** simulator builds use automatic signing with no provisioning
profile requirement. A physical demo install would require the Apple team and
a provisioning profile capable of using `se.cascable.CascableCoreiOSDemo`;
that has not been tested. No physical iPad is available.

No App Store distribution is configured or intended.

---

## 4. Info.plist and permissions

The existing Runner `Info.plist` already contains the required local-network and
camera declarations:

- `NSLocalNetworkUsageDescription`
- `NSBonjourServices` → `_ptp._tcp`
- `NSCameraUsageDescription`
- `NSAppTransportSecurity` → `NSAllowsLocalNetworking`

No additional privacy key was required for the SDK at this stage. Wired-camera
authorization is an OS prompt handled by
`attemptToObtainWiredCameraAuthorization(completionHandler:)`; it is not an
Info.plist string.

The app does not request photo-library access.

---

## 5. Licence validation

**PASS — official SDK result `0` (`success`).**

The supplied demo licence archive contained the official
`CascableCoreLicense.swift`/`.h`/`.m` files. Its embedded byte array was
converted locally to the ignored binary path:

```text
ipad_app/ios/Runner/CascableCoreLicense.licence
```

No licence bytes, key or token are printed or committed. The archive was moved
out of the repository; `.gitignore` covers the binary and zip names. The demo
copy phase is restricted to `Debug-CascableDemo`, so production does not contain
the licence.

Actual launch evidence:

```text
CASCABLE_DEMO_LICENSE_RESULT=0 configured=true
CASCABLE_DEMO_LICENSE=applied
```

The demo bundle contains a 471-byte licence; the production bundle has no
licence file.

## 6. Simulated Camera

The official `CascableCoreSimulatedCamera` plugin is linked and loaded:

```text
CASCABLE_DEMO_PLUGINS=["se.cascable.CascableCore.plugin.simulated-camera"]
```

Actual simulated results:

```text
CASCABLE_DEMO_DISCOVERY=started
CASCABLE_DEMO_DISCOVERED=Simulated Camera transport=CBLCameraTransport(rawValue: 0)
CASCABLE_DEMO_LOST_SIGHT=Simulated Camera
CASCABLE_DEMO_CONNECT=connected warnings=0 state=CBLCameraConnectionState(rawValue: 2)
CASCABLE_DEMO_CAPTURE_REQUEST=sent error=none
CASCABLE_DEMO_LIVE_VIEW=frame size=(864.0, 576.0) format=CBLCameraLiveViewFramePixelFormat(rawValue: 0)
CASCABLE_DEMO_TRANSFER=preview_available
CASCABLE_DEMO_TRANSFER=preview_received size=(864.0, 576.0)
CASCABLE_DEMO_DISCONNECT=requested
CASCABLE_DEMO_LIVE_VIEW=terminated reason=CBLCameraLiveViewTerminationReason(rawValue: 0) error=none
CASCABLE_DEMO_DISCONNECT=complete error=none
```

| Test | Result |
|---|---|
| SDK initialization / licence | **PASS** |
| Discovery | **PASS** |
| Connection/state | **PASS** |
| Live View | **PASS — 864×576 frame** |
| Shutter request | **PASS — request sent** |
| Preview transfer | **PASS — 864×576** |
| Disconnect | **PASS** |
| Original JPEG transfer | **NOT SUPPORTED by simulated plugin / NOT TESTED** |

The shutter callback only confirms the request was sent. No physical shutter,
original JPEG or EOS 60D behavior is claimed.

## 7. Canon EOS 60D compatibility investigation

### Official evidence

- Cascable's current **Canon compatibility index** lists many Canon EOS models,
  but **not the EOS 60D**:
  <https://compatibility.cascable.se/canon/>
- The direct model URL `https://compatibility.cascable.se/canon/eos-60d/`
  returns **404**.
- Cascable's wired-camera guide says wired Canon EOS cameras support
  full-featured remote control in **PC Remote** mode:
  <https://cascable.se/help/wired-cameras/>
- Canon's EOS 60D USB support page documents EOS Utility tethering, not a
  Cascable-supported PTP/PC Remote contract:
  <https://id.canon/id/support/8200843500>

### Compatibility matrix

| Capability | EOS 60D evidence | Verdict |
|---|---|---|
| USB transport through CascableCore | No official 60D model entry | **UNVERIFIED / not listed** |
| Remote shutter | No official 60D entry | **UNVERIFIED** |
| Live View | No official 60D entry | **UNVERIFIED** |
| Original JPEG transfer | No official 60D entry; simulated camera explicitly lacks original transfer | **UNVERIFIED** |
| PTP mode over USB on iPadOS | No official 60D/Cascable PTP statement | **UNVERIFIED** |
| Required camera settings | Not documented for 60D by Cascable | **UNKNOWN — do not guess** |

**Conclusion:** there is no evidence-based basis to claim EOS 60D compatibility.
The generic statement that many Canon EOS cameras work is not model-specific
evidence and cannot be used as a compatibility claim.

Do not implement model-specific workarounds, PTP mode switching, or fake
success based on assumptions. A physical EOS 60D and a supported USB/PTP path
must be tested before any camera integration proceeds.

---

## 8. Architecture integration assessment

### Current path

```text
BoothController
  → CameraPipeline
    → CameraService (Dart interface)
      → NativeCameraService or MockCameraService
    → ImageIngestor (validation/normalization)
  → StorageService
```

Relevant files:

- `lib/services/camera_service.dart`
- `lib/services/native_camera_service.dart`
- `lib/services/camera_contract.dart`
- `lib/services/camera_pipeline.dart`
- `lib/main.dart`
- `ios/Runner/AppDelegate.swift` (`CameraPlugin` stub)

### Exact adapter boundary

The correct boundary is the existing **Dart `CameraService` interface**:

```text
BoothController → CameraPipeline → CameraService
                                      ├─ MockCameraService
                                      ├─ NativeCameraService
                                      └─ CascableCoreCameraService (future)
```

`CascableCoreCameraService` should be a Dart implementation that talks only to
the Terabooth MethodChannel/EventChannel contract. SDK types must not cross the
Flutter boundary.

On the native side, a future `CascableCameraAdapter` should own:

- the `Camera` reference
- discovery and connection state
- Live View frame delivery
- shutter request correlation
- original JPEG transfer completion
- disconnect/reconnect events

It must only return a capture after the **original JPEG bytes have arrived and
been validated**. The SDK shutter callback means "request sent", not "photo
captured".

### Selection by build configuration

Recommended:

- Production/default remains `MockCameraService`.
- Demo/native selection requires an explicit Dart define
  (`TERABOOTH_CAMERA_BACKEND=cascable`) plus the `CASCABLE_DEMO` native build
  condition.
- No silent fallback to mock on a native error when the operator believes a
  real camera is selected.
- `MockCameraService` is not removed or replaced in this phase.

No production adapter, capture flow, reliability retry, or camera topology
change was made in Phase 3A-1.

---

## 9. Build and test results

| Check | Result |
|---|---|
| Demo build `Debug-CascableDemo` (official remote SPM) | **BUILD SUCCEEDED** |
| Demo bundle ID | `se.cascable.CascableCoreiOSDemo` |
| Demo launch in iPad Simulator | **PASS** |
| SDK frameworks embedded/loading | **PASS** |
| Simulated plugin loaded | **PASS** |
| Licence verification | **PASS — result 0** |
| Production build `flutter build ios --simulator --debug` | **PASS — 174 MB; no licence embedded** |
| Production bundle ID | `com.terabooth.teraboothIpad` |
| `flutter analyze` | **No issues** |
| Flutter tests | **87 passed** |
| Python tests | **39 passed** |
| Remote SPM resolution | **PASS — official 18.0.2 / 1.0.14 pins** |
| Physical iPad signing | **NOT TESTED** |
| EOS 60D USB/capture | **NOT TESTED** |

The demo build used the official CascableCore 18.0.2 and Simulated Camera
1.0.14 binaries through a temporary local package because remote SPM resolution
did not complete. The repository's final project references are the official
remote URLs.

---

## 10. Files changed

- `ipad_app/ios/Runner.xcodeproj/project.pbxproj`
- `ipad_app/ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner-CascableDemo.xcscheme`
- `ipad_app/ios/Runner/AppDelegate.swift`
- `ipad_app/ios/Runner/CascableCoreLicense.swift`
- `ipad_app/ios/Runner/CascableCoreDemoProbe.swift`
- `ipad_app/.gitignore`
- `ipad_app/lib/services/camera_service.dart` (EOS 60D label only)
- `ipad_app/lib/services/native_camera_service.dart` (EOS 60D label only)
- `ipad_app/lib/screens/capture_screen.dart` (EOS 60D label only)
- `ipad_app/lib/screens/welcome_screen.dart` (EOS 60D label only)
- `README.md`
- `docs/EVENT_DAY_RUNBOOK.md`
- `docs/IMPLEMENTATION_LOG.md`
- this document

No printing, GIF, QR, Windows Bridge, camera topology, MockCameraService, or
capture pipeline behavior was changed.

---

## 11. Remaining blockers

1. **EOS 60D compatibility** — absent from Cascable's official Canon list;
   USB/PTP/remote shutter/Live View/original JPEG remain unverified.
2. **Original JPEG transfer** — simulated plugin does not support it; physical
   EOS 60D test required.
3. **Physical iPad signing/install** — no Apple team/profile or device test.
4. **Optional CascableCoreSwift** — resolved but unlinked; requires Apple's
   Metal Toolchain if the Swift Live View rendering APIs are adopted.
5. **Production camera integration** — intentionally not started.

**No EOS 60D compatibility or physical readiness is claimed.**
