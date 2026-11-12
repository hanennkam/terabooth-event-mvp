# Phase 3A-2A — iOS CascableCore Camera Adapter Foundation

**Date:** 2026-11-12  
**Result:** **PARTIAL / PASS for adapter foundation build-and-test. Physical iPad validation remains BLOCKED.**

The native adapter foundation is implemented and compiles against CascableCore 18.0.2.
`MockCameraService` remains the default. No physical iPad USB test or original
JPEG transfer is claimed.

---

## 1. Existing contract audit

### Flutter interfaces

`CameraService` (`lib/services/camera_service.dart`) is the authoritative
abstraction:

```dart
abstract class CameraService {
  String get name;
  bool get isSimulated;
  Future<void> connect();
  Future<void> disconnect();
  Future<CapturedImage> capture({String? captureId});
}
```

- `MockCameraService` generates labelled 1200×1800 PNG images and is the
  existing default in `main.dart`.
- `NativeCameraService` uses:
  - MethodChannel `com.terabooth/camera`
  - EventChannel `com.terabooth/camera/events`
- `CascableCameraService` was a placeholder; it now delegates to
  `NativeCameraService` and is still not the default.
- `CameraPipeline` owns the separate connection/capture state machine,
  serializes captures, generates capture IDs, applies `captureTimeout`, and
  calls `ImageIngestor`.
- `ImageIngestor` validates JPEG/PNG, checks dimensions and decodeability,
  de-duplicates capture IDs, atomically stores originals, reopens and
  revalidates the saved file, and never recompresses.
- `BoothController` remains the workflow owner; Retake All is unchanged.

### Existing MethodChannel methods

`initialize`, `startDiscovery`, `stopDiscovery`, `connect`, `disconnect`,
`capture`, `status`, `startLiveView`, `stopLiveView`, `dispose`.

### Existing EventChannel types

`discovery`, `connection`, `capture`, `liveViewFrame`, `error`.

### Native channel payload

All values are Foundation/Flutter-serializable:

- discovery: `id`, `model`, `manufacturer`, `transport`, `state`
- connection: `id`, `model`, `state`, `warnings`, optional `message`
- capture: `captureId`, `state`, optional `byteCount`, `code`, `message`
- live view: `bytes` (base64 JPEG), `width`, `height`
- capture method response: `captureId`, `bytes` (base64 JPEG), `width`, `height`

No `Camera`, `CameraDiscovery`, transfer, or property objects cross the
channel.

---

## 2. EOS 60D `LowerThanExpectedFunctionality` warning

### What it means

The 3A-1B macOS connection returned:

```text
CASCABLE_MAC_WARNING type=0 category=0
```

Official enum meaning:

- type `0` = `CBLCameraConnectionWarningTypeLowerThanExpectedFunctionality`
- category `0` = `CBLCameraConnectionWarningCategoryRemoteControl`

The SDK header describes this as: the camera has lower than expected
functionality; use the supported-functionality APIs to check. The category
identifies remote-control functionality.

The warning object exposes only `type` and `category`. It does **not** enumerate
which settings or operations are missing.

### Does it affect shutter/settings/Live View/transfer?

The warning alone cannot answer that. It is a capability classification, not a
per-operation error. More detailed capability information is available through:

- `camera.supportedFunctionality` (advanced-feature bitmask)
- `camera.knownPropertyIdentifiers` (77 on the physical 60D)
- `camera.currentCommandCategories`
- `camera.liveViewStreamActive`
- `camera.storageDevices`
- each property's `valueSetType`, `currentValue`, `validSettableValues` and
  `validValueRange`

On the physical macOS test, despite the warning:

- settings **read** worked (77 identifiers)
- Live View delivered a 1056×704 frame
- one shutter request was accepted without an SDK error
- disconnect/reconnect worked

Settings **write** was not exercised. Image transfer was not tested because
there was no SD card. Therefore the warning must not be dismissed or suppressed,
and the untested operations cannot be declared compatible.

### Safe without an SD card

Safe:

- discovery
- connection
- settings read
- Live View start/frame/stop
- one shutter **request**
- disconnect/reconnect

Not safe/meaningful without storage:

- original JPEG transfer
- repeated capture
- file/storage validation

No automatic shutter retry is implemented or allowed.

---

## 3. Native adapter

Created:

```text
ipad_app/ios/Runner/CascableCameraAdapter.swift
```

Used only in the Runner target. CascableCore types remain in Swift.

### Actual SDK APIs used

- `CameraDiscovery.sharedInstance()`
- `CameraDiscovery.platformSupportsWiredCameras`
- `CameraDiscovery.hasAuthorizationToDiscoverWiredCameras`
- `CameraDiscovery.attemptToObtainWiredCameraAuthorization(completionHandler:)`
- `CameraDiscovery.discoveryMode = .usbOnly`
- `CameraDiscovery.setEnabled(_:forPluginWithIdentifier:)`
- `CameraDiscoveryDelegate` discovery/lost-sight callbacks
- `Camera.connect(authenticationRequestCallback:authenticationResolvedCallback:completionCallback:)`
- `Camera.disconnect(_:callbackQueue:)`
- `Camera.connectionState`, `cameraTransport`, `service`
- `CameraLiveView.beginStream(delivery:deliveryQueue:terminationHandler:)`
- `CameraLiveView.endStream()`
- `Camera.invokeOneShotShutterExplicitlyEngagingAutoFocus(_:completionCallback:)`
- `Camera.addCameraInitiatedTransferHandler(_:)`
- `CameraInitiatedTransferRequest.isValid`
- `CameraInitiatedTransferRequest.canProvide(_:)`
- `CameraInitiatedTransferRequest.executeTransfer(for:completionHandler:)`
- `CameraInitiatedTransferResult.generateData(for:completionHandler:)`

