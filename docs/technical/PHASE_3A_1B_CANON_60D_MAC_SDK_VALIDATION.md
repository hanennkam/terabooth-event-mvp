# Phase 3A-1B — Canon EOS 60D macOS SDK Physical Validation

**Date:** 2026-11-12  
**Camera:** Canon EOS 60D (physical)  
**Mac:** MacBookPro18,1, macOS 26.5.1 (25F80), Apple silicon  
**SDK:** CascableCore 18.0.2  
**Demo licence:** `se.cascable.CascableCoreMacDemo`  
**Result:** **PASS for the tested macOS subset. PARTIAL overall; iPadOS and image transfer remain unverified.**

---

## 1. Environment and isolation

| Item | Value |
|---|---|
| macOS | 26.5.1 (25F80) |
| Hardware | MacBookPro18,1 |
| Xcode | 26.6 (17F113) |
| SDK | CascableCore 18.0.2 (SPM remote) |
| Mac demo target | `TeraboothCascableMacDemo` |
| Mac Bundle ID | **`se.cascable.CascableCoreMacDemo`** |
| Licence | locally supplied, ignored, not committed |
| Demo app | `/tmp/TeraboothMacDemoDerived/Build/Products/Debug/TeraboothCascableMacDemo.app` |

The macOS demo is a separate **native AppKit** target under
`macos_cascable_demo/`. The production iPad project and production bundle ID
`com.terabooth.teraboothIpad` were not modified.

The official demo repository has **no native macOS target**; its two targets
are iOS targets that can run as Mac Catalyst apps. Because the task requires
native macOS semantics, a minimal AppKit target was created instead of reusing
the iOS scheme.

### Dependencies

The Mac project uses the official remote SPM repository:

```text
https://github.com/Cascable/cascablecore-distribution @ 18.0.2
revision 4407ce7682e82bb0b152ddcfad4cfd98609941fa
```

`Package.resolved` is at:

```text
macos_cascable_demo/TeraboothCascableMacDemo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

No temporary local package path is used. The optional `CascableCoreSwift`
product is not required by this probe.

---

## 2. Licence verification

The same locally supplied licence bytes were copied into the ignored Mac demo
resource and applied with the official API. No bytes were printed.

```text
CASCABLE_MAC_LICENSE_RESULT=0
CASCABLE_MAC_BUNDLE=se.cascable.CascableCoreMacDemo
```

`0` is `LicenseVerificationResult.success`.

---

## 3. Physical discovery and connection

Before the run:

- Cascable Studio was quit.
- No Canon EOS Utility or other camera-owning process remained.
- The Canon EOS 60D was powered on.
- USB enumeration showed:
  - `USB Product Name = Canon Digital Camera`
  - `USB Vendor Name = Canon Inc.`
  - `idVendor = 1193`

The app requested USB-only discovery.

### Exact log

```text
CASCABLE_MAC_DISCOVERY=started mode=usbOnly
CASCABLE_MAC_DISCOVERED vendor=Canon Inc. model=Canon EOS 60D transport=CBLCameraTransport(rawValue: 1) state=0
CASCABLE_MAC_CONNECT=requested
CASCABLE_MAC_CONNECT=connected warnings=1 state=2 model=Canon EOS 60D transport=CBLCameraTransport(rawValue: 1)
CASCABLE_MAC_WARNING type=0 category=0
```

`CBLCameraTransport(rawValue: 1)` is `CBLCameraTransportUSB`.
`connectionState 0` is not connected; `2` is connected.

Connection warning:

- type `0` = `LowerThanExpectedFunctionality`
- category `0` = `RemoteControl`

This is a reported limitation, not a connection failure. It means the SDK
considers some expected remote-control functionality unavailable on this
camera/connection.

---

## 4. Remote settings read

The SDK reported **77 known property identifiers**.

```text
CASCABLE_MAC_SETTINGS=known_identifiers 77
CASCABLE_MAC_STORAGE=devices 0
CASCABLE_MAC_STORAGE=shots_available 0
CASCABLE_MAC_SETTING id=2 name=Aperture value=5
CASCABLE_MAC_SETTING id=1 name=Shutter Speed value=⅟80
CASCABLE_MAC_SETTING id=0 name=ISO value=5000
CASCABLE_MAC_SETTING id=9 name=AE Mode value=M
CASCABLE_MAC_SETTING id=4 name=Battery Power value=3/4
CASCABLE_MAC_SETTING id=21 name= value=nil
```

This validates the settings **read** path and camera status reporting. The
settings **write** path was not exercised; no camera setting was changed. The empty image-quality value
and zero storage/shot counts are consistent with the missing SD card. They are
not treated as an SDK failure.

---

## 5. Live View

Live View started after connection and delivered a real frame:

```text
CASCABLE_MAC_LIVE_VIEW=started
CASCABLE_MAC_LIVE_VIEW=frame size=(1056.0, 704.0) format=0
```

`format 0` is the SDK's JPEG live-view frame format. This is actual frame
delivery from the physical EOS 60D, not a simulated frame.

Live View stopped cleanly on disconnect:

```text
CASCABLE_MAC_LIVE_VIEW=terminated reason=0 error=none
```

`reason 0` is `EndedNormally`.

---

## 6. Single shutter request

Exactly one shutter request was issued during the first physical run:

```text
CASCABLE_MAC_SHUTTER=requested error=none
```

The SDK accepted the request without a returned error. This does **not** prove:

- that a physical image was written,
- that an original JPEG was transferred,
- that the no-SD-card condition was harmless.

The second run used `--no-shutter`; no further shutter was triggered:

```text
CASCABLE_MAC_SHUTTER=skipped
```

No original JPEG transfer was attempted or claimed.

---

## 7. Disconnect and reconnect

```text
CASCABLE_MAC_DISCONNECT=requested
CASCABLE_MAC_LIVE_VIEW=terminated reason=0 error=none
CASCABLE_MAC_LOST_SIGHT model=Canon EOS 60D
CASCABLE_MAC_DISCONNECT=complete error=none
CASCABLE_MAC_RECONNECT=search_started
CASCABLE_MAC_DISCOVERED vendor=Canon Inc. model=Canon EOS 60D transport=CBLCameraTransport(rawValue: 1) state=0
CASCABLE_MAC_CONNECT=requested
CASCABLE_MAC_CONNECT=connected warnings=1 state=2 model=Canon EOS 60D transport=CBLCameraTransport(rawValue: 1)
CASCABLE_MAC_LIVE_VIEW=started
```

The EOS 60D was rediscovered and reconnected over USB. No second shutter was
issued during reconnection.

---

## 8. Comparison with Cascable Studio

| Capability | Cascable Studio (user-observed) | CascableCore 18.0.2 macOS SDK |
|---|---|---|
| USB discovery/connection | **PASS** | **PASS** |
| Camera model identification | PASS | **PASS — Canon EOS 60D** |
| Remote settings | **PASS** | **PASS for reading 77 settings; write not exercised** |
| Real-time Live View | **PASS** | **PASS — 1056×704 frame** |
| Camera control | **PASS** | **PASS — shutter request accepted; disconnect/reconnect** |
| Original image transfer | Not tested (no SD card) | **NOT TESTED / NOT CLAIMED** |

The SDK reproduces the previously observed Studio capabilities for USB
connection, settings, Live View and control. Image transfer remains untested in
both cases because no SD card is available.

The SDK reports a `LowerThanExpectedFunctionality`/`RemoteControl` warning even
though the tested functions work. This is an SDK functionality classification,
not a discovery failure.

---

## 9. Missing SD card

Observed:

```text
CASCABLE_MAC_STORAGE=devices 0
CASCABLE_MAC_STORAGE=shots_available 0
CASCABLE_MAC_SETTING id=21 name= value=nil
```

The camera has no SD card. Do not interpret this as SDK incompatibility. Do not
claim original JPEG capture or transfer. A later test with a card must verify:

- file creation,
- original JPEG transfer,
- file size/EXIF,
- storage warnings/errors,
- repeated capture without corruption.

---

## 10. Limitations and remaining iPad work

This is **macOS USB validation only**. It does not prove iPadOS USB behavior.

Still required on a physical iPad:

- USB adapter/cable detection and iPadOS authorization.
- CascableCore discovery over USB on iPadOS.
- Connection/authentication and state events.
- Settings read/write.
- Live View frame delivery/rendering.
- Shutter and original JPEG transfer.
- Disconnect/reconnect and cable-pull behavior.
- Ten-session stability.
- App background/foreground behavior.

The EOS 60D is still absent from Cascable's official Canon compatibility list.
The successful macOS test is empirical evidence for this SDK/camera/firmware
combination, not a guarantee of iPadOS support or all EOS 60D features.

---

## 11. Files and commands

Mac demo:

- `macos_cascable_demo/TeraboothCascableMacDemo.xcodeproj`
- `macos_cascable_demo/main.swift`
- `macos_cascable_demo/Info.plist`
- `macos_cascable_demo/Package.resolved` (workspace)
- `macos_cascable_demo/CascableCoreLicense.licence` (ignored, 0600)

Build:

```bash
cd macos_cascable_demo
xcodebuild -project TeraboothCascableMacDemo.xcodeproj \
  -scheme TeraboothCascableMacDemo \
  -configuration Debug \
  -derivedDataPath /tmp/TeraboothMacDemoDerived build
