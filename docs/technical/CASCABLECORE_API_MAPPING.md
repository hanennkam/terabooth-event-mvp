# CascableCore API Mapping — Terabooth Camera Contract

> **TARGET CORRECTION (2026-11-12):** The actual camera is a **Canon EOS 60D**, not an EOS R. The EOS 60D is absent from Cascable's official Canon compatibility list and its direct model page returns 404. All EOS R-specific assumptions here are historical and must not be used as EOS 60D compatibility evidence. See `PHASE_3A_1_CASCABLE_SETUP.md`.

> **Documentation-only.** No MethodChannel, Swift or Dart source is changed by this document.
> Names marked **SDK-confirmed** come from official CascableCore docs/demo. Names marked **Terabooth contract** are our own channel names, not SDK APIs.

---

## 1. Existing contract (inspected)

### Flutter

```dart
abstract class CameraService {
  String get name;
  bool get isSimulated;
  Future<void> connect();
  Future<CapturedImage> capture();
}
```

`NativeCameraService` uses:

- Channel: `com.terabooth/camera`
- Methods: `connect`, `capture`, `status`, `disconnect`
- `capture` expects `{bytes: base64, width, height, id}`.

`BoothController` calls `camera.connect()` once per session, then `camera.capture()` three times; it has no disconnect, live view or connection-state handling.

### Swift

`CameraPlugin` registers `com.terabooth/camera` and currently returns `CAMERA_SDK_MISSING`. `CascableCameraAdapter.swift` is a reference file outside the Xcode target.

### Compatibility decision

Preserve the existing `CameraService` methods for the event flow. Add status/error events and optional live view **additively**; do not replace the 3-photo UI.

---

## 2. Proposed channel architecture

| Channel | Type | Purpose |
|---|---|---|
| `com.terabooth/camera` | MethodChannel | Commands and request/response |
| `com.terabooth/camera/events` | EventChannel | Asynchronous discovery, connection, capture, live view, errors |

Both are Terabooth contracts. They carry no CascableCore types across the boundary.

All native calls that touch CascableCore must run on the **main thread**; CascableCore is documented as not thread-safe.

---

## 3. Method contract

### 3.1 `initialize`

```json
{}
```

Response:

```json
{
  "ok": true,
  "backend": "cascablecore",
  "licensed": true,
  "platformSupportsWiredCameras": true,
  "wiredAuthorization": true
}
```

Behavior:

- Apply the licence before any SDK call.
- Check `platformSupportsWiredCameras`.
- Request wired authorization via `attemptToObtainWiredCameraAuthorization()`.
- Return `ok:false` + an error if licence/auth fails.

SDK basis: `CascableCoreLicenseVerification.apply(license:)`, `CameraDiscovery.platformSupportsWiredCameras`, `attemptToObtainWiredCameraAuthorization()`.

### 3.2 `startDiscovery`

```json
{"mode": "usbOnly"}
```

Response: `{"ok": true}`; discovered cameras are delivered as events.

SDK basis: `CameraDiscovery.shared`, `discoveryMode = .usbOnly`, `clientName`, `delegate`, `beginSearching()`.

### 3.3 `stopDiscovery`

Response `{"ok": true}`.

SDK basis: `stopSearching()`.

### 3.4 `connect`

Request:

```json
{"cameraId": "usb:canon-eos-r"}
```

Response (after connection completes):

```json
{
  "ok": true,
  "cameraId": "usb:canon-eos-r",
  "model": "Canon EOS R",
  "transport": "usb",
  "friendlyIdentifier": "..."
}
```

`cameraId` is a Terabooth identifier derived from the discovered camera (not an SDK API). The adapter keeps the actual `Camera` reference natively.

SDK basis: `CameraDiscoveryDelegate.discovery(_:didDiscover:)`, `camera.connect(authenticationRequestCallback:authenticationResolvedCallback:completionCallback:)`, `cameraTransport == .USB`, `friendlyIdentifier`, `deviceInfo`.

### 3.5 `disconnect`

Response `{"ok": true}`.

SDK basis: `disconnect(_:callbackQueue:)`, `stopSearching()`.

### 3.6 `capture`

Request:

```json
{"requestId": "cap_123"}
```

Response:

```json
{"ok": true, "captureId": "cap_123", "state": "requested"}
```

The final result is an event (`capture.completed` or `capture.failed`), because the camera may take seconds to produce/transfer the image and the SDK callback does not confirm the shutter.

SDK basis: `invokeOneShotShutterExplicitlyEngagingAutoFocus(_:completionCallback:)`.

**Important:** the SDK completion callback means “request sent”, not “photo captured”. Do not return success from `capture` based on that callback alone.

### 3.7 `status`

Response:

```json
{
  "licensed": true,
  "connected": true,
  "state": "connected",
  "transport": "usb",
  "cameraId": "usb:canon-eos-r",
  "model": "Canon EOS R",
  "liveViewActive": false,
  "captureInFlight": false
}
```

SDK basis: `connectionState`, `connected`, `cameraTransport`, `liveViewStreamActive`, `friendlyDisplayName`.

