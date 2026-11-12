# Camera Pipeline Reliability — Phase 1C

> **SDK-independent implementation.** CascableCore is not installed and no native camera is claimed.
> **Mock camera remains the default and is explicitly labelled SIMULATED.**
> **No physical iPad/EOS R test has been performed.**

---

## 1. Actual architecture

| File | Responsibility |
|---|---|
| `lib/services/camera_service.dart` | `CameraService` interface; mock, unavailable and Cascable placeholder services |
| `lib/services/camera_contract.dart` | SDK-independent MethodChannel/EventChannel names, payload keys and error codes |
| `lib/services/camera_pipeline.dart` | Connection/capture state machine, capture coordinator, image validation/ingestion |
| `lib/services/native_camera_service.dart` | Dart-to-native MethodChannel client; JPEG bytes or native path; no Cascable types |
| `lib/services/storage_service.dart` | Unique filenames, atomic writes, metadata, temp recovery |
| `lib/booth_controller.dart` | Existing 3-photo workflow, review/retake, print bridge/QR flow |
| `lib/main.dart` | Camera selection + app lifecycle forwarding |
| `ios/Runner/AppDelegate.swift` | Compile-safe stub; still returns `CAMERA_SDK_MISSING` |
| `ios/Runner/Cascable/CascableCameraAdapter.swift` | Reference only; not in the Xcode target |

The existing `CameraService` boundary is preserved. No CascableCore dependency, package or native adapter implementation was added.

### Camera selection

- Default: `MockCameraService` (SIMULATED).
- `--dart-define=USE_NATIVE_CAMERA=true`: `NativeCameraService`.
- Native stub still fails clearly; it never fabricates a camera or image.

### Existing workflow preserved

Welcome → Start → 3-photo countdown → capture → review → individual/all retake → Approve & Print → QR.

`BoothController` still owns the booth flow; the new `CameraPipeline` owns camera/capture reliability. Print bridge and QR code paths are unchanged.

---

## 2. State machine

Connection and capture state are separate fields in `CameraPipelineState`.

### Connection states

```text
disconnected -> discovering -> connecting -> connected
                                      |-> failed
connected -> recovering -> connecting/connected
connected -> disconnected
any active state -> failed
failed -> disconnected/discovering/connecting
```

| State | Meaning |
|---|---|
| `disconnected` | No camera session |
| `discovering` | Looking for/validating a camera |
| `connecting` | Connection in progress |
| `connected` | Camera commands allowed |
| `recovering` | Session interrupted (e.g. background/reconnect) |
| `failed` | Connection error; no capture allowed |

### Capture states

```text
idle -> capturing -> transferring -> ready
                         |-> failed
capturing -> failed
ready -> capturing / idle
failed -> idle / capturing (new request only)
```

| State | Meaning |
|---|---|
| `idle` | No capture has been requested |
| `capturing` | Shutter request in flight |
| `transferring` | Image received; validating/saving |
| `ready` | A valid original is saved |
| `failed` | Capture/transfer failed; no success |

`CameraStateMachine` rejects invalid transitions; tests cover valid and invalid cases.

**Separate-state rule:** a capture failure never changes a connected camera to “connected capture failed” by conflating the two. A disconnect fails the active capture and changes the connection state; a capture error leaves the connection connected.

---

## 3. Capture lifecycle

1. `BoothController` starts a session and calls `cameraPipeline.connect()`.
2. For each of the 3 photos, it calls `capture(eventId, sessionId, slot)`.
3. The coordinator:
   - rejects the request if the camera is not connected;
   - rejects a duplicate slot already active/queued;
   - generates a unique `cap_<utc-microseconds>_<counter>` ID;
   - enqueues the request; only one capture executes at a time;
   - sets `capturing`, then calls `camera.capture(captureId: id)`;
   - applies the configurable timeout (default 15 s);
   - on delivery, sets `transferring` and runs image validation/save;
   - reports `ready` only after the saved file has been reopened and validated;
   - completes the Dart future with the saved `CapturedImage`.
4. `BoothController` adds the image only after that future succeeds.
5. The next queued request starts only after the previous one finishes.
6. No automatic shutter retry is performed. A timeout/failure is final; the operator must retake.

### Duplicate taps

A second request for the same slot is immediately rejected with `DUPLICATE_CAPTURE` while the first is active or queued. Different slots can be queued and are executed sequentially.

### Retake (non-event implementation detail)

