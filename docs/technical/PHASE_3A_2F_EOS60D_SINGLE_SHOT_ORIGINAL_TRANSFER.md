# Phase 3A-2F — EOS 60D Single-Shot Original JPEG Transfer

**Date:** 2026-11-12  
**Overall result:** **BLOCKED — no shutter request was issued.**

The preflight passed, but the required Step 2 condition cannot be satisfied with
the official CascableCore 18.0.2 API: a `CameraInitiatedTransferRequest`—and
therefore `canProvide(.original)`—is only delivered **after** a photograph is
taken. There is no pre-capture API to confirm `.original` availability.

Under the explicit safety rule “only if Step 2 confirms `.original` is
available,” issuing a shutter would violate the test protocol. I stopped.

No shutter request, transfer, JPEG creation, settings write or camera-file
operation occurred.

---

## 1. Preflight — PASS

Recorded at **2026-11-12 02:18:13 +0800**.

### USB

```text
Canon Digital Camera@02110000
sessionID      = 22300173558354
USBSpeed       = 3
UsbLinkSpeed   = 480000000
idVendor       = 1193
idProduct      = 12821
locationID     = 34668544
USB Address    = 2
```

The camera remained USB-enumerated after the SDK disconnect on the same session.

Cascable Studio was quit before the test. No EOS Utility, Image Capture
application or Photos application was running. No camera app was relaunched.

### SDK discovery / connection

```text
CASCABLE_MAC_LICENSE_RESULT=0
CASCABLE_MAC_BUNDLE=se.cascable.CascableCoreMacDemo
CASCABLE_MAC_DISCOVERY=started mode=usbOnly mode_args transfer=false
CASCABLE_MAC_DISCOVERED vendor=Canon Inc. model=Canon EOS 60D transport=1 state=0
CASCABLE_MAC_CONNECT=requested
CASCABLE_MAC_CONNECT=connected warnings=1 state=2 model=Canon EOS 60D transport=1
CASCABLE_MAC_WARNING type=0 category=0
```

Transport `1` = USB; state `2` = connected. Warning:

- `type 0` = `LowerThanExpectedFunctionality`
- `category 0` = `RemoteControl`

### Capability/storage preflight

```text
CASCABLE_MAC_CAPABILITY_FUNCTIONALITY_RAW=447936
CASCABLE_MAC_CAPABILITY_FUNCTIONALITY=fileDeletion,depthOfFieldPreview,shutterHalfPress,directFocusManipulation,exposureControl,cameraInitiatedTransfer,videoRecording,pannableLiveView
CASCABLE_MAC_CAPABILITY_COMMAND_CATEGORIES=stillsShooting,filesystemAccess
CASCABLE_MAC_CAPABILITY_KNOWN_PROPERTIES=78
CASCABLE_MAC_STORAGE=devices 1
CASCABLE_MAC_STORAGE=shots_available 724
CASCABLE_MAC_SETTINGS_WRITE=not_attempted
CASCABLE_MAC_LIVE_VIEW=frame size=(1056.0, 704.0) format=0
```

The one accessible storage device and positive shot count satisfied preflight.
`cameraInitiatedTransfer` is present, but this does **not** prove `.original`
availability.

### Settings observed (unchanged)

```text
Aperture 3.5 | Shutter ⅟80 | ISO 5000 | AE M | Battery 2/4
White Balance Automatic | Drive Single Shot | Exposure Comp 0
```

No setting write occurred.

---

## 2. Transfer API inspection — definitive blocker

Official CascableCore 18.0.2 API:

- `Camera.addCameraInitiatedTransferHandler(_:)` registers a handler.
- A `CameraInitiatedTransferRequest` is delivered **after a shot is taken**
  (the SDK header says this “typically happens soon after a shot is taken”).
- Only that request exposes:
  - `isValid`
  - `availableRepresentations`
  - `canProvide(.original)`
  - `predictedFileSize(for: .original)`
  - `isOnlyDestinationForImage`
- `executeTransfer(for: .original)` and
  `generateData(for: .original)` are valid only on that request.

There is no API to enumerate representations or ask “will this camera provide an
original?” before capture. The supported-functionality bit
`cameraInitiatedTransfer` only indicates the general mechanism.

Therefore Step 2’s pre-capture requirement cannot be met. No `.original`
availability can be claimed or refuted without first taking a photograph.

