# Phase 3A-2D — Canon EOS 60D Original JPEG Transfer

**Date:** 2026-11-12  
**Overall result:** **BLOCKED — the EOS 60D was not enumerated on USB at the time of the single-shutter test.**

The transfer harness is implemented and builds, but the required precondition
(camera discovered, USB transport, storage available) was not met. **No shutter
was triggered. No transfer request was received. No JPEG was created or
validated. No settings were changed.**

---

## 1. Preflight evidence

### USB

At test time, `ioreg` contained no `Canon Digital Camera` entry. A direct
`ioreg -p IOUSB -l -w 0 | grep -A3 'Canon Digital Camera'` returned nothing.

`system_profiler SPUSBDataType` also returned no usable USB listing in this
environment.

This is different from the 3A-2C preflight, where the camera was present at
`locationID 34668544` with:

```text
idVendor  = 1193
idProduct = 12821
USB Product Name = Canon Digital Camera
USB Vendor Name  = Canon Inc.
```

### Competing applications

Cascable Studio was fully closed. No EOS Utility, Image Capture application, or
Photos application was open. Remaining system processes (`icdd`, Photos widget
extensions) are not user camera-owning applications.

### Storage

`/Volumes` contained only `Macintosh HD`. No SD volume was mounted by macOS.
CascableCore storage could not be queried because no camera was connected.

The prior 3A-2C run did report one camera storage device and 724 shots when the
camera was present and Studio was closed. Those are historical capability
results, not current 3A-2D transfer results.

---

## 2. Discovery / connection logs

No camera discovery ran because the camera was absent. The harness would have
logged:

```text
CASCABLE_MAC_DISCOVERY=started mode=usbOnly
CASCABLE_MAC_DISCOVERED vendor=Canon Inc. model=Canon EOS 60D transport=1
CASCABLE_MAC_CONNECT=connected ...
```

None of those events occurred in this phase.

No transfer handler would be meaningful without a connection, and no shutter
was issued.

---

## 3. Harness audit and changes

The existing macOS harness was inspected:

- Licence verified (`CASCABLE_MAC_LICENSE_RESULT=0` in prior/current runs).
- `CameraDiscovery` USB-only discovery.
- Connection and warning logging.
- Capability/property/storage logging.
- Live View start/frame/stop.
- Camera-initiated transfer handler.
- Disconnect/reconnect.

The harness was hardened before the attempted transfer:

- Original JPEG saved under a **unique** `/tmp/terabooth-eos60d-original-<UUID>/`
  directory, mode 0700, file mode 0600; never overwrites an existing file.
- Added a full-resolution guard: long edge ≥3000 and short edge ≥2000 before
  accepting the result as a complete original rather than a thumbnail.
- No preview or thumbnail substitution.
- No filesystem fallback.
- No automatic retry.
- One shutter maximum.

Build:

```text
** BUILD SUCCEEDED **
```

No camera was available to exercise these paths.

---

## 4. First capture — NOT RUN

| Step | Result |
|---|---|
| One shutter request | **NOT RUN** |
| Shutter request result | **NOT TESTED** |
| Camera-initiated transfer callback | **NOT RECEIVED** |
| `isValid` | **NOT TESTED** |
| `availableRepresentations` | **NOT TESTED** |
| `canProvide(.original)` | **NOT TESTED** |
| `canProvide(.preview)` | **NOT TESTED** |
| Predicted original size | **NOT TESTED** |
| `isOnlyDestinationForImage` | **NOT TESTED** |
| `executeTransfer(for: .original)` | **IMPLEMENTED, NOT TESTED** |
| `generateData(for: .original)` | **IMPLEMENTED, NOT TESTED** |

No second shutter was issued or scheduled.

---

## 5. `.original` availability

**Unknown for this run.** The camera was not connected, so no
`CameraInitiatedTransferRequest` existed to inspect.

No claim is made that the EOS 60D can or cannot provide `.original` through
camera-initiated transfer. The prior 3A-2C capability mask did include
`cameraInitiatedTransfer`, but that does not prove the original representation
is available.

---

## 6. Transfer execution result

No transfer was executed. No success or SDK error was produced.

---

## 7. JPEG validation — BLOCKED

No bytes were received. Therefore none of the following is validated:

- byte count
- JPEG signature
- decode
- pixel dimensions
- EXIF
- file size
- full-original vs thumbnail
- camera-side file comparison

No image was saved.

---

## 8. Exact byte comparison — NOT POSSIBLE

No original image was received and no camera storage was accessible. Exact
comparison with the corresponding SD-card file is therefore not performed.

This is a limitation of the blocked run, not evidence of a transfer failure.

---

## 9. Capture lifecycle / safety

| Requirement | Result |
|---|---|
| One shutter request only | **No shutter sent** |
| No automatic retry | **Satisfied by harness** |
| No preview substitution | **Satisfied by harness** |
| No filesystem fallback | **Satisfied by harness** |
| No duplicate completion | **Guarded; not exercised** |
| Timeout behavior | **Implemented; not exercised** |
| No success before original bytes | **Satisfied by harness** |
| Disconnect during transfer | **Not run** |
| Settings write | **Not performed** |

No camera files were opened, modified or deleted.

---

## 10. Limitations

- Camera was not USB-enumerated at test time.
- No camera storage was available for inspection.
- No original-transfer request occurred.
- No original JPEG, EXIF or dimension validation occurred.
- No exact camera-file comparison occurred.
- Prior 3A-2C capability/storage evidence is historical and not a substitute
  for this transfer test.

---

## 11. Implications for the iOS adapter

The iOS adapter remains conservative:

- It requires camera-offered `.original` bytes.
- It does not substitute preview data.
- It does not report shutter request as success.
- It has no filesystem fallback.
- It remains disabled by default.

3A-2D produced **no new evidence** about EOS 60D original-transfer behavior.
The key compatibility risk is unchanged.

---

## 12. Final validation

| Check | Result |
|---|---|
| macOS harness build | **BUILD SUCCEEDED** |
| Mac licence | **PASS in prior/current harness runs** |
| Camera discovery this phase | **BLOCKED — not enumerated** |
| Shutter / transfer | **NOT RUN** |
| JPEG validation | **BLOCKED** |
| Settings write | **NOT PERFORMED** |
| iOS production build | **PASS — 175 MB** |
| Production Bundle ID | **`com.terabooth.teraboothIpad`** |
| Production licence | **ABSENT** |
| Flutter tests | **96 passed** |
| Python tests | **39 passed** |
| CameraPipeline/ImageIngestor/MockCameraService changed | **NO** |
| Printing/GIF/QR/Windows Bridge changed | **NO** |

No licence material was exposed. No camera files were modified.

---

## 13. Recommended next action

1. Power the EOS 60D on and wake it.
2. Charge/AC the camera (last observed battery was 2/4).
3. Use a direct, data-capable USB cable and direct Mac port (no hub).
4. Close Cascable Studio and all camera-owning apps.
5. Confirm:

```bash
ioreg -p IOUSB -l -w 0 | grep -A2 'Canon Digital Camera'
```

6. Run the capability-only harness and confirm:
   - EOS 60D discovered
   - USB transport
   - 78 known properties (or document changed count)
   - one storage device
   - non-nil shots available
7. Only then run one `--transfer` test.
8. If `.original` is unavailable, stop and report; do not substitute preview.
9. If it succeeds, validate JPEG/EXIF/dimensions and preserve the file.

Do not run a second shutter automatically. Do not proceed to iPad integration
until an original transfer is actually demonstrated.
