# Phase 3A-2G — Authorized Single-Shot Original Transfer

**Date:** 2026-11-12  
**Overall result:** **PARTIAL** — exactly one shutter request was issued, the camera offered `.original`, and the full original payload was transferred. However, the original representation was **CR2 (RAW)**, not JPEG. No JPEG was validated or saved.

**Exactly one shutter request was issued. No retry, no second capture, no settings change, no file deletion, and no preview substitution occurred.**

---

## 1. Preflight

Recorded at **2026-11-12 02:22:17 +0800** (UTC 2026-11-11T18:22:17Z).

### USB

```text
Canon Digital Camera@02110000
sessionID      = 22304111800016
USBSpeed       = 3
UsbLinkSpeed   = 480000000
idVendor       = 1193
idProduct      = 12821
locationID     = 34668544
USB Address    = 2
```

Cascable Studio was quit before the run. No EOS Utility, Image Capture
application or Photos application was running. No physical disconnect/reconnect
was performed.

### SDK preflight

```text
CASCABLE_MAC_LICENSE_RESULT=0
CASCABLE_MAC_BUNDLE=se.cascable.CascableCoreMacDemo
CASCABLE_MAC_DISCOVERY=started mode=usbOnly mode_args transfer=true
CASCABLE_MAC_DISCOVERED vendor=Canon Inc. model=Canon EOS 60D transport=1 state=0
CASCABLE_MAC_CONNECT=connected warnings=1 state=2 model=Canon EOS 60D transport=1
CASCABLE_MAC_WARNING type=0 category=0
CASCABLE_MAC_TRANSFER_HANDLER=registered token=true
CASCABLE_MAC_CAPABILITY_KNOWN_PROPERTIES=78
CASCABLE_MAC_STORAGE=devices 1
CASCABLE_MAC_STORAGE=shots_available 724
```

- Storage: one device; positive remaining shots.
- Warning: `LowerThanExpectedFunctionality` / `RemoteControl`
  (type 0/category 0), preserved.
- Live View delivered a 1056×704 frame.
- No settings were changed.

---

## 2. Handler and capture correlation

The camera-initiated transfer handler was registered **before** the shutter:

```text
CASCABLE_MAC_TRANSFER_HANDLER=registered token=true
```

A unique capture correlation ID was generated:

```text
capture_id = cap_146a585b-1a31-4f15-8e42-fe21b81a51de
```

Timeout and duplicate-callback guards were active. No preview transfer was
requested or substituted.

---

## 3. Exactly one shutter

```text
02:22:24.834 CASCABLE_MAC_SHUTTER=requested capture_id=cap_146a585b-1a31-4f15-8e42-fe21b81a51de error=none
```

- Exactly **one** shutter request was issued.
- The SDK accepted the request without error.
- A physical capture was subsequently confirmed by the original-file transfer.

No second shutter request was issued, including after validation failure or
timeout.

---

## 4. Transfer request details

```text
02:22:26.934 CASCABLE_MAC_TRANSFER_REQUEST count=1
  capture_id=cap_146a585b-1a31-4f15-8e42-fe21b81a51de
  valid=true
  representations=3
  can_original=true
  can_preview=true
  predicted_original_bytes=14069528
  only_destination=false
```

`.original` **was available** on this request. `representations=3` means both
preview and original bits were present.

The exact API used:

- `Camera.addCameraInitiatedTransferHandler(_:)`
- `CameraInitiatedTransferRequest.isValid`
- `CameraInitiatedTransferRequest.availableRepresentations`
- `CameraInitiatedTransferRequest.canProvide(.original)`
- `CameraInitiatedTransferRequest.predictedFileSize(for: .original)`
- `CameraInitiatedTransferRequest.executeTransfer(for: .original, completionHandler:)`
- `CameraInitiatedTransferResult.generateData(for: .original, completionHandler:)`

---

## 5. Transfer execution result

```text
CASCABLE_MAC_TRANSFER=original_requested
CASCABLE_MAC_TRANSFER_RESULT available=3 contains_original=true filename=IMG_9646.CR2
CASCABLE_MAC_ORIGINAL=bytes 14069528 predicted_bytes=14069528
  jpeg_signature=false eoi=true
  sha256=a3e23b566c5595495da8ef98637579df63448e57d563ea37a76442fa32211742
  capture_id=cap_146a585b-1a31-4f15-8e42-fe21b81a51de
CASCABLE_MAC_ORIGINAL=failed_jpeg_signature
```

The original payload was complete relative to the SDK prediction:

- Predicted original bytes: **14,069,528**
- Received bytes: **14,069,528**
- Transfer filename: **IMG_9646.CR2**
- Content type: **CR2 RAW**, not JPEG
- JPEG SOI (`FF D8 FF`): **false**
- JPEG EOI check: **true**, but this does not make a CR2 a JPEG; the signature
  check correctly failed.

Because the payload was not JPEG, **no file was written** under
`/tmp/terabooth-eos60d-original-*`. The harness did not save a misnamed or
misrepresented file.

---

## 6. Second transfer request / duplicate

At the same timestamp as validation failure, a second transfer request for the
same capture was delivered:

```text
CASCABLE_MAC_TRANSFER_REQUEST count=2
  capture_id=cap_146a585b-1a31-4f15-8e42-fe21b81a51de
  valid=true
  representations=3
  can_original=true
  can_preview=true
  predicted_original_bytes=3554984
  only_destination=false
CASCABLE_MAC_TRANSFER=duplicate_callback_ignored
```

