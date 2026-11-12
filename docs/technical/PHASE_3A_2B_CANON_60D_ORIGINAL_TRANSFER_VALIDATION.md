# Phase 3A-2B — Canon EOS 60D Original Transfer & Capability Validation

**Date:** 2026-11-12  
**Overall result:** **BLOCKED at the time of 3A-2B** — follow-up 3A-2C later found the EOS 60D enumerated and storage reported after Cascable Studio was closed. No 3A-2B transfer result is retroactively claimed.

**Update (3A-2C):** USB preflight later found the camera present with 1 storage device and 724 shots when Studio was closed. Original transfer still requires a new run. — the EOS 60D was not enumerated on USB during this phase and no SD card was mounted. The macOS test harness was extended and builds successfully, but no live capability, original-transfer, settings-write or capture-lifecycle test could be run.

No shutter was triggered in this phase. No image was received. No camera file was modified or deleted.

---

## 1. Environment

| Item | Value |
|---|---|
| Project | `/Users/Apple/Dev/terabooth-event-mvp` |
| macOS | 26.5.1 (25F80) |
| Hardware | MacBookPro18,1 |
| Xcode | 26.6 (17F113) |
| Mac demo target | `macos_cascable_demo/TeraboothCascableMacDemo` |
| Mac Bundle ID | **`se.cascable.CascableCoreMacDemo`** |
| SDK | CascableCore **18.0.2** |
| SDK revision | `4407ce7682e82bb0b152ddcfad4cfd98609941fa` |
| Licence | existing local demo licence; result `0`; bytes not exposed |
| Camera | Canon EOS 60D (not enumerated at test time) |
| Storage | No external SD volume mounted |

`Package.resolved` is the existing official remote pin. No local package
substitution was introduced.

---

## 2. Harness audit

Existing behavior confirmed before modification:

- Licence loaded from the ignored bundle resource and applied with
  `CascableCoreLicenseVerification.apply(license:)`.
- USB-only `CameraDiscovery`.
- Canon model/transport logging.
- Connection warning type/category logging.
- Property read of aperture, shutter, ISO, AE mode, battery, image quality.
- Live View first-frame logging and normal termination.
- Stop/end-stream, transfer-handler removal, disconnect and reconnect.

The harness was extended with:

- Full supported-functionality bit logging and decoding.
- Current command-category logging and decoding.
- `liveViewStreamActive`, storage devices and known-property counting.
- Property `valueSetType`, `currentValue`, `validSettableValues` count/preview and
  `validValueRange` logging.
- A camera-initiated original-transfer handler.
- Request validation: `isValid`, available representations,
  `canProvide(.original)`, `canProvide(.preview)`, predicted original size,
  `isOnlyDestinationForImage`.
- Only `.original` transfer/`generateData(for: .original)`; no preview fallback.
- Temporary original save under `/tmp`, JPEG signature/decode/dimension/EXIF/file
  size validation.
- Explicit “exact camera-file comparison not performed” logging.
- Storage gate: `--transfer` refuses to trigger a shutter when
  `storageDevices.count == 0`.
- Transfer timeout, duplicate callback guard, optional
  disconnect-during-transfer mode, and clean reconnect.

The harness does not perform settings writes automatically.

---

## 3. USB discovery and connection evidence

### Current phase

Commands were run with Cascable Studio absent:

```text
CASCABLE_MAC_LICENSE_RESULT=0
CASCABLE_MAC_BUNDLE=se.cascable.CascableCoreMacDemo
CASCABLE_MAC_DISCOVERY=started mode=usbOnly mode_args transfer=false
```

The capability-only run and the `--transfer` run both waited for USB discovery;
no Canon device appeared. `ioreg` showed no `Canon Digital Camera` entry at that
time. Therefore:

- No current camera connection evidence exists for this phase.
- No current capability data exists for this phase.
- No shutter was sent.
- No transfer request was received.

### Earlier evidence, not re-tested here

Phase 3A-1B previously established on this same Mac/camera/SDK:

- Canon EOS 60D USB discovery and connection.
- 77 known property identifiers.
- 1056×704 Live View frame.
- One shutter request accepted without SDK error.
- Disconnect/reconnect success.
- Warning: `LowerThanExpectedFunctionality` / `RemoteControl`.

Those results are historical evidence only and were not re-run in 3A-2B.

---

## 4. Capability investigation — BLOCKED

The harness now logs, when a camera is connected:

- `supportedFunctionality.rawValue` and decoded feature names
- `currentCommandCategories.rawValue` and decoded categories
- `liveViewStreamActive`
- `knownPropertyIdentifiers.count`
- `storageDevices.count`
- shots available
- selected property `valueSetType`, `currentValue`,
  `validSettableValues` count/preview, `validValueRange`

Because no camera was enumerated, none of these values is available for the
EOS 60D in this phase.

**Status: IMPLEMENTED, NOT TESTED / BLOCKED by no current USB camera.**

No writable-setting claim is made.

---

## 5. Remote-control warning

The exact warning previously observed in Phase 3A-1B remains:

```text
type=0 category=0
```

Interpretation:

- type `0` = `LowerThanExpectedFunctionality`
- category `0` = `RemoteControl`

