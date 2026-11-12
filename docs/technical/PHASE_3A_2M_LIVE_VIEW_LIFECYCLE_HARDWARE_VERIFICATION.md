# Phase 3A-2M — Live View Lifecycle Hardware Verification

## Overall result

**PARTIAL**

The single capability-only run succeeded for discovery, connection, capability
reads, storage and Live View frame delivery. The Phase 3A-2L cleanup ordering
also worked: disconnect was requested only after the Live View termination
callback.

However, Live View still terminated with:

```text
reason=2
se.cascable error 1008
```

The 3-second fallback was **not** used. This disproves the hypothesis that the
previous failure was solely caused by disconnecting before the termination
callback; the EOS 60D/CascableCore end-stream operation itself is returning a
failure.

No shutter, capture, transfer, settings write, filesystem operation, reconnect
or application termination occurred.

---

## 1. Orchestration

Exact invocation:

```bash
cd /Users/Apple/Dev/terabooth-event-mvp/macos_cascable_demo
./orchestration/run-safe-test.sh \
  --mode capability \
  --allow-hardware \
  --authorization capability-preflight
```

- Mode: **capability**
- Authorization: **capability-preflight**
- `--transfer`: **absent**
- `--single-shot`: **absent**
- Guard: **PASS**
- Competing camera apps: **none detected**
- No application termination command executed
- `CAMERA_COMMAND=true` only for the capability harness

Log:

```text
macos_cascable_demo/logs/orchestration-20261112T025456+0800-75453.log
```

---

## 2. USB preflight / postflight

Before:

```text
Canon Digital Camera@01120000
sessionID      = 22351073318200
USBSpeed       = 3
UsbLinkSpeed   = 480000000
idVendor       = 1193
idProduct      = 12821
locationID     = 17956864
USB Address    = 1
```

After SDK disconnect, the same Canon device and **same session ID**
`22351073318200` remained enumerated. No USB/PTP reset or physical reconnect
occurred.

---

## 3. CascableCore discovery and connection

```text
CASCABLE_MAC_LICENSE_RESULT=0
CASCABLE_MAC_BUNDLE=se.cascable.CascableCoreMacDemo
CASCABLE_MAC_DISCOVERY=started mode=usbOnly mode_args transfer=false
CASCABLE_MAC_DISCOVERED vendor=Canon Inc. model=Canon EOS 60D transport=1 state=0
CASCABLE_MAC_CONNECT=connected warnings=1 state=2 model=Canon EOS 60D transport=1
CASCABLE_MAC_WARNING type=0 category=0
```

- Model: **Canon EOS 60D**
- Transport: **USB** (`1`)
- Connection state: connected (`2`)
- Warning: **`LowerThanExpectedFunctionality` / `RemoteControl`**
  (type 0/category 0), preserved.
- Cleanup once-only guards active.

---

## 4. Capability

```text
CASCABLE_MAC_CAPABILITY_FUNCTIONALITY_RAW=447936
CASCABLE_MAC_CAPABILITY_FUNCTIONALITY=fileDeletion,depthOfFieldPreview,shutterHalfPress,directFocusManipulation,exposureControl,cameraInitiatedTransfer,videoRecording,pannableLiveView
CASCABLE_MAC_CAPABILITY_COMMAND_CATEGORIES=stillsShooting,filesystemAccess
CASCABLE_MAC_CAPABILITY_KNOWN_PROPERTIES=78
CASCABLE_MAC_STORAGE=devices 1
CASCABLE_MAC_STORAGE=shots_available 3014
```

Selected properties:

```text
Aperture 3.5 | Shutter ⅟80 | ISO 5000 | AE M | Battery 2/4
White Balance Automatic | Drive Single Shot | Exposure Comp 0
```

Image Quality:

```text
CASCABLE_MAC_IMAGE_QUALITY=current nil set_type=1 valid_count=0 known=false
```

JPEG-only remains **not independently verifiable** through this SDK property.
No settings were changed.

