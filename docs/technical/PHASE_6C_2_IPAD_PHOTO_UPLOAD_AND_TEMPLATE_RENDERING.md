# Phase 6C-2 — iPad Photo Upload, Asset Retrieval & Template Rendering

## Overall result

**BLOCKED for the requested physical iPad JPEG upload.**

The existing production app has no supported way to produce or import a
synthetic JPEG while `USE_NATIVE_CAMERA=false`: its only photo source is
`MockCameraService`, which returns **PNG** bytes. No test-JPEG upload path exists
in the production UI, and changing that path or enabling the camera would violate
this phase's boundaries.

**Automated `solo_4x6_v1` template rendering: PASS.**  
**Physical iPad upload/retrieval: NOT TESTED.**  
**Windows Bridge physical receipt: NOT TESTED.**

No camera, printer, auth, signing or production-data change was made.

---

## 1. Existing API workflow

The supported path is the existing architecture:

```text
BoothController.approve()
  → BridgeClient.submit()
  → POST /v1/print-jobs (multipart)
       Idempotency-Key
       metadata (terabooth.print/1)
       image_0..image_n
  → Windows Bridge validates:
       template/version/crop/copy count
       SHA-256 of each uploaded image
       Pillow image validity
       minimum dimensions
       writes exact bytes to job input
  → process_job renders template
  → GET /v1/print-jobs/{job_id}
  → GET /v1/print-jobs/{job_id}/artefact
  → delivery/GIF endpoints
```

For `solo_4x6_v1`:

- version `1`
- one image slot
- 1200×1800 output
- 300 dpi
- exact uploaded bytes are hashed and written without re-encoding
- renderer creates a separate derived JPEG.

No endpoint was invented or bypassed.

---

## 2. Why physical JPEG upload is blocked

| Evidence | Consequence |
|---|---|
| `USE_NATIVE_CAMERA=false` | Native Cascable camera path is disabled |
| Production camera is `MockCameraService` | Only app camera source |
| `MockCameraService.capture()` uses `ui.ImageByteFormat.png` | Mock captures are PNG, not JPEG |
| No photo-library/file import in production capture flow | No synthetic JPEG can enter `BridgeClient.submit` through the app |
| Camera/native capture prohibited in this phase | Cannot switch to real JPEG source |
| No token available to an external uploader | Cannot safely test API-only without operator secret exposure |

The app cannot satisfy "synthetic JPEG only" through its actual UI without a
product change or enabling the physical camera. A PNG upload would not prove the
required JPEG preservation contract, so it was not performed.

---

## 3. Automated template rendering

Existing template tests were run:

```text
pytest tests/test_phase4b_branding.py
3 passed
```

The `solo_4x6_v1` specification:

```text
id: solo_4x6_v1
version: 1
slots: 1
canvas: 1200×1800
output: 1200×1800
dpi: 300
```

The existing test suite asserts the rendered artefact is a valid
**1200×1800 JPEG** for the one-photo template. This is an automated renderer
test, **not** a physical iPad upload/retrieval test.

The Bridge writes the received image bytes directly to the job input and the
renderer creates a separate derived JPEG, so the original upload is not replaced
by the branded render.

---

## 4. Physical iPad status

The current app was not used for an upload because no JPEG can be supplied
through the supported UI.

| Check | Status |
|---|---|
| Authenticated Bridge health | **PASS from Phase 6C** (operator-confirmed) |
| Physical test event/session created | **NO** |
| Physical JPEG upload | **NOT TESTED** |
| Windows receipt of test JPEG | **NOT TESTED** |
| Original hash/receipt verification | **NOT TESTED** |
| iPad asset retrieval | **NOT TESTED** |
| Guest QR/GIF/ZIP retrieval | **NOT TESTED** |
| Physical UI event/session visibility | **NOT TESTED** |

No production event/session or customer data was changed.

---

## 5. Tests / build

```text
Flutter analyze: No issues
Flutter tests: 144 passed (last full run; no source changes this phase)
Windows Bridge tests: 61 passed
solo_4x6_v1 rendering tests: 3 passed
```

No new Release build or installation was needed because no app source changed in
this phase. The installed app remains the Phase 6C build with the Keychain token.

---

## 6. Exact blocker and safe next choices

### Option A — add a test-only synthetic JPEG import/self-test (requires approval)

Add an explicit operator-only test path that uses a bundled synthetic JPEG and
the existing `BridgeClient.submit` contract with `solo_4x6_v1`. This would be a
product change and must not alter Mock defaults or production data.

### Option B — authorize a native camera capture test

Enable the native path only for an explicitly authorized test and capture one
real JPEG. This is outside the current phase boundaries.

### Option C — API-only synthetic JPEG test

Run the existing Bridge contract with a synthetic JPEG from a machine that has the
Bridge token, without involving the iPad. This can verify Windows rendering and
hash preservation but **cannot** prove physical iPad upload.

Do not change `MockCameraService` to emit JPEG, enable native camera silently, or
upload PNG while calling it a JPEG test.

---

## 7. Safety confirmation

| Check | Result |
|---|---|
| Camera discovery/Live View/shutter | **NONE** |
| Physical capture | **NONE** |
| Printer/DNP command | **NONE** |
| Bridge auth weakened | **NO** |
| Token requested/exposed | **NO** |
| Production data reset/deleted | **NO** |
| Existing test events/data | **Untouched** |
| MockCameraService default | **YES** |
| MockPrinter default | **YES** |
| USE_NATIVE_CAMERA | **false** |
| Source/project changes this phase | **NONE** |

**Stopped at the supported-input blocker. No physical upload result was
fabricated.**