The warning is preserved; it is not dismissed or suppressed. The harness still
logs all connection warnings. The warning does not, by itself, identify which
operations fail. Feature flags, command categories, properties and actual
operations must be checked.

No new warning was observed in 3A-2B because no connection occurred.

---

## 6. Original transfer request — BLOCKED

The harness installs the camera-initiated transfer handler on connection and
logs the required request metadata. It does not substitute preview/thumbnail
data.

For this phase:

| Check | Result |
|---|---|
| Camera advertises original transfer | **NOT TESTED** |
| `isValid` | **NOT TESTED** |
| `canProvide(.original)` | **NOT TESTED** |
| `executeTransfer(for: .original)` | **IMPLEMENTED, NOT TESTED** |
| `generateData(for: .original)` | **IMPLEMENTED, NOT TESTED** |
| Original bytes received | **NONE** |

No original-transfer request arrived because no camera was connected.

---

## 7. Original JPEG validation — BLOCKED

No bytes were received. Therefore the following are not validated:

- JPEG signature
- Image decoding
- Dimensions
- File size
- EXIF metadata
- Camera-side file identity
- Exact byte comparison against a camera file

The harness’s temporary save path and ImageIO validation are implemented but
untested.

No `--transfer` shutter was sent. The storage gate logged/blocked the operation
when storage was unavailable; because the camera was absent, the run stopped at
discovery.

---

## 8. Settings write — NOT ATTEMPTED / BLOCKED

No camera was connected. The harness only audits property writability metadata.
It did not change aperture, shutter, ISO or any other camera setting.

| Check | Result |
|---|---|
| Writable property discovered | **NOT TESTED** |
| Original value recorded | **NOT TESTED** |
| Valid settable values inspected | **NOT TESTED** |
| Non-destructive change | **NOT ATTEMPTED** |
| Camera confirms new value | **NOT TESTED** |
| Original value restored | **NOT TESTED** |

No firmware, storage, deletion or destructive setting was touched.

---

## 9. Capture lifecycle / reliability — BLOCKED

The harness supports one-shot transfer mode, a 20-second transfer timeout,
duplicate callback guard, optional disconnect during transfer, and reconnect.
None could be exercised without a camera.

| Test | Result |
|---|---|
| One shutter request | **NOT RUN — no camera** |
| Transfer request arrival | **NOT RUN** |
| Transfer success | **NOT RUN** |
| Timeout handling | **IMPLEMENTED, NOT RUN** |
| Disconnect during transfer | **IMPLEMENTED, NOT RUN** |
| Duplicate transfer callback | **IMPLEMENTED, NOT RUN** |
| Clean reconnect | **NOT RUN this phase** |
| Shutter without image reported as success | **No** — harness only marks success after validated original data |

No automatic shutter retry exists.

---

## 10. Build and final validation

| Check | Result |
|---|---|
| macOS harness build | **BUILD SUCCEEDED** |
| macOS licence | **PASS — result 0** |
| Mac Bundle ID | `se.cascable.CascableCoreMacDemo` |
| Camera connected | **NO** |
| SD card mounted | **NO** |
| iOS production build | **PASS — 175 MB** |
| Production Bundle ID | **`com.terabooth.teraboothIpad`** |
| Production licence file | **ABSENT** |
| `flutter analyze` | **No issues** |
| Flutter tests | **96 passed** |
| Python tests | **39 passed** |
| Production camera service enabled | **NO** |
| CameraPipeline/ImageIngestor/MockCameraService changed | **NO** |
| Printing/GIF/QR/Windows Bridge changed | **NO** |

No licence bytes were output; the Mac and iPad licence files remain local and
ignored.

---

## 11. Known limitations

- No current USB camera, so capability and original-transfer validation are
  blocked.
- No SD card, so storage, camera-side file info and original-byte comparisons
  are blocked even if the camera is reconnected.
- Camera-initiated original transfer may not be offered by the EOS 60D; this is
  exactly what must be measured.
- Exact comparison with the camera-side file requires a filesystem workflow and
  was not implemented.
- Settings write was deliberately not attempted.
- The historical macOS warning remains unresolved in meaning beyond its
  type/category.
- No iPadOS behavior is inferred from macOS.

---

## 12. Implications for the iOS adapter

The existing iOS adapter remains conservative and correct:

- It waits for `.original` bytes; it does not substitute preview data.
- It does not claim a capture from the shutter callback.
- It has no filesystem fallback.
- It should not be enabled by default until original transfer and iPad USB are
  proven.

3A-2B did not produce evidence that the EOS 60D can deliver original images
through camera-initiated transfer. That remains the key compatibility risk for
the iPad adapter.

---

## 13. Recommended next phase

1. Reconnect and power the EOS 60D; verify `Canon Digital Camera` in `ioreg`.
2. Install an SD card with free space; do not delete existing images.
3. Run the capability-only harness and capture all feature/property/warning
   data.
4. Run `--transfer` once; inspect `isValid`, `canProvide(.original)`, predicted
   size, transfer result and generated data.
5. Validate exactly one JPEG and log EXIF/dimensions/file size.
6. Perform one safe settings write and restore, if a clearly non-destructive
   property is available.
7. Only after macOS original transfer passes, plan physical iPad USB testing.

Do not begin physical iPad integration based on macOS-only evidence.
