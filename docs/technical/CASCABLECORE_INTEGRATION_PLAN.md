# CascableCore Integration Plan — Terabooth EOS R / iPadOS

> **TARGET CORRECTION (2026-11-12):** The actual camera is a **Canon EOS 60D**, not an EOS R. The EOS 60D is absent from Cascable's official Canon compatibility list and its direct model page returns 404. All EOS R-specific assumptions here are historical and must not be used as EOS 60D compatibility evidence. See `PHASE_3A_1_CASCABLE_SETUP.md`.

> **Documentation-only plan. No app source is changed by this document.**
> **Precondition:** CascableCore evaluation licence approved and installed; iPad + EOS R available.
> **Architecture constraint:** iPad controls the camera over USB; Windows remains print/QR companion; mock camera remains for tests.

---

## 1. Decision

Proceed with **CascableCoreSwift + CascableCore** as the only planned EOS R USB path, preserving the existing Flutter `CameraService` boundary and `BoothController` flow.

Do **not**:

- add Canon EDSDK (no iOS support);
- switch to CCAPI/Wi-Fi;
- move camera control to Windows;
- add a second UI flow or redesign the booth UI;
- fake a camera or capture.

**Go/no-go:** integration may start only after the evaluation licence is approved and the iPad/EOS R are physically available. Until then, only documentation and compile-safe scaffolding exist.

---

## 2. Preconditions and gates

| Gate | Requirement | Current status |
|---|---|---|
| G1 | CascableCore evaluation licence approved | **BLOCKED** — requested, not approved |
| G2 | Xcode + iOS 26.5 runtime + iPadOS device | Build works; iPad available 11 Nov |
| G3 | EOS R + data USB-C cable | Available; not yet tested on iPad |
| G4 | iOS deployment target raised to 14.0 | **Not yet** — current 13.0 |
| G5 | Source changes approved after licence | **Not started** |
| G6 | Physical 10/10 capture test | **Not tested** |

---

## 3. Minimal target changes (after approval)

1. **Raise deployment target** from iOS 13.0 to **iOS 14.0** in the Runner target/project (CascableCore minimum).
2. **Add SPM dependency**:
   - Xcode → File → Add Package Dependencies.
   - `https://github.com/cascable/cascablecore-swift`
   - Product: `CascableCoreSwift` on the Runner target.
   - It brings `CascableCore` transitively; if Xcode does not expose the module, add `https://github.com/cascable/cascablecore-distribution` and the `CascableCore` product explicitly.
3. **Add the licence** via a non-committed source file or approved build injection. Apply it before any CascableCore API; fail closed on non-success.
4. **Add `CascableCameraAdapter.swift` to the Runner target** (currently only a reference file outside the target).
5. **Wire the real adapter into `CameraPlugin`**, replacing the stub handlers only after the adapter compiles.
6. **Keep `MockCameraService` as default** for UI tests; native path is opt-in via `USE_NATIVE_CAMERA=true`.
7. **No Info.plist additions required** beyond what exists; confirm the installed SDK's release notes before changing permissions. Do not add the multicast entitlement for USB-only.

---

## 4. Architecture mapping

| Terabooth component | Responsibility after integration |
|---|---|
| **Flutter UI** | Camera status, countdown/capture controls, review; optional live preview. No redesign. |
| **NativeCameraService** | Dart-to-Swift method/event client; no SDK types leak into Dart. |
| **CameraPlugin** | MethodChannel/EventChannel handling; main-thread dispatch; maps errors. |
| **CascableCameraAdapter** | Owns `CameraDiscovery`, connected `Camera`, live view, capture, transfers, reconnect. |
| **Camera session** | Connection lifecycle, command categories, capture serialization, transfer correlation. |
| **Image pipeline** | Native writes original JPEG to a temp path; Flutter reads/saves via existing `StorageService`; preview uses a smaller path/bytes. |
| **BoothController** | Existing 3-photo countdown/review/approve flow; adds connection status/reconnect; no new workflow. |

### Why a native session object

CascableCore is stateful and main-thread-only. The adapter should own:

- one discovery object;
- one connected camera reference;
- a single capture-in-flight state;
- a camera-initiated transfer handler token;
- timers/timeouts and reconnect backoff.

This prevents duplicate captures and lost transfer callbacks. It does not change the Flutter architecture.

---

## 5. Camera lifecycle

### 5.1 Startup

1. Apply licence; require `.success`.
2. Create `CameraDiscovery.shared`.
3. Set `clientName = "Terabooth"`.
4. Set `discoveryMode = .usbOnly`.
5. Check `platformSupportsWiredCameras`.
6. Call `attemptToObtainWiredCameraAuthorization()` and require `true`.
7. Set delegate and `beginSearching()`.