```

Run (physical camera connected, Studio closed):

```bash
/tmp/TeraboothMacDemoDerived/Build/Products/Debug/TeraboothCascableMacDemo.app/Contents/MacOS/TeraboothCascableMacDemo
```

Run without a shutter request:

```bash
.../TeraboothCascableMacDemo --no-shutter
```

---

## 12. Terabooth architecture implications

Current path:

```text
BoothController
  → CameraPipeline
  → CameraService
  → ImageIngestor
  → StorageService
```

The recommended iPad boundary remains unchanged:

```text
CameraService
  ├─ MockCameraService          (keep as default)
  ├─ NativeCameraService        (existing channel scaffold)
  └─ CascableCoreCameraService  (future)
```

A future native Swift `CascableCameraAdapter` should own the physical
`Camera`, discovery/connection, settings, Live View, shutter correlation and
JPEG transfer. Dart should see only the SDK-independent MethodChannel/EventChannel
contract; no CascableCore types cross the boundary.

The adapter must return a capture only after accepted original-image bytes have
arrived and been validated. The macOS test does not justify implementing this
adapter on iPadOS yet, because USB authorization, discovery, Live View and
transfer behavior may differ on iPadOS.

Constraints retained:

- `MockCameraService` remains the default.
- `CameraPipeline` and `CameraService` were not modified.
- Camera control stays on iPad, not Windows.
- Printing/GIF/QR/Windows Bridge were not changed.
- No production CameraService adapter was implemented in this phase.

---

## 13. Final result

**macOS SDK subset: PASS**

- Licence: **PASS**
- USB discovery: **PASS**
- Model identification: **PASS — Canon EOS 60D**
- Connection: **PASS**
- Settings read: **PASS**
- Live View: **PASS**
- Single shutter request: **PASS as request only**
- Disconnect/reconnect: **PASS**
- Original JPEG transfer: **NOT TESTED / NOT CLAIMED**
- iPadOS USB: **NOT TESTED**