| Step 2 item | Result |
|---|---|
| Request delivered | **NO — only post-capture** |
| `isValid` | **NOT AVAILABLE** |
| `availableRepresentations` | **NOT AVAILABLE** |
| `canProvide(.original)` | **NOT AVAILABLE** |
| `canProvide(.preview)` | **NOT AVAILABLE** |
| Predicted original size | **NOT AVAILABLE** |
| `isOnlyDestinationForImage` | **NOT AVAILABLE** |
| `executeTransfer` / `generateData` | **NOT CALLED** |

---

## 3. Exactly one controlled capture — NOT RUN

No shutter request was sent. The run used `--capability-only`, which explicitly
disables the transfer/shutter path and does not reconnect.

- Unique capture ID: **none**
- Shutter requests: **0**
- Physical capture confirmed: **NO**
- Transfer request: **none**
- Transfer callback: **none**
- Preview substitution: **none**
- Filesystem fallback: **none**

No second shutter was issued or scheduled.

---

## 4. JPEG validation — NOT RUN

No bytes were received. Therefore:

- file size: **NOT AVAILABLE**
- JPEG SOI/EOI: **NOT AVAILABLE**
- decode: **NOT AVAILABLE**
- pixel dimensions: **NOT AVAILABLE**
- EXIF: **NOT AVAILABLE**
- SHA-256: **NOT AVAILABLE**
- camera-file SHA comparison: **NOT POSSIBLE**
- original-vs-thumbnail: **NOT DETERMINED**

No `/tmp/terabooth-eos60d-original-*` directory was created.

---

## 5. Cleanup — PASS

```text
CASCABLE_MAC_DISCONNECT=requested
CASCABLE_MAC_LIVE_VIEW=terminated reason=0 error=none
CASCABLE_MAC_LOST_SIGHT model=Canon EOS 60D
CASCABLE_MAC_DISCONNECT=complete error=none
CASCABLE_MAC_DISCONNECT=capability_only_exit
```

- Live View stopped normally.
- SDK disconnected cleanly.
- No reconnect was performed by the harness.
- Final `ioreg` still showed the same session `22300173558354`, location
  `34668544`, vendor `1193`, product `12821`.
- No camera file was created, read, deleted or modified.
- No temporary image exists.

---

## 6. What remains unverified

- `.original` representation availability.
- Original JPEG transfer execution.
- Physical capture.
- JPEG validation and SHA-256.
- Exact comparison with the SD-card file.
- Settings write/restore.
- iPadOS USB compatibility.

A successful capability/preflight session does not prove original transfer.

---

## 7. Build/test status

| Check | Result |
|---|---|
| macOS harness build | **BUILD SUCCEEDED** |
| Mac licence | **PASS — result 0** |
| Preflight/USB/storage | **PASS** |
| Shutter request | **NOT SENT** |
| Transfer/JPEG | **NOT RUN** |
| Settings write | **NOT PERFORMED** |
| iOS production build | **PASS — 175 MB** |
| Production Bundle ID | **`com.terabooth.teraboothIpad`** |
| Production licence | **ABSENT** |
| Flutter tests | **96 passed** |
| Python tests | **39 passed** |
| CameraPipeline/ImageIngestor/MockCameraService changed | **NO** |
| Printing/GIF/QR/Windows Bridge changed | **NO** |

No licence material was exposed. No camera settings or files were changed.

---

## 8. Implications for the iOS adapter

The iOS adapter remains conservative:

- It requires `.original` bytes.
- It does not substitute preview data.
- It does not report shutter request as success.
- It has no filesystem fallback.
- It remains disabled by default.

3A-2F did not produce new evidence about `.original` availability. The key
compatibility risk remains unresolved.

---

## 9. Exact next decision

The protocol must choose one of these:

**Option A — Authorize one controlled shutter without pre-capture `.original`
confirmation.** This is the only way the SDK can reveal whether `.original` is
offered. It must remain one shutter, no retry, no preview substitution.

**Option B — Keep the pre-capture rule.** Then original-transfer validation is
impossible with the current API and remains permanently blocked.

No pre-capture capability API exists in CascableCore 18.0.2.

---

## 10. Recommended next phase

If Option A is approved:

1. Confirm camera awake, Studio closed, one storage/724 shots.
2. Trigger exactly one shutter.
3. Log request `isValid`, representations, `canProvide(.original)`, predicted
   size, `isOnlyDestinationForImage`.
4. If `.original` is unavailable, stop; do not substitute.
5. If available, execute once, generate data, save under a unique `/tmp`
   directory, record SHA-256/decode/dimensions/EXIF, compare if possible.
6. Stop after success; no second shot.

A successful macOS transfer would still not establish iPadOS compatibility.