`retakeOne` calls the coordinator again with the same slot but a new capture ID. The old original remains on disk; the new original is saved under a unique filename. Tests verify different IDs/paths and both files present.

> **Event scope (Phase 1F-R):** individual per-photo retake is not part of the event MVP. Code/tests may remain, but event validation uses **Retake All** only.

---

## 4. Image transfer/ingestion lifecycle

```text
Native camera (future) / mock
    -> CapturedImage(bytes, captureId)
    -> ImageValidator
       - JPEG magic or PNG (mock only)
       - size bounds
       - header dimensions
       - small decode to prove decodability
       - minimum long/short edge and pixel cap
    -> ImageIngestor
       - reject duplicate capture ID
       - reject capture-ID mismatch
       - atomic StorageService.saveOriginal
       - reopen file and revalidate
       - only then return a path
    -> BoothController photos
```

### Validation policy

- JPEG (`FF D8 FF`) accepted; PNG only when `camera.isSimulated`.
- Minimum 1 KB, maximum 40 MB.
- JPEG SOF header / PNG IHDR dimensions parsed without decoding the full 30 MP image.
- A small (≤128 px) decode verifies the payload is decodable without allocating a full bitmap.
- Default minimum long edge **1800 px**, short edge **600 px**, max 100 MP.
- EOS R JPEG originals should pass; a low-resolution preview is rejected.
- Original bytes are **not recompressed**.

### Duplicate delivery

`ImageIngestor` keeps accepted capture IDs for the process lifetime and also checks the session directory for an existing original before saving. A second delivery for the same ID is rejected with `DUPLICATE_IMAGE_DELIVERY`; no second file is written. This also catches redelivery after an app restart.

### Failure

Any validation/save/reopen failure returns a `CameraPipelineException`; the image is not added to `photos`. A failed save is deleted best-effort.

---

## 5. Storage guarantees

### Layout

```text
<documents>/events/<eventId>/sessions/<sessionId>/
  original_<slot>_<captureId>.jpg
  original_<slot>_<captureId>.png      # simulated mock only
  session.json
  .terabooth-tmp-*.part                # only during a write
```

The event/session structure is preserved. Filenames now include the capture ID; a slot may have multiple originals after retakes.

### Guarantees

- **Unique filenames:** target existence is checked; a suffix (`__2`, etc.) is added rather than overwriting.
- **Atomic writes:** bytes go to a temp file in the same directory, flush, length-check, then rename.
- **No incomplete originals exposed:** the final path is returned only after length/reopen validation.
- **No overwrite:** existing completed originals are never replaced.
- **Metadata:** `session.json` is written atomically and contains capture IDs/paths/dimensions.
- **Write failure:** `StorageException`; temp/target cleanup; explicit error to the pipeline.
- **Termination:** a temp file may remain; `recoverIncompleteWrites()` removes only temp/partial files and preserves completed originals.
- **Recovery:** `BoothController` calls recovery at session start. If a capture was interrupted, no image is fabricated; any completed original remains, and the operator can retake.

### Known storage limitation

A capture that fails after a valid file was saved (e.g. disconnect during the final storage step) may leave a complete but unreferenced original. It is not shown in the UI and is never reported as a successful capture. A future cleanup pass could reconcile unreferenced originals; not required for this phase.

---

## 6. Disconnect, background and restart behaviour

| Event | Behaviour |
|---|---|
| USB unplug during capture | `notifyDisconnected()` fails the active capture (`CAMERA_DISCONNECTED`); connection → `failed`; no success/photo |
| Power-off | Same as unexpected disconnect |
| Disconnect during transfer | Active capture fails; no success; connection failed. A file completing after the failure is not exposed |
| App background | Active capture fails with `APP_BACKGROUNDED`; queued requests fail; connection → `recovering`; no background capture |
| App foreground | One reconnect attempt from `recovering`; never auto-captures |
| Reconnect | Explicit `connect()` after reset/start; no automatic retry loop |
| App restart | New pipeline is disconnected; session start cleans temp files; completed originals remain; no fabricated recovery |
| Duplicate tap | Rejected before a second shutter request |

`main.dart` forwards `paused`/`hidden`/`resumed` lifecycle events to `BoothController`.

---

## 7. SDK-independent native contract

Defined in `lib/services/camera_contract.dart`; documented fully in `CASCABLECORE_API_MAPPING.md`.