### 5.2 Connect

1. On `didDiscover`, select the first EOS R (or the only camera); stop discovery after selection.
2. Call `connect(authenticationRequestCallback:authenticationResolvedCallback:completionCallback:)`.
3. Surface authentication UI only if the camera asks (EOS R typically won't for USB, but do not assume).
4. On success: verify `cameraTransport == .USB`, store camera, set `.connected`.
5. On failure: report error; allow retry; do not fake connection.

### 5.3 Session

- Existing flow: 3 photos at 3-second countdown; each capture must be acknowledged by an actual transferred original before advancing.
- Register `addCameraInitiatedTransferHandler` once per camera connection.
- Start live view only if the UI needs it; for MVP the existing countdown UI can operate without a preview, reducing risk.
- After 3 originals are saved, optionally stop live view and proceed to review.

### 5.4 Shutdown

- Remove transfer handler.
- `endStream()` if live view active.
- `disconnect(_:callbackQueue:)`.
- `stopSearching()`.
- Clear references; do not reuse a disconnected camera object without rediscovery.

---

## 6. Capture and original-image strategy

### 6.1 Preferred path (reliability first)

1. Ensure camera is in `.stillsShooting`, live view active if required by EOS R.
2. Guard: only one capture in flight; reject duplicate requests with `CAPTURE_IN_PROGRESS`.
3. Call `invokeOneShotShutterExplicitlyEngagingAutoFocus(true, completionCallback:)`.
4. Treat the callback as **request accepted**, not success.
5. Await a camera-initiated transfer request or a filesystem change/new file within a timeout.
6. For the original:
   - If the transfer request `canProvide(.original)` and `isOnlyDestinationForImage` is true → transfer original immediately.
   - If original is available → request `.original`, write to temp, verify file size > 0.
   - If only preview is available → **do not use it as the 2×6 original**; fall back to filesystem.
7. If no valid transfer/file within timeout → fail the capture with a clear error; do not save a placeholder; allow retake.

### 6.2 Filesystem fallback

1. Record the newest known file/time before capture.
2. After shutter, switch to `.filesystemAccess` if necessary.
3. Load storage/root children (do not assume DCIM path).
4. Find the new file by date/name; stream it to a temp file with `streamItem`.
5. Verify JPEG/type and non-zero size; switch back to `.stillsShooting` for the next capture.
6. This may stop live view; allow the camera to restart it; measure the timing on EOS R.

### 6.3 Image format

- Set EOS R to **JPEG Large/Fine** for the event; do not rely on RAW. Flutter/Pillow cannot process CR3, and the 2×6 output needs a decodable JPEG.
- The current `compose_strip` expects JPEG. If the camera produces HEIF/RAW, reject with a clear configuration error, not a fake success.
- 2×6 needs ~600×1800 per panel at 300 dpi; the original must be large enough after cover-crop. Verify actual EOS R JPEG dimensions on 11 Nov.

### 6.4 Transport to Flutter

Avoid base64 for full originals (memory/CPU). Proposed contract:

- Native writes original to `Application Support/terabooth/incoming/<captureId>.jpg` (or a temp directory).
- Method/event returns `{id, path, width, height, capturedAt, byteLength}`.
- Dart reads the file once for preview and passes the path/bytes to `StorageService`, which writes atomically to the existing event/session path.
- Do not duplicate large byte arrays across MethodChannel and Dart storage.

The existing `NativeCameraService.capture()` base64 contract can be kept as a temporary fallback, but it is not recommended for 3 full JPEGs.

---

## 7. Live view plan (optional)

The current UI does not require live preview for the 3-photo countdown. For the event:

- **MVP:** skip live view; use camera status/countdown only. This reduces start/stop latency and failure modes.
- **If preview is needed:** use `liveViewPublisher` with `sinkWithReadyHandler`, limit FPS, and send JPEG frames over an EventChannel at a controlled rate (e.g. 10 fps). Do not forward every camera frame.
- Starting/stopping live view is multi-second; do not start/stop per photo.
- If EOS R requires live view for remote shutter, keep it running for the session and stop only after the third capture.

**Decision:** defer live preview until the core capture/transfer path passes 10/10. Do not redesign the UI for it.

---

## 8. Error and recovery design

| Event | Design |
|---|---|
| **USB unplug during capture** | KVO `connectionState`; mark pending capture `failed`; no image saved; keep already-saved photos; prompt reconnect. |
| **Camera power-off** | Treated as unexpected disconnect (check `disconnectionWasExpected`); same as above; do not auto-capture. |
| **Failed image transfer** | Delete partial temp file; report `TRANSFER_FAILED`; allow retake; never save a truncated JPEG. |
| **Duplicate capture taps** | Native `captureInFlight` guard + Flutter controller guard; return `CAPTURE_IN_PROGRESS`; correlate by `captureId`. |
| **Background/foreground** | On background: stop live view, abort pending transfer, mark session paused; on foreground: check `connectionState`, rediscover if needed; no background capture. |
| **Reconnect** | Stop discovery; clear camera; restart discovery with backoff (1s, 2s, 4s, max 3 attempts); user-triggered retry. |
| **Capture timeout** | 15s from shutter request to verified original; then fail; one retry maximum. |
| **Connect timeout** | 20s; clear error; no fake connected state. |
| **Live-view termination** | `.endedNormally` → update status; `.failed` / `.alreadyStreaming` → error/recover; do not capture blindly. |
| **Licence invalid/expired** | Fail closed at startup; no discovery; show setup error. |

**No auto-resubmit of a capture after an ambiguous result.** The operator decides retake.

---

## 9. Implementation sequence (after licence approval)

| Step | Work | Acceptance |
|---|---|---|
| 1 | Raise target to iOS 14; add SPM package; add licence (untracked); build | App builds with SDK; licence `.success` |
| 2 | Add adapter to target; discovery USB-only + authorization | Camera discovered/connected; no fake state |
| 3 | Implement connection state/error mapping | Unplug/power-off produces correct error |
| 4 | Implement capture + camera-initiated original transfer | One real JPEG saved; camera shutter fires |
| 5 | Implement filesystem fallback | New file found/streamed; valid JPEG |
| 6 | Flutter Method/EventChannel integration; keep mock default | Flutter receives path/status; UI unchanged |
| 7 | Duplicate/timeout/background/reconnect hardening | Fault tests pass |
| 8 | 10/10 physical sessions; 3 images each | G0 green |
| 9 | Optional live preview | Deferred; not required for event |

**Estimated effort:** 1–2 focused development days after licence + hardware, plus physical debugging. This is an estimate, not a commitment; EOS R transfer behaviour is unknown.

---

## 10. Files expected to change later

Documentation only now; no changes made:

- `ipad_app/ios/Runner.xcodeproj/project.pbxproj` — deployment target and package references.
- `ipad_app/ios/Runner/CascableCameraAdapter.swift` — real implementation, added to target.
- `ipad_app/ios/Runner/AppDelegate.swift` — plugin registration and licence application.
- `ipad_app/lib/services/native_camera_service.dart` — method/event calls.
- `ipad_app/lib/booth_controller.dart` — connection status/retry, capture correlation.
- `ipad_app/lib/main.dart` — native selection (already flag-based).
- Non-committed licence file — **never committed**.

No UI redesign; no Windows camera control; no dependency changes until approval.

---

## 11. Risks and stop conditions

| Risk | Mitigation |
|---|---|
| Licence not approved in time | Fallback to iPad built-in camera or proven LumaBooth rig; do not ship Cascable stub as working |
| EOS R original unavailable via camera-initiated transfer | Filesystem fallback; test on 11 Nov |
| Command-category switch loses live view | Test timing; capture 3 then transfer; restart live view for next session |
| Capture callback succeeds but shutter did not fire | Require transfer/file evidence; timeout; no fake |
| USB disconnect/power-off | KVO + explicit errors; no auto-retry capture |
| iOS 14 target change affects app | Build/test; current iPadOS is newer |
| Licence expiry during event | Install commercial/evaluation licence with validity through 14 Nov; verify offline |
| No internet at venue | License file or pre-activated offline token; test with WAN off |

**Stop and fall back** if 10/10 camera sessions cannot pass by 11 November or the licence/terms are unsuitable for the event.

---

## 12. References

- [CascableCore SDK Research](./CASCABLECORE_SDK_RESEARCH.md)
- [API mapping](./CASCABLECORE_API_MAPPING.md)
- [Test plan](./CASCABLECORE_TEST_PLAN.md)
- [Developer portal](https://developer.cascable.se/)
- [CascableCore distribution](https://github.com/cascable/cascablecore-distribution)
- [CascableCoreSwift](https://github.com/cascable/cascablecore-swift)
- [EOS R compatibility](https://compatibility.cascable.se/canon/eos-r/)
- [Wired camera guide](https://cascable.se/help/wired-cameras/)