### Capture semantics

- A shutter request is emitted as `shutterSent`; it does **not** complete the
  Flutter method.
- The Flutter `capture` result is held until original bytes arrive.
- Only `CBLCameraInitiatedTransferRepresentationOriginal` is accepted.
- If the camera does not offer an original representation, the adapter fails
  with `TRANSFER_FAILED`; it does not substitute a preview.
- Timeout is 12 seconds (inside the pipeline's 15-second timeout).
- A late transfer after timeout/disconnect is ignored.
- No automatic shutter retry.
- The original bytes are base64-encoded unchanged; no resize/recompression.
- `CameraPipeline → ImageIngestor → StorageService` remains authoritative for
  JPEG validation, dimensions, capture-ID matching, de-duplication, atomic
  storage and Retake All.

### Live View

- `startLiveView` starts the SDK stream and emits base64 JPEG frames at a
  throttled rate.
- `stopLiveView` calls `endStream`.
- Disconnect/stop/dispose terminate the stream.
- The adapter does not render frames; rendering remains a future UI concern.

### State/error events

Events are serializable and include discovery, connecting/connected/
disconnected, Live View lifecycle, capture shutter/transfer/original/failed, and
error/capture codes.

### App integration

`CameraPlugin` now registers both the method and event channels against a
single `CascableCameraAdapter`. The old demo probe is no longer started, avoiding
a second competing camera state machine.

`CameraPlugin.licenseApplied` is set from the demo licence result. In production
it remains false; the adapter returns `CAMERA_LICENSE_MISSING` rather than
pretending to work. The production Bundle ID is unchanged.

---

## 4. Dart service integration

`NativeCameraService.connect()` now:

1. calls `initialize`
2. verifies `licensed == true`
3. calls native `connect`

Added optional native methods:

- `startDiscovery`
- `stopDiscovery`
- `startLiveView`
- `stopLiveView`
- `dispose`

`CascableCameraService` and the exact-name `CascableCoreCameraService` alias
delegate to `NativeCameraService`; they are selection wrappers, not a second
state machine. They are **not** the default.

`CameraAdapterEvent` parses serializable events for tests and future UI use.

No change was made to `CameraPipeline`, `ImageIngestor`, `StorageService`,
printing, QR, GIF or Windows Bridge.

---

## 5. Tests and builds

### Added tests

`test/camera_adapter_contract_test.dart` covers:

- native event shape parsing
- discovery state mapping
- connection state mapping
- Live View lifecycle/frame mapping
- shutter-sent versus original-received distinction
- transfer failure/disconnect codes
- NativeCameraService initialization, connect and capture-ID/bytes preservation
- missing-licence failure
- missing-image failure
- `CascableCameraService` delegation

Existing `CameraPipeline` tests continue to cover:

- capture timeout with no automatic retry
- late image after timeout cannot complete
- disconnect during capture
- disconnect during transfer
- duplicate capture/duplicate image
- Retake All/retake behavior and unique IDs

### Results

| Check | Result |
|---|---|
| `flutter analyze` | **No issues** |
| `flutter test` | **96 passed** |
| `pytest -q` | **39 passed** |
| iOS demo build `Debug-CascableDemo` | **BUILD SUCCEEDED** |
| iOS production build | **BUILD SUCCEEDED — 175 MB** |
| Production bundle ID | **`com.terabooth.teraboothIpad`** |
| Production licence file | **ABSENT** |
| Physical iPad USB | **NOT TESTED** |
| Original JPEG transfer | **NOT TESTED** |

The first full Flutter run had one unrelated transient GIF-test failure; the
isolated test and the subsequent full run passed. No GIF code was changed.

---

## 6. Known limitations

1. **No physical iPad** — wired authorization, USB discovery/connect, Live
   View and transfer on iPadOS are unverified.
2. **Original JPEG camera-initiated transfer** — adapter supports only
   camera-offered original transfer; EOS 60D behavior on iPadOS is unknown.
   There is no filesystem fallback.
3. **SD card missing** — no original transfer validation on macOS or iPadOS.
4. **Settings write** — not exercised; read path only.
5. **Warning** — `LowerThanExpectedFunctionality`/`RemoteControl` remains
   unsuppressed; no full EOS 60D compatibility claim.
6. **Authentication** — adapter cancels unknown authentication prompts rather
   than guessing a PIN. EOS 60D may not need authentication, but this is
   unverified on iPadOS.
7. **Native event runtime tests** — the Dart contract/pipeline tests cover
   mapping and invariants; no physical native SDK event run is possible without
   an iPad.
8. **No production selection** — `CascableCameraService` exists but
   `MockCameraService` remains default; production camera integration is not
   enabled.

---

## 7. Required physical iPad tests

- iPadOS USB adapter detection and permission prompt.
- `platformSupportsWiredCameras` / authorization result.
- EOS 60D discovery over USB and model/transport.
- Connection and warning details.
- Settings read and safe settings write.
- Live View frames and stop.
- One shutter request; no repeated shutter.
- Original JPEG transfer with an SD card.
- ImageIngestor validation and original-byte preservation.
- Capture timeout, late transfer, disconnect during capture.
- Disconnect/reconnect and 10-session stability.
- Background/foreground behavior.
- Retake All and unique capture IDs on device.

A successful macOS result and a simulated-camera result are not proof of iPadOS
USB compatibility.