- MethodChannel: `com.terabooth/camera`
- EventChannel: `com.terabooth/camera/events`
- Methods: `initialize`, `startDiscovery`, `stopDiscovery`, `connect`, `disconnect`, `capture`, `status`, `startLiveView`, `stopLiveView`, `dispose`
- Events: `discovery`, `connection`, `capture`, `liveViewFrame`, `error`
- Capture request includes `captureId`; result includes capture ID/path/width/height.
- Error codes include `CAMERA_LICENSE_MISSING`, `CAMERA_PERMISSION_DENIED`, `CAMERA_NOT_FOUND`, `CAMERA_CONNECT_TIMEOUT`, `CAMERA_DISCONNECTED`, `CAPTURE_IN_PROGRESS`, `DUPLICATE_CAPTURE`, `CAPTURE_TIMEOUT`, `TRANSFER_FAILED`, `DUPLICATE_IMAGE_DELIVERY`, `INVALID_IMAGE`, `UNSUPPORTED_IMAGE_FORMAT`, `STORAGE_FAILED`, `APP_BACKGROUNDED`.

The current Swift plugin is still a stub. The future CascableCore adapter must emit these events and call `captureId` through the channel. No CascableCore API is assumed or implemented here.

---

## 8. Remaining CascableCore dependencies

- Evaluation licence approval and installation.
- iOS deployment target raised to 14.0.
- SPM `CascableCoreSwift`/`CascableCore` added.
- `CascableCameraAdapter.swift` added to the Runner target and implemented.
- Native adapter must:
  - report connection/disconnection events;
  - implement `capture(captureId:)` only after a real image is received;
  - write/return the original JPEG;
  - report errors/timeouts.
- Physical iPad + EOS R testing and 10/10 sessions.

**No camera readiness is claimed.**

---

## 9. Tests and results

Commands run:

```bash
cd /Users/Apple/Dev/terabooth-event-mvp/ipad_app
flutter analyze
flutter test

cd ../windows_bridge
./.venv/bin/pytest -q
```

| Suite | Result |
|---|---|
| `flutter analyze` | **No issues** |
| `flutter test` | **38 passed** |
| `pytest -q` | **9 passed** |

### Required test coverage

| Required test | Test |
|---|---|
| Valid capture state transitions | `camera state machine accepts valid...` |
| Invalid transition rejection | `camera state machine rejects invalid...` |
| Duplicate capture prevention | `duplicate capture for the same slot...` |
| Sequential capture queue | `capture is sequential and never overlaps` |
| Capture timeout | `capture timeout fails without automatic retry` |
| Disconnect during capture | `disconnect during capture fails...` |
| Image validation | valid/invalid/low-resolution/PNG tests |
| Duplicate image delivery | `duplicate image delivery is rejected` / after new ingestor |
| Atomic image storage | storage unique/no-temp test |
| Storage failure | `write failure is explicit` / `storage failure is explicit` |
| Recovery from incomplete capture | `recovery removes partial temp files...` |
| Retake new capture ID | `retake gets a new capture ID...` |
| 3-photo workflow regression | `3-photo capture, review, retake and approve regression` |

Additional: disconnect during transfer, background capture failure, separate connection/capture state.

### Physical limitations

- No iPad/EOS R hardware test.
- No CascableCore SDK/licence.
- Mock PNG is allowed only as a simulated source; native must deliver JPEG.
- EXIF orientation is preserved but not normalized; print composition/rotation must be verified physically.
- Accepted-image tracking includes a storage lookup, so an existing original is detected after restart; the in-memory set remains an additional fast path.

---

## 10. Files changed in Phase 1C

- `lib/services/camera_service.dart`
- `lib/services/camera_contract.dart` (new)
- `lib/services/camera_pipeline.dart` (new)
- `lib/services/native_camera_service.dart`
- `lib/services/storage_service.dart`
- `lib/booth_controller.dart`
- `lib/main.dart`
- `lib/models.dart`
- `test/camera_pipeline_test.dart` (new)
- `test/booth_controller_test.dart`
- `test/storage_service_test.dart`
- `test/support.dart` (new)
- `test/fixtures/sample_1200x1800.jpg` (new)
- `test/fixtures/small_100x100.jpg` (new)
- `docs/technical/CAMERA_PIPELINE_RELIABILITY.md` (new)
- `docs/IMPLEMENTATION_LOG.md`

No CascableCore package, native camera implementation or Windows bridge change was made.