### 3.8 Optional live view methods

```text
startLiveView  -> {"ok": true}
stopLiveView   -> {"ok": true}
```

SDK basis: `beginStream(delivery:deliveryQueue:terminationHandler:)`, `endStream()`, or `liveViewPublisher(options:)`.

Deferred for MVP; see §6.

### 3.9 `dispose`

Releases the adapter, observers, transfer handler, live view and discovery. Response `{"ok": true}`.

---

## 4. Event contract

All events are maps with a `type` field.

### 4.1 `discovery`

```json
{
  "type": "discovery",
  "state": "searching",
  "cameras": [
    {"cameraId": "usb:canon-eos-r", "model": "Canon EOS R", "manufacturer": "Canon", "transport": "usb"}
  ]
}
```

States: `idle`, `searching`, `found`, `stopped`, `failed`.

SDK basis: discovery delegate/`availableCameras`; fields such as `service.manufacturer`, `service.model`, `cameraTransport`.

### 4.2 `connection`

```json
{
  "type": "connection",
  "state": "connected",
  "cameraId": "usb:canon-eos-r",
  "model": "Canon EOS R",
  "transport": "usb",
  "expectedDisconnect": false
}
```

States: `disconnected`, `connecting`, `connected`, `disconnecting`, `error`.

SDK basis: `connectionState` (`.notConnected`, `.connectionInProgress`, `.connected`, `.disconnectionInProgress`), `disconnectionWasExpected`.

### 4.3 `capture`

```json
{
  "type": "capture",
  "phase": "completed",
  "captureId": "cap_123",
  "path": "/.../incoming/cap_123.jpg",
  "width": 0,
  "height": 0,
  "byteLength": 8123456,
  "capturedAt": "2026-11-11T14:02:03Z",
  "source": "cameraInitiatedTransfer"
}
```

Phases: `requested`, `shutterSent`, `transferring`, `completed`, `failed`, `timeout`.

`source`: `cameraInitiatedTransfer` or `filesystem`. `width`/`height` are populated from the actual image; the zero values above are placeholders.

SDK basis: shutter + camera-initiated transfer (`isValid`, `canProvide(.original)`, `executeTransfer`, `write(.original,to:)`) or filesystem (`storageDevices`, `loadChildren`, `streamItem`).

### 4.4 `liveViewFrame`

```json
{
  "type": "liveViewFrame",
  "format": "jpeg",
  "width": 1024,
  "height": 680,
  "bytes": "<FlutterStandardTypedData>"
}
```

Deferred; not needed for the current countdown UI.

SDK basis: live view frame delivery / `liveViewPublisher`.

### 4.5 `error`

```json
{
  "type": "error",
  "code": "CAMERA_DISCONNECTED",
  "message": "The camera disconnected during capture.",
  "recoverable": true,
  "captureId": "cap_123"
}
```

Terabooth error codes are our contract, not CascableCore codes.

---

## 5. SDK-to-Terabooth mapping

| Terabooth operation | CascableCore API (confirmed) | Notes |
|---|---|---|
| Apply licence | `CascableCoreLicenseVerification.apply(license:)` | Before any SDK call; `.success` required |
| Start USB discovery | `CameraDiscovery.shared`, `.discoveryMode = .usbOnly`, `beginSearching()` | Set `clientName` first |
| Authorization | `platformSupportsWiredCameras`, `hasAuthorizationToDiscoverWiredCameras`, `attemptToObtainWiredCameraAuthorization()` | Runtime permission |
| Discovered camera | `CameraDiscoveryDelegate.discovery(_:didDiscover:)` | Stop discovery after selection |
| Connect | `camera.connect(authenticationRequestCallback:authenticationResolvedCallback:completionCallback:)` | Handle authentication pairs |
| Connection status | `connectionState`, `disconnectionWasExpected`, `cameraTransport` | KVO/observation; main thread |
| Disconnect | `disconnect(_:callbackQueue:)` | Clean session end |
| Command mode | `setCurrentCommandCategories(_:completionCallback:)` | `.stillsShooting` / `.filesystemAccess` |
| Live view | `beginStream(delivery:deliveryQueue:terminationHandler:)` or `liveViewPublisher` | Heavy; optional |
| Shutter | `invokeOneShotShutterExplicitlyEngagingAutoFocus(_:completionCallback:)` | Callback ≠ shutter fired |
| Camera-initiated transfer | `addCameraInitiatedTransferHandler`, `executeTransfer(for:completionQueue:)`, `writeRepresentation` | Handle immediately; `isValid` can expire |
| Filesystem | `storageDevices`, `rootDirectory`, `loadChildren`, `streamItem(...)` | Requires `.filesystemAccess`; do not assume paths |
| Camera model | `friendlyDisplayName`, `deviceInfo`, `service.model` | May be nil until connected |
| Supported features | `supportedFunctionality`, `supportsFunctionality(_:)` | Only valid after connect |

---

## 6. Live view decision

**MVP recommendation: no live preview.**

Reasons:

