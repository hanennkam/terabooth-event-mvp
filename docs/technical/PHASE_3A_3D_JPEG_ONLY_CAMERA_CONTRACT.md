# Phase 3A-3D — JPEG-Only Camera Contract & Pipeline Audit

## Overall result

**PASS for source-level contract and automated verification.**

Physical camera capture remains **NOT TESTED**. Signing/deployment is still
blocked by the demo bundle identifier restriction, and no iPad/camera operation
was performed.

---

## 1. Actual architecture and data flow

```text
Canon EOS 60D
  -> CascableCore native adapter
  -> .original transfer only (no preview)
  -> JPEG bytes + capture ID
  -> CameraService.capture()
  -> CameraPipeline state machine/capture timeout
  -> ImageValidator
       magic bytes
       JPEG end-of-image
       dimensions (EXIF-aware)
       decode check
  -> ImageIngestor
       capture-ID duplicate check
       storage duplicate check
       SHA-256 of received bytes
  -> StorageService.saveOriginal
       atomic temp -> fsync -> rename
       length verification
  -> ImageIngestor reopens final file
       SHA-256 before == after
       decode/dimension verification
  -> CapturedImage (original path + SHA-256)
  -> BoothController review/approval
  -> BridgeClient.submit uses the exact original bytes
  -> Windows Bridge composes branded derived output separately
```

`MockCameraService` remains the default. The mock intentionally emits PNG under
`allowPng: true`; native camera ingestion always uses `allowPng: false`.

---

## 2. Gaps found and corrected

### JPEG end-of-image

The validator checked JPEG magic bytes, SOF dimensions and decodeability, but
did not require the JPEG EOI marker. A truncated payload could reach the codec
depending on the platform decoder. Added:

```text
last bytes must be 0xFF 0xD9
```

The native adapter now also requires JPEG SOI and EOI before completing its
`.original` transfer.

### Hash preservation

The ingestor verified file length and dimensions but did not compute a content
hash. Added:

- SHA-256 of received bytes before storage.
- SHA-256 of the reopened saved file.
- Explicit failure if hashes differ.
- SHA-256 persisted in session capture metadata and retained on restoration.

Accepted bytes are written exactly; no re-encode, resize, EXIF strip or colour
profile modification.

### Native contract

- `.original` is required; `.preview` is never requested.
- No RAW-to-JPEG conversion.
- Native returns the transfer bytes; Flutter validation is authoritative.
- Native width/height are 0 placeholder values; the validator computes the real
  dimensions. No UI trusts native dimensions.
- Shutter acknowledgement is not capture success; the pipeline completes only
  after ImageIngestor success.

---

## 3. Files changed

- `lib/services/camera_pipeline.dart`
  - JPEG EOI enforcement
  - SHA-256 before/after storage
  - stored-original hash error
- `lib/models.dart`
  - optional `CapturedImage.sha256`
  - preserve hash/orientation in `withPath`/`withCaptureId`
- `lib/booth_controller.dart`
  - persist capture SHA-256 in session metadata
- `lib/services/storage_service.dart`
  - restore capture SHA-256
- `ios/Runner/CascableCameraAdapter.swift`
  - SOI+EOI JPEG check
- `test/jpeg_only_contract_test.dart`
  - new contract tests

No Windows Bridge, API, printer, event/session/branding or production integration
was changed.

---

## 4. Tests added

`test/jpeg_only_contract_test.dart` (9 tests):

1. Valid original JPEG accepted.
2. Exact bytes and SHA-256 preserved.
3. CR2/RAW magic rejected.
4. PNG rejected for native camera.
5. JPEG-like/RAW/invalid content rejected.
6. Truncated JPEG without EOI rejected.
7. Empty payload rejected.
8. Undersized dimensions rejected.
9. Duplicate capture ID creates only one original.
10. Native adapter source uses `.original` only, never `.preview`.

Plus the native source assertion for no preview fallback.

Existing tests continue to cover:

- capture timeout without retry
- late transfer after timeout
- disconnect during pending capture
- duplicate image delivery
- capture-ID mismatch
- retake/Retake All
- atomic storage and original preservation
- branded composition output

---

## 5. Verification results

```text
Flutter analyze: No issues

Flutter test --concurrency=1:
137 tests passed

Python bridge tests:
55 passed

Demo simulator build:
BUILD SUCCEEDED
bundle: se.cascable.CascableCoreiOSDemo
demo licence present

Production simulator build:
BUILD SUCCEEDED
bundle: com.terabooth.teraboothIpad
production licence absent
```

No app was installed or launched. No camera/shutter/transfer was performed.

---

## 6. Hash preservation evidence

The contract test verifies:

```text
sha256(received bytes)
  == CapturedImage.sha256
  == sha256(reopened stored file)
```

File bytes are compared directly with the fixture bytes before the hash check.
No recompression or byte modification occurs.

Session metadata now includes `sha256` for each capture; restoration retains it.
The Windows Bridge receives the original bytes and hashes them independently for
its print-job payload; it does not receive or alter the iPad original.

---

## 7. Capture state correctness

- `shutterRequested` / `shutterSent` are not success states.
- Native `originalReceived` is not enough; CameraPipeline only completes after
  ImageIngestor validation.
- CR2/PNG/truncated/hash-mismatched data fail the capture.
- Timeout and late callbacks cannot complete a failed capture.
- No automatic shutter retry.
- Retake All remains the only retake workflow.
- Preview data is never a fallback.

---

## 8. Integration audit

Approved originals already flow through:

```text
BoothController.photos -> BridgeClient.submit -> 1/2/3/4-photo template job
```

The Bridge API accepts the original bytes, validates hashes, composes the branded
derived output and keeps originals separate. No bridge defect was found for
JPEG-only operation.

Remaining gaps are physical: signed iPad deployment, physical EOS 60D discovery/
connection, Live View, actual JPEG transfer, and DNP output.

---

## 9. Remaining blockers

1. Physical iPad signing/deployment is blocked by the unavailable
   `se.cascable.CascableCoreiOSDemo` bundle ID for the Personal Team.
2. No physical USB EOS 60D discovery/connection/Live View has occurred.
3. No physical original-JPEG transfer from the EOS 60D has been validated on
   iPadOS; previous Canon evidence was macOS-only and CR2/JPEG behavior differed.
4. DNP printer output remains unvalidated.
5. The safe demo probe is prepared but has not been installed or launched.

Do not describe physical iPad camera capture or DNP printing as verified.

**Stopped after source and automated verification.**
