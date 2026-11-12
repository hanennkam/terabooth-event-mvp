# Phase 3A-2L — Live View Lifecycle Cleanup Correction

## Overall result

**PASS for the source correction and static verification.**  
**Hardware behavior remains unverified** because this phase explicitly prohibited
camera discovery/connection.

The macOS harness now waits for the documented asynchronous Live View
termination callback before disconnecting, with a bounded fallback that logs an
unconfirmed stop. It no longer calls `endStream()` and `disconnect()` back-to-back.
No shutter or transfer code path was changed.

---

## 1. Official API evidence (CascableCore 18.0.2)

From the installed macOS framework headers:

- `CameraLiveView.beginStream(delivery:deliveryQueue:terminationHandler:)`
  starts streaming. Frame delivery is asynchronous and must call the supplied
  frame-completion block to receive more frames.
- `CameraLiveView.endStream()` has **no completion handler and returns void**.
- Header documentation for `endStream()`:

  > “Ends the current live view stream, if one is running. Will cause the
  > stream's termination handler to be called with
  > `CBLCameraLiveViewTerminationReasonEndedNormally`.”

- The termination handler is documented as the stream-ending notification. It is
  delivered on the main queue.
- There is no separate synchronous “stream fully stopped” API or completion
  callback beyond the termination handler.
- The SDK does **not** document a required wait between `endStream()` and
  `disconnect()`, but the termination handler is the only supported confirmation
  that streaming has ended.

### Termination reason 2

```text
CBLCameraLiveViewTerminationReasonFailed = 2
```

Header meaning:

> “The stream failed, due to disconnection or another failure.”

### Error 1008

```text
CBLErrorCodeNotAvailable = 1008
```

Header meaning:

> “The operation failed because the camera does not support the requested
> operation.”

This is **not** `NotConnected` (1002). It does not by itself prove a disconnect
race. It can indicate that the camera/SDK did not support the specific end
operation at that moment.

---

## 2. Existing cleanup sequence (before correction)

`stopAndDisconnect` previously did, synchronously:

```text
camera.endStream()
remove transfer handler
camera.disconnect(...)
```

Consequences:

- `endStream()` is asynchronous.
- `disconnect()` was requested before the termination handler could run.
- The live view termination callback could arrive after disconnect began.
- The camera object was released only in the disconnect callback, but the stream
  was not awaited.
- The stream could report `reason=2`/error `1008` during teardown.

This is consistent with a lifecycle-ordering problem, but it is not proven that
ordering is the sole cause of error 1008.

---

## 3. Correction

File: `macos_cascable_demo/main.swift`

### New state

```text
cleanupStarted
disconnectStarted
pendingDisconnectCamera
liveViewStartRequested
liveViewTerminationObserved
liveViewStopTimeout
```

### New flow

1. First cleanup request wins; later cleanup calls return.
2. If Live View may be active, call `endStream()`.
3. Wait for the SDK termination handler.
4. Only after the handler runs, remove the transfer handler and call
   `disconnect()`.
5. A 3-second fallback disconnects if no termination callback arrives, logging:

```text
CASCABLE_MAC_LIVE_VIEW=stop_timeout_unconfirmed
CASCABLE_MAC_LIVE_VIEW=termination_not_confirmed
```

The fallback is **not** treated as proof of a clean stop.

6. If the termination callback arrives after the fallback, it is logged and
   cannot trigger a duplicate disconnect.
7. If Live View is already inactive, disconnect proceeds immediately.
8. The camera object is retained until the disconnect callback completes.
9. No reconnect is added.
10. No shutter or transfer code was changed.

### Exact source shape

```text
stopAndDisconnect:
  guard !cleanupStarted
  pendingDisconnectCamera = camera
  if live view active:
      schedule 3s fallback
      camera.endStream()
  else:
      finishLiveViewCleanup()

terminationHandler:
  liveViewTerminationObserved = true
  log reason/error
  finishLiveViewCleanup()

finishLiveViewCleanup:
  guard pending camera && !disconnectStarted
  cancel fallback
  log unconfirmed if needed
  remove transfer handler
  camera.disconnect(...)
```

---

## 4. Root cause vs uncertainty

### Supported by evidence

- The pre-correction code ended streaming and disconnected immediately.
- The SDK’s termination notification is asynchronous.
- The observed failure occurred during that cleanup window.
- Waiting for the termination handler is the supported way to know streaming has
  ended.

### Not proven

- That ordering was the sole cause of `reason=2`/`1008`.
- That the corrected order will produce `reason=0` on the physical camera.
- That error 1008 will disappear; `NotAvailable` may indicate a camera/SDK
  limitation for this end operation.

No hardware run was performed to test the change.

---

## 5. Static verification

| Check | Result |
|---|---|
| macOS harness build | **BUILD SUCCEEDED** |
| Safe orchestration `source` | **PASS, CAMERA_COMMAND=false** |
| Safe orchestration `process` | **PASS, guard PASS, CAMERA_COMMAND=false** |
| `run-safe-test.sh` executable termination commands | **NONE** |
| Flutter analyze | **No issues** |
| Capability-only shutter guard | **`wantsTransfer && !capabilityOnly` remains** |
| Shutter call path changed | **NO** |
| Transfer call path changed | **NO** |
| Production/Flutter architecture changed | **NO** |

No hardware harness, discovery, connection, shutter, or transfer was run.

---

## 6. Safety confirmations

| Requirement | Result |
|---|---|
| Shutter requests | **NONE** |
| Camera capture | **NONE** |
| Camera-initiated transfer | **NONE** |
| `.original`/`.preview` transfer | **NONE** |
| Camera settings writes | **NONE** |
| Camera filesystem operations | **NONE** |
| USB/PTP reset | **NONE** |
| Camera discovery/connection in this phase | **NONE** |
| Cascable Studio terminated/relaunched | **NONE** |
| Application termination commands | **NONE** |
| Production camera integration changed | **NO** |
| CameraPipeline/ImageIngestor/MockCameraService changed | **NO** |
| Printing/QR/GIF/Windows Bridge changed | **NO** |
| Licence exposed | **NO** |

---

## 7. Remaining limitations

- The correction is not hardware-tested; a future explicitly authorized
  capability-only run must verify whether termination is now `reason=0`.
- If the EOS 60D returns `NotAvailable (1008)` even after waiting, the SDK/camera
  may not support the end operation as expected; that must be reported, not
  hidden.
- The 3-second fallback is a safety bound, not proof of clean termination.
- The Image Quality property remains unavailable/nil; JPEG-only is not
  independently verifiable through this SDK property.

---

## 8. Recommended next action

1. Do not run hardware automatically.
2. After a new explicit authorization, run one capability-only preflight through
   the safe orchestrator.
3. Check whether Live View termination is `reason=0`.
4. If `1008` persists, investigate camera/SDK end-stream support rather than
   adding delays or fabricating success.
5. Do not proceed to transfer or iPadOS testing from this static correction.

**No further hardware operation was performed.**
