# Phase 3A-2H — Single-Shot Original JPEG Transfer Validation

## Overall result

**BLOCKED**

The physical EOS 60D was USB-enumerated, but CascableCore USB-only discovery
did not return the camera during the authorized run. No shutter request was
issued. No transfer callback or JPEG was produced. I did not retry, per the
one-shot rule.

The temporary build artifact is intentionally removed; no test image exists.

---

## 1. Hardware preflight

Recorded before the failed run:

```text
Timestamp: 2026-11-12 02:30:03 +0800
Canon Digital Camera@02110000
sessionID      = 22310120635878
USBSpeed       = 3
UsbLinkSpeed   = 480000000
idVendor       = 1193
idProduct      = 12821
locationID     = 34668544
USB Address    = 2
```

Cascable Studio was stopped. No EOS Utility, Image Capture application, or
Photos application was running. Only Photos widget extensions and system
services remained.

An earlier no-shutter preflight at 02:29 succeeded:

```text
CASCABLE_MAC_DISCOVERED vendor=Canon Inc. model=Canon EOS 60D transport=1 state=0
CASCABLE_MAC_CONNECT=connected warnings=1 state=2 model=Canon EOS 60D transport=1
CASCABLE_MAC_WARNING type=0 category=0
CASCABLE_MAC_CAPABILITY_KNOWN_PROPERTIES=78
CASCABLE_MAC_STORAGE=devices 1
CASCABLE_MAC_STORAGE=shots_available 3014
CASCABLE_MAC_LIVE_VIEW=frame size=(1056.0, 704.0) format=0
CASCABLE_MAC_IMAGE_QUALITY=current nil set_type=1 valid_count=0 known=true
```

- Camera model: **Canon EOS 60D**
- Transport: **USB** (`1`)
- Warning: **`LowerThanExpectedFunctionality` / `RemoteControl`**
  (type `0`/category `0`), preserved
- Storage: one device, 3014 shots available
- Live View: real 1056×704 frame
- Image Quality property: **current value nil**, though the identifier is known
  (`known=true`)

### JPEG-only precondition

**JPEG-only was not independently confirmed before capture.** The Image Quality
property had no current value and no settable values. No camera setting was
changed. The phase’s payload-validation exception could have distinguished
actual payload format after a capture, but discovery failed before any capture.

---

## 2. Transfer handler preparation

The existing harness registers the camera-initiated transfer handler after
connection and before any shutter. In the failed run, connection never occurred,
so no handler/request was active.

No preview request was made. No filesystem fallback was used.

---

## 3. Authorized capture

| Item | Result |
|---|---|
| Shutter requests issued | **0** |
| Shutter accepted | **NO** |
| Capture ID | Not generated (no connection) |
| Physical capture | **NO** |

The run log:

```text
CASCABLE_MAC_LICENSE_RESULT=0
CASCABLE_MAC_BUNDLE=se.cascable.CascableCoreMacDemo
CASCABLE_MAC_DISCOVERY=started mode=usbOnly mode_args transfer=true
CASCABLE_MAC_TIMEOUT=terminating
```

No `CASCABLE_MAC_DISCOVERED`, `CONNECT`, `TRANSFER_REQUEST`, or
`SHUTTER` event occurred during this run.

No retry was attempted. The authorization’s single shutter was not used.

---

## 4. Transfer result

| Item | Result |
|---|---|
| Callbacks | **0** |
| `.original` availability | **NOT TESTED** |
| Preview availability | **NOT TESTED** |
| Predicted original bytes | **NOT AVAILABLE** |
| Actual transferred bytes | **0** |
| Transfer result | **NONE** |

No `.original` transfer was requested or executed. No preview or thumbnail was
substituted.

---

## 5. JPEG validation

| Check | Result |
|---|---|
| SOI marker | **NOT AVAILABLE** |
| EOI marker | **NOT AVAILABLE** |
| Decode | **NOT AVAILABLE** |
| Dimensions | **NOT AVAILABLE** |
| MIME/type | **NOT AVAILABLE** |
| SHA-256 | **NOT AVAILABLE** |
| EXIF | **NOT AVAILABLE** |
| Predicted vs actual bytes | **NOT AVAILABLE** |
| Temporary output | **None created** |

No `/tmp/terabooth-eos60d-jpeg-*` file or directory exists.

---

## 6. Duplicate callback

No callback occurred, so no duplicate callback was observed or ignored in this
run.

---

## 7. Safety

| Rule | Result |
|---|---|
| Maximum one shutter | **0 issued** |
| No retry | **Satisfied** |
| No second capture | **Satisfied** |
| No settings changed | **Satisfied** |
| No camera file delete/modify | **Satisfied** |
| No RAW conversion | **Satisfied** |
| No preview substitution | **Satisfied** |
| No filesystem fallback | **Satisfied** |
| No production integration | **Satisfied** |

No camera file was created, read, modified or deleted by this run.

---

## 8. Discovery failure and likely cause

Facts:

- USB enumeration was present before the run, with the same session as the
  earlier successful preflight.
- No user camera application was running.
- CascableCore USB-only discovery did not return the camera within the timeout.
- The earlier 02:29 no-shutter preflight had discovered/connected successfully
  with the same harness.

The cause of this specific discovery failure is **not proven**. Possible
contributors include a camera/system PTP session not released after the prior
run, camera sleep state, or a transient USB/PTP session issue. It is not
evidence that the camera or SDK is fundamentally incompatible; the earlier
preflight is direct evidence to the contrary.

Manual action is required before any new attempt:

1. Confirm the camera is awake and powered; battery was 2/4 in earlier runs.
2. Quit all camera apps; do not launch Studio.
3. Use a direct USB cable/port.
4. Confirm `ioreg` shows Canon EOS 60D.
5. Run capability-only discovery; wait for 78 properties/1 storage positive.
6. Only then request new authorization for one shutter.

Do not retry this blocked run automatically.

---

## 9. Final conclusion

| Statement | Status |
|---|---|
| A. CascableCore transferred `.original` in this run | **NO — no discovery** |
| B. Transferred `.original` verified as JPEG | **NO** |
| C. Camera independently confirmed JPEG-only | **NO — Image Quality nil** |
| D. Proven scope | **Nothing new about JPEG transfer** |

The phase did **not** establish macOS USB JPEG transfer. It only established a
discovery failure in this run, after a successful capability-only preflight.

---

## 10. Regression checks

| Check | Result |
|---|---|
| macOS harness build | **BUILD SUCCEEDED** |
| iOS production Bundle ID | **`com.terabooth.teraboothIpad`** |
| Production licence embedded | **NO** |
| `MockCameraService` default | **YES** |
| Production camera integration enabled | **NO** |
| Flutter tests | **96 passed** |
| Python tests | **39 passed** |
| Flutter analyze | **No issues** |
| Demo/production build configurations | **Healthy** |

No production camera integration, CameraPipeline, ImageIngestor,
MockCameraService, printing, GIF, QR or Windows Bridge was modified.

---

## 11. Recommended next step

The one-shot authorization was **not consumed** by a shutter, but a new attempt
must not be made automatically. Re-establish a clean capability connection with
a no-shutter run, then obtain explicit confirmation for one new single-shot
attempt.

Do not claim iPadOS compatibility from this macOS result.
