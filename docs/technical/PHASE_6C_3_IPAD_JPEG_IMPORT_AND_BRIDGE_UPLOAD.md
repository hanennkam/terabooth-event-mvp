# Phase 6C-3 — Temporary JPEG Import & Physical iPad-to-Bridge Upload

## Overall result

**PASS — physical iPad JPEG import, authenticated upload, Bridge receipt,
original-hash preservation and derived-artefact retrieval.**

A synthetic JPEG was selected through the native iOS document picker on the
physical iPad, validated, submitted through the existing
`BoothController.approve() → BridgeClient.submit()` path, and rendered by the
actual Windows Bridge using `solo_4x6_v1`.

No camera, shutter, DNP/printer command or production event data was touched.

---

## 1. Temporary import tool

Added **Settings → Temporary test tools → Import Test JPEG**.

Properties:

- Clearly labelled **TEMPORARY TEST — NOT FOR EVENT USE**.
- Native iOS document picker.
- `.jpg`/`.jpeg` selection only.
- Validates JPEG signature, decodability, dimensions and size through the
  existing `ImageValidator`.
- Rejects PNG/HEIC/RAW and invalid bytes; no conversion.
- Uses a disposable temporary `BoothController`/storage, not customer events.
- Calls `prepareImportedTestReview()` and then the existing `approve()`.
- `approve()` calls the existing `BridgeClient.submit()`.
- No automatic submission: operator must explicitly tap **Submit one test job**.
- Blocks submission unless the Bridge reports **MockPrinter** mode.
- Does not start a camera session.

The imported JPEG is separate from `MockCameraService`; mock output was not
changed.

---

## 2. Exact API workflow used

```text
iOS Files document picker
  → JPEG bytes
  → ImageValidator (JPEG magic/EOI/dimensions/decode)
  → CapturedImage
  → BoothController.prepareImportedTestReview()
  → BoothController.approve()
  → BridgeClient.submit()
  → POST /v1/print-jobs
       Idempotency-Key
       terabooth.print/1 metadata
       template solo_4x6_v1 version 1
       image_0
  → Windows Bridge validates SHA-256, image, dimensions
  → exact original bytes stored
  → process_job renders derived 1200×1800 JPEG
  → GET /v1/print-jobs/{job}/artefact
```

No endpoint was invented and authentication was not bypassed.

---

## 3. Physical iPad result

Operator used AirDrop to place the synthetic test JPEG in Files, then selected it
through the app's document picker.

| Check | Result |
|---|---|
| Document picker opened | **PASS** |
| JPEG selected | **PASS** — `Terabooth_Test_JPEG.jpg` |
| Dimensions | **PASS** — 1200×1800 |
| SHA-256 displayed | **PASS** |
| Bridge URL | **PASS** — `http://192.168.8.192:8787` |
| Keychain token retained after update | **PASS** — authenticated job accepted |
| Job state | **PASS** — `completed` |
| Completion | **PASS** — `confirmed` |
| Printer mode | **PASS** — `mock` |
| Original hash from Bridge | **PASS — MATCHES** |
| Derived artefact retrieved | **PASS** — 1200×1800 JPEG displayed |
| Physical printer used | **NO** |

The Bridge accepted the exact original bytes; the displayed original hash
matched the local JPEG hash. The derived artefact was a valid 1200×1800 JPEG
rendered from `solo_4x6_v1`.

---

## 4. What is physically verified vs automated

### Physically verified on iPad

- Document-picker JPEG import and validation.
- Authenticated LAN upload to the actual Windows Bridge.
- Job acceptance/completion with MockPrinter.
- Original hash match reported by Bridge.
- Retrieval/display of derived 1200×1800 JPEG.

### Automated

- Flutter analyze and tests.
- Windows Bridge tests and solo template tests.
- Code signing/build validation.

### Not verified physically

- Real camera JPEG capture.
- Physical DNP print.
- Guest QR/GIF/ZIP retrieval from this test.
- Normal event catalog visibility of the disposable test session (it uses
  isolated temp storage by design).

---

## 5. Changes

- `pubspec.yaml` / `pubspec.lock`: added `file_picker: ^13.3.3`.
- `lib/screens/jpeg_import_test_screen.dart`: isolated import/submit/retrieve tool.
- `lib/screens/settings_screen.dart`: temporary-test card.
- `lib/booth_controller.dart`: `prepareImportedTestReview()` for the isolated
  review; `approve()` remains the submission path.
- `lib/models.dart`: `PrintJob.imageHashes` from the existing job JSON.
- `test/jpeg_import_test_state_test.dart`: isolated-review and hash parsing tests.
- Documentation/report.

No MockCameraService, MockPrinter, Cascable configuration, production Bundle ID,
signing identity or Windows Bridge code was changed.

---

## 6. Tests and build

```text
Flutter analyze: No issues
Flutter tests: 146 passed
Windows Bridge tests: 61 passed
```

Release build:

```text
BUILD SUCCEEDED
Bundle: com.terabooth.teraboothIpad
Team: P2LJT7F45Y
Profile: 0a12cb09-dbbd-4c11-856d-3b44a94b80c3
Expiry: 2026-11-19
Demo licence: absent
```

Installed over the existing app. The Keychain token and saved Bridge URL
survived the update.

### Build note

`file_picker` requires iOS 14. The project target is already 14.0, but Flutter's
generated plugin Swift package defaults to 13.0; the Release build used:

```text
IPHONEOS_DEPLOYMENT_TARGET=14.0
```

as a command-line override. Future builds of this tree need the same override
until the generated package minimum is aligned.

---

## 7. Remaining limitations

- The import tool is temporary and must not be presented as a booth workflow.
- It is visible under Settings and should be removed or gated before a live event.
- No real camera JPEG was tested.
- No physical DNP print was submitted.
- No guest QR/GIF/ZIP retrieval was tested from this job.
- The disposable test session is isolated from the event catalog.
- Build requires the iOS 14 deployment-target override noted above.
- No production data was deleted or altered.

---

## 8. Safety confirmation

| Check | Result |
|---|---|
| Camera discovery/Live View/shutter | **NONE** |
| Physical capture | **NONE** |
| Physical printer/DNP command | **NONE** |
| Bridge auth bypass | **NO** |
| Token printed/exposed | **NO** |
| MockCameraService changed | **NO** |
| MockPrinter default changed | **NO** |
| Production event data changed/deleted | **NO** |
| Cascable signing/licence changed | **NO** |
| Production Bundle ID changed | **NO** |

**Physical iPad import/upload/retrieval PASS. No physical print performed.**