- The existing UI uses a countdown, not a preview.
- Live view start/stop is documented as multi-second and resource-heavy.
- Forwarding decoded frames over an EventChannel adds latency/memory risk.
- The event's reliability goal is capture + transfer + print, not preview.

If preview becomes necessary:

- Use `liveViewPublisher(options:)` with a controlled FPS.
- Encode frames as JPEG/typed data; drop frames if Flutter is busy.
- Keep live view running for the session; do not toggle per photo.
- Never let preview start/stop block capture.

---

## 7. Image handoff

### Preferred

```text
SDK transfer → native temp file → event path → Dart File read → StorageService atomic write
```

- Native writes the original to a temp directory.
- Event includes `path`, `width`, `height`, `byteLength`.
- Dart reads the file and calls the existing `StorageService.saveOriginal`.
- Delete the native temp file after the Dart save succeeds.
- Do not send a full 6–10 MB JPEG as base64 unless unavoidable.

### Temporary compatibility

The current `NativeCameraService.capture()` expects base64. A minimal integration can return base64 for the 3 images, but this increases memory copies. Keep it only as a fallback and document the limitation.

### Existing `CapturedImage`

`CapturedImage` has `bytes`, `width`, `height`, `path`. Reuse it; `path` remains the saved local path. A native temp path can be an additional private field or the bytes can be read before constructing the object.

---

## 8. State machine

```text
idle
  └─ initialize (licence/auth) ──► ready
ready
  └─ startDiscovery ──► discovering
discovering
  ├─ camera found ──► connecting
  └─ stop/fail ──► ready/error
connecting
  ├─ success ──► connected
  └─ fail/timeout ──► error
connected
  ├─ capture(request) ──► capturing
  ├─ disconnect ──► disconnecting
  └─ unexpected disconnect ──► error
capturing
  ├─ transfer complete + valid JPEG ──► connected (capture.completed)
  ├─ transfer failed ──► connected (capture.failed)
  ├─ timeout ──► connected (capture.timeout)
  └─ disconnect ──► error (capture.failed)
disconnecting
  └─ done ──► ready
```

Rules:

- One capture in flight; duplicate `capture` returns `CAPTURE_IN_PROGRESS`.
- No automatic capture retry after an ambiguous timeout.
- `captureId` is generated by Dart (or native) and echoed in all events.
- Captures already saved stay saved on later errors.

---

## 9. Error mapping

| Terabooth code | Cause | User action |
|---|---|---|
| `CAMERA_LICENSE_MISSING` | licence not applied / not `.success` | Install valid licence |
| `CAMERA_SDK_MISSING` | CascableCore not linked | Build/setup error |
| `CAMERA_PERMISSION_DENIED` | wired authorization denied | Open Settings, allow Files/Camera |
| `CAMERA_NOT_FOUND` | no USB camera discovered | Check cable/Wi-Fi off/PTP |
| `CAMERA_CONNECT_FAILED` | connect error | Retry; check camera |
| `CAMERA_CONNECT_TIMEOUT` | 20s no completion | Retry |
| `CAMERA_DISCONNECTED` | unexpected disconnect | Reconnect; retake |
| `CAMERA_NOT_CONNECTED` | capture before connect | Connect |
| `CAPTURE_IN_PROGRESS` | duplicate request | Ignore/queue |
| `CAPTURE_TRIGGER_FAILED` | shutter request error | Retry once |
| `CAPTURE_TIMEOUT` | no transfer/file within 15s | Retake |
| `TRANSFER_FAILED` | transfer/write error | Retake |
| `TRANSFER_TIMEOUT` | file transfer stalled | Retake |
| `INVALID_IMAGE_FORMAT` | RAW/HEIF or undecodable | Set JPEG |
| `LIVE_VIEW_FAILED` | stream failure | Continue without preview |
| `UNSUPPORTED` | SDK feature unavailable | Fallback/config |

---

## 10. Compatibility with existing Flutter flow

- `connect()` remains the session start; native `connect` is idempotent if already connected.
- `capture()` remains the per-photo call; native waits for the real transfer and returns the image, or throws.
- **Event scope (Phase 1F-R):** individual per-photo retake is out of the event MVP. `retakeOne()` remains a non-event/test API only; do not expose it in the event workflow. Event recapture uses Retake All (complete 3-photo session).
- `approve()` is unchanged; it uploads to the Windows bridge.
- `CameraService` can gain a default no-op `disconnect()` and optional status stream later; the 3-photo flow does not need a UI redesign.
- `MockCameraService` remains default and test-covered.

---

## 11. Unverified parts of this contract

- Exact EOS R original availability via camera-initiated transfer.
- Whether filesystem fallback can run without a disruptive live-view stop on EOS R.
- Actual file sizes/timings.
- Whether the proposed `cameraId` can be stable across reconnects (use serial/friendlyIdentifier if available).
- Whether `FlutterStandardTypedData` is needed for live view; deferred.
- Exact Swift overloads for file streaming/write (confirm against installed headers).

**Do not implement this contract as “working” until the physical 10/10 test passes.**