The second request was ignored; no transfer was executed and no preview or
thumbnail was substituted. It is **not known** whether this was a JPEG companion
from a RAW+JPEG camera setting, another representation, or a duplicate camera
event. No claim is made.

The one-shot authorization did not permit another shutter or a retry.

---

## 7. JPEG validation — NOT PASSED

| Check | Result |
|---|---|
| Byte count | **14,069,528** |
| JPEG SOI | **FAIL — CR2** |
| JPEG EOI | true, but not meaningful for CR2 |
| Decode as JPEG | **NOT ATTEMPTED — signature failed** |
| Pixel dimensions | **NOT VALIDATED** |
| EXIF | **NOT VALIDATED** |
| Full original vs thumbnail | **NOT VALIDATED** |
| SHA-256 | `a3e23b566c5595495da8ef98637579df63448e57d563ea37a76442fa32211742` |
| Camera-file byte comparison | **NOT POSSIBLE / NOT PERFORMED** |

The SHA-256 above is for the received CR2 payload. It is not compared to the
camera-stored `IMG_9646.CR2`.

No JPEG file was preserved because none was received.

---

## 8. Timeout / cleanup

Because JPEG validation failed, the capture was not marked successful and the
transfer timeout remained active:

```text
CASCABLE_MAC_TRANSFER=timeout
CASCABLE_MAC_DISCONNECT=requested
CASCABLE_MAC_LIVE_VIEW=terminated reason=0 error=none
CASCABLE_MAC_LOST_SIGHT model=Canon EOS 60D
CASCABLE_MAC_DISCONNECT=complete error=none
CASCABLE_MAC_DISCONNECT=no_reconnect_exit
```

- Live View stopped.
- SDK disconnected cleanly.
- No reconnect was performed.
- The camera remained USB-enumerated on the same session
  `22304111800016`.
- No second capture occurred.
- No camera file was deleted or modified.

---

## 9. Camera image format implication

The original representation is CR2. This indicates that the camera’s current
image-quality setting is producing RAW (possibly RAW+JPEG), not JPEG-only. **No
camera setting was changed** in this phase.

The task requires an original JPEG. The single authorized capture cannot be
reused with different settings. A future test must either:

- have the user manually set the camera to JPEG-only **before** a new authorized
  capture, or
- explicitly authorize RAW handling (outside the current JPEG pipeline).

The second callback may have been a JPEG companion, but it was not transferred
or inspected. It must not be represented as a JPEG success.

---

## 10. What was tested vs unverified

### Tested successfully

- One shutter request accepted.
- Physical capture confirmed by original transfer.
- `.original` availability: **true**.
- Complete original payload received; byte count matched prediction.
- CR2 SHA-256 computed.
- Warning retained.
- Clean Live View stop/disconnect.
- No preview substitution; no retry.

### Not tested / failed

- Original **JPEG** delivery.
- JPEG decode/dimensions/EXIF.
- Camera-file SHA comparison.
- Settings write/restore.
- iPadOS USB/transfer.

### Blocked

- JPEG-specific validation by camera image-quality setting and one-shot
  authorization.

### Not claimed

- Full EOS 60D compatibility.
- iPadOS compatibility.
- That the second callback was JPEG.

---

## 11. Implications for the iOS adapter

The iOS adapter currently accepts JPEG only. The observed behavior means a
RAW/RAW+JPEG-configured EOS 60D may deliver a **CR2** `.original`, which the
adapter correctly rejects as `INVALID_IMAGE`/unsupported rather than saving a
mislabeled file.

Before iPad integration, the project must decide:

1. require **JPEG-only camera setting** (manual, verified preflight), or
2. add explicit RAW support/conversion (not current scope), or
3. handle multiple transfer requests per shutter and select a JPEG companion if
   actually offered.

The current adapter’s one-pending/duplicate-callback guard may ignore a second
transfer request. That is acceptable for safety now but must be revisited if
the camera is configured RAW+JPEG.

Do not enable the camera service by default.

---

## 12. Final status

| Check | Result |
|---|---|
| macOS harness build | **BUILD SUCCEEDED** |
| Mac licence | **PASS — result 0** |
| Camera/USB | **PASS** |
| Exactly one shutter | **YES** |
| `.original` offered | **YES** |
| Original payload complete | **YES — 14,069,528 bytes** |
| Original JPEG | **NO — CR2** |
| JPEG validation | **FAIL (not JPEG)** |
| File saved | **NO** |
| SHA-256 computed | **YES (CR2)** |
| Camera-file comparison | **NO** |
| Camera settings changed | **NO** |
| Camera files deleted/modified | **NO** |
| iOS production build | **PASS — 175 MB** |
| Production Bundle ID | **`com.terabooth.teraboothIpad`** |
| Production licence | **ABSENT** |
| Flutter tests | **96 passed** |
| Python tests | **39 passed** |

No production camera integration, CameraPipeline, ImageIngestor,
MockCameraService, printing, GIF, QR or Windows Bridge was changed.

**No second capture will be issued.**

---

## 13. Recommended next phase

1. User manually sets EOS 60D to **JPEG-only** image quality (no code/settings
   change by the harness).
2. Obtain new explicit authorization for exactly one additional controlled
   shutter.
3. Rerun the one-shot harness; expect JPEG SOI/EOI, decode, dimensions, EXIF,
   SHA-256.
4. If a second callback appears and appears to be a JPEG companion, decide
   explicitly whether it belongs to the authorized capture; do not silently
   transfer it under the current one-shot guard.
5. Compare against the camera file if feasible.
6. Do not begin iPad integration from RAW-only results.