---

## 5. Live View frame

```text
CASCABLE_MAC_LIVE_VIEW=started
CASCABLE_MAC_LIVE_VIEW=frame size=(1056.0, 704.0) format=0
```

A real physical 1056×704 Live View frame was delivered.

---

## 6. Live View termination

```text
02:55:10.158 CASCABLE_MAC_LIVE_VIEW=stop_requested
02:55:10.166 CASCABLE_MAC_LIVE_VIEW=terminated reason=2 error=The operation couldn’t be completed. (se.cascable error 1008.)
02:55:10.166 CASCABLE_MAC_DISCONNECT=requested
```

- `reason=2` = `CBLCameraLiveViewTerminationReasonFailed`.
- error `1008` = `CBLErrorCodeNotAvailable` (“camera does not support the
  requested operation”).
- The termination callback arrived **before** the disconnect request.
- The 3-second fallback did **not** fire.
- No `stop_timeout_unconfirmed` or `termination_not_confirmed` log exists.

### Conclusion from this evidence

The 2L ordering correction worked:

- `endStream()` was requested.
- The SDK termination callback arrived.
- Only then was `disconnect()` requested.

But the termination itself was still a failure. The earlier failure was not
solely a disconnect-before-callback race. The EOS 60D/CascableCore end-stream
operation is returning `NotAvailable` in this state.

---

## 7. Disconnect / post-disconnect

```text
CASCABLE_MAC_DISCONNECT=requested
CASCABLE_MAC_LOST_SIGHT model=Canon EOS 60D
CASCABLE_MAC_DISCONNECT=complete error=none
CASCABLE_MAC_DISCONNECT=no_reconnect_exit
```

- Disconnect occurred after the termination callback.
- Disconnect callback completed with no SDK error.
- No reconnect.
- Camera remained USB-enumerated on the same session.
- No harness/camera process remains.

---

## 8. Safety / regression

| Requirement | Result |
|---|---|
| Shutter requests | **0** |
| Physical capture | **NONE** |
| Transfer callbacks | **0** |
| Transfer executions | **0** |
| `.original` / `.preview` transfer | **NONE** |
| Camera settings writes | **NONE** |
| Camera filesystem operations | **NONE** |
| USB/PTP reset | **NONE** |
| Reconnect / retry | **NONE** |
| Cascable Studio terminated/relaunched | **NO** |
| External application termination | **NONE** |
| Capability-only shutter guard | **`wantsTransfer && !capabilityOnly` intact** |
| Production Bundle ID | **`com.terabooth.teraboothIpad`** |
| Production licence embedded | **NO** |
| MockCameraService default | **YES** |
| CameraPipeline/ImageIngestor/MockCameraService changed | **NO** |
| Printing/QR/GIF/Windows Bridge changed | **NO** |

The log contains no `CASCABLE_MAC_SHUTTER` or `CASCABLE_MAC_TRANSFER_REQUEST`
line.

---

## 9. Remaining limitations

- Normal Live View termination is **not achieved**: reason 2/error 1008 persists.
- Error 1008 is `NotAvailable`, not a disconnection error; it may reflect a
  camera-specific limitation of the end-stream operation.
- No retry or alternative shutdown strategy was attempted.
- JPEG-only remains unverified (Image Quality nil).
- No JPEG transfer or iPadOS compatibility is claimed.

---

## 10. Recommended next action

1. Do not retry automatically.
2. Treat the end-stream `NotAvailable` as a camera/SDK lifecycle limitation, not
   a simple ordering race.
3. Investigate a safer supported strategy before another hardware test:
   - whether omitting explicit `endStream()` and relying on disconnect is
     supported, or
   - whether the camera requires a different command-category/state transition
     before ending Live View.
   Do not implement this without review.
4. Keep the 2L wait-for-callback logic; it is correctly ordered and prevents a
   disconnect-before-callback race.
5. Do not proceed to transfer or iPadOS testing from this result.

No further hardware operation was performed.
