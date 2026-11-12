# Phase 6A — CascableCore Integration into Terabooth

## Overall result

**PASS for source integration and automated verification.**  
**Physical iPad/camera operations remain NOT TESTED** in this session.

No app was installed or launched. No camera discovery, connection, shutter,
capture, transfer or settings operation was performed.

---

## 1. Architecture preserved

```text
BoothController
  → CameraPipeline
  → CameraService
      → NativeCameraService / CascableCoreCameraService (physical path)
      → MockCameraService (default)
  → ImageIngestor
  → StorageService
```

- Native SDK types remain inside `CascableCameraAdapter.swift`.
- Flutter sees only serializable MethodChannel/EventChannel payloads.
- `ImageIngestor` remains authoritative for JPEG validation and original-byte
  atomic storage.
- `MockCameraService` remains the production default.
- `USE_NATIVE_CAMERA` defaults false; no global production camera enablement.
- Windows Bridge, printer and guest delivery were not modified.

---

## 2. SDK APIs used

- `CameraDiscovery.sharedInstance()`
- `CameraDiscoveryDelegate`
- `CameraDiscovery.discoveryMode = .usbOnly`
- `CameraDiscovery.attemptToObtainWiredCameraAuthorization`
- `Camera.connect(authenticationRequestCallback:authenticationResolvedCallback:completionCallback:)`
- `Camera.disconnect(_:callbackQueue:)`
- `Camera.addCameraInitiatedTransferHandler` / `remove...`
- `CameraInitiatedTransferRequest.canProvide(.original)` and
  `executeTransfer(for: .original)`
- `generateData(for: .original)`
- `CameraLiveView.beginStream` / `endStream`
- `Camera.knownPropertyIdentifiers`, `property(with:)`,
  `storageDevices`
- `CascableCoreLicenseVerification.apply`

No undocumented APIs were introduced.

---

## 3. Changes made

### Native licence handoff

`ios/Runner/AppDelegate.swift` now sets:

```swift
CameraPlugin.licenseApplied = licenseApplied
```

inside the demo-only `CASCABLE_DEMO` block. Previously the adapter checked this
flag but it was never set, so native initialization would fail even with a valid
licence.

### Native disposal

`ios/Runner/CascableCameraAdapter.swift` now disconnects an active camera during
`dispose`, stops Live View, removes the transfer handler, fails pending captures,
stops discovery and clears delegate state.

### Live View abstraction

`lib/services/camera_service.dart` adds optional capabilities:

- `CameraLiveViewSource` — frame stream, start/stop
- `CameraEventSource` — native connection events

`NativeCameraService`/`CascableCameraService` implement both. The native event
stream is shared/broadcast so event consumption is not duplicated.

### Controller lifecycle

`BoothController` now:

- subscribes to native Live View frames after a successful connect;
- exposes `liveViewFrame` and `liveViewError`;
- starts/stops Live View with the session lifecycle;
- stops Live View on end/reset/dispose;
- cancels subscriptions and calls `camera.dispose()` on app dispose.

Live View failure does not fail capture; capture remains authoritative.

### Connection interruption

`CameraPipeline` subscribes to native connection events and calls
`notifyDisconnected` on `disconnected`, `failed` or `disconnectFailed`, so
pending captures fail rather than remaining stuck.

### Capture

The existing native path remains:

- one shutter request at a time;
- `.original` only;
- JPEG SOI/EOI validation;
- no preview fallback;
- no RAW conversion;
- no automatic retry;
- capture completes only after original bytes are validated/stored.

Live View and capture use one native adapter instance; no second camera state
machine.

### UI

`CaptureScreen` now displays a real native Live View frame when present; the mock
viewfinder remains for `MockCameraService`. The pill says "Live view" for native
and "Mock viewfinder" for mock.

---

## 4. Files modified

- `ios/Runner/AppDelegate.swift`
- `ios/Runner/CascableCameraAdapter.swift`
- `lib/services/camera_service.dart`
- `lib/services/native_camera_service.dart`
- `lib/services/camera_pipeline.dart`
- `lib/booth_controller.dart`
- `lib/screens/capture_screen.dart`
- `test/native_live_view_integration_test.dart`
- `test/support.dart`

No production bundle ID, CascableCore SPM version, licence file, Windows Bridge,
printer or camera architecture was changed.

---

## 5. Licence and Bundle ID configuration

| Configuration | Bundle ID | Licence |
|---|---|---|
| Demo / `Debug-CascableDemo` | `se.cascable.CascableCoreiOSDemo` | Copied by demo-only phase |
| Production | `com.terabooth.teraboothIpad` | Absent |

CascableCore 18.0.2 remains pinned. Demo licence contents were not read, printed
or modified.

Physical demo signing is still blocked: `se.cascable.CascableCoreiOSDemo` cannot
be registered to the available Personal Team, and no provisioning profile was
found.

---

## 6. Tests and builds

### Flutter

```text
flutter analyze: No issues
flutter test --concurrency=1: 141 passed
```

New tests cover:

- licensed native initialization and method sequence;
- discovery/connect/start/stop Live View/disconnect/dispose;
- controller Live View frame exposure and stop on session end;
- controller disposal of native resources;
- native connection-loss event → pipeline failed state;
- existing native adapter contract/mapping tests.

### Bridge regression

```text
61 passed
```

### Simulator builds

```text
Demo Runner-CascableDemo:
BUILD SUCCEEDED
bundle: se.cascable.CascableCoreiOSDemo
demo licence present

Production:
BUILD SUCCEEDED
bundle: com.terabooth.teraboothIpad
licence absent
```

No app was installed or launched.

---

## 7. Known limitations

- No physical iPad install/launch or camera connection/Live View/capture.
- Demo signing/provisioning remains blocked by the bundle-ID restriction.
- Native connection-loss events only cover events emitted by the adapter; there
  is no network/Wi-Fi path (USB only).
- Live View failure is reported but does not block capture; this is deliberate.
- Authentication prompts are cancelled rather than guessed; EOS 60D USB is
  expected not to require a code, but physical behavior is unverified.
- `CameraPipeline` uses the adapter's connection events; no automatic reconnect
  or retry is added.
- Production integration remains disabled by default.
- Windows Bridge/printer unchanged.

---

## 8. Exact next steps for physical validation

1. Resolve demo provisioning without changing the licence-bound bundle ID
   (Cascable/team ownership or a valid wildcard App ID arrangement).
2. Install the signed demo build on the physical iPad.
3. Launch and confirm `CASCABLE_DEMO_LICENSE_RESULT` is success (without printing
   licence data).
4. Connect the EOS 60D USB; verify discovery/connection/properties/storage.
5. Start/stop Live View from the operator UI; verify real frames and clean
   termination.
6. Only after those pass, obtain explicit approval for one shutter/capture test.
7. Verify original JPEG ingestion, hash preservation and no RAW/preview fallback.
8. Do not implement automatic retries or production camera enablement.

**Stopped after source and automated verification. No physical camera action.**
