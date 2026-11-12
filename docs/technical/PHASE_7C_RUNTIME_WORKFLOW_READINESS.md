# Phase 7C — Runtime Workflow Readiness (No Hardware Dependency)

## Overall result

**PASS for software workflow readiness.**
**BLOCKED only at the Cascable production licence for physical camera testing.**

No physical camera, physical print, spooler or customer-data change occurred.

---

## 1. Audit result

Reused:
- Phase 7A/7B concurrency/licence findings
- Prior production app launch/UI evidence
- Prior physical synthetic JPEG upload/Bridge evidence
- Existing Bridge delivery/QR tests and MockPrinter tests
- Phase 6G/6I printer test evidence

No redundant full regression suite was run.

### Genuine defects found and fixed

1. **Mock camera status could read as a real camera**
   - Capture screen previously showed `Camera ready` for MockCamera.
   - Fixed to:
     - `Simulated camera ready`
     - `Preparing simulated camera`
     - `Simulated camera offline/error/recovering`
   - Real-camera labels remain unchanged for native mode.

2. **Temporary JPEG import bypassed ingestion/storage**
   - Imported JPEGs went directly into a temporary review/Bridge submission.
   - Fixed to run through the actual:
     ```text
     ImageValidator → ImageIngestor → StorageService
     ```
     before `prepareImportedTestReview()` and `BridgeClient.submit()`.
   - Uses isolated temporary storage/controller; no production event data.

---

## 2. Workflow verification

| Component | Result | Evidence |
|---|---|---|
| Event creation/selection | **PASS** | Existing event management tests |
| Session start/capture/review | **PASS** | Camera pipeline/UI tests |
| Mock camera status | **PASS** | Fixed labels; simulated and real states distinct |
| Mock camera connect/error states | **PASS** | Existing camera pipeline tests |
| JPEG signature/decode/dimensions | **PASS** | Existing JPEG contract tests |
| JPEG ingestion/storage | **PASS** | Import tool now uses ImageIngestor/StorageService |
| Bridge upload/auth | **PASS** | Prior physical synthetic upload; authenticated client |
| Bridge QR/guest delivery | **PASS software** | Existing guest delivery/QR tests |
| MockPrinter job/status | **PASS** | UI tests: mock completion never claims physical print |
| Print unknown/failure handling | **PASS** | Existing UI/recovery tests |
| Temporary import isolation | **PASS** | Settings-only, warning, temp controller/storage, no event workflow |
| Real EOS 60D | **BLOCKED** | No production-bundle Cascable licence |
| Physical 4×6 print | **BLOCKED** | No authorized hardware calibration |

---

## 3. Targeted tests

```text
flutter test test/ui_experience_test.dart test/jpeg_import_test_state_test.dart
11 passed

flutter analyze
No issues found
```

Reused evidence:
- 77 Bridge tests (Phase 6I full run)
- 74/77 prior Flutter/print evidence where applicable
- Physical synthetic upload/Bridge receipt from Phase 6C-3
- Production app launch/UI from Phase 6B-6

No full Flutter suite rerun was needed because changes are isolated to the
capture-screen labels and the temporary test tool.

---

## 4. Temporary tool isolation

`Settings → Temporary test tools → Import Test JPEG` is:

- clearly marked `TEMPORARY TEST — NOT FOR EVENT USE`;
- not reachable from Welcome/Capture/Review;
- uses a disposable controller/storage;
- never starts a camera;
- requires MockPrinter;
- does not write customer event data;
- is cleaned up on screen disposal.

It cannot enter the normal guest session flow without the operator explicitly
opening Settings and the test tool.

---

## 5. Remaining blocker

Physical camera validation still requires:

1. A CascableCore 18.0.2 evaluation/production licence for
   `com.terabooth.teraboothIpad`.
2. A local evaluation build with `USE_NATIVE_CAMERA=true` and licence applied in
   the production path.
3. One authorized EOS 60D USB/Live View/JPEG test.

Physical print remains separately blocked/unauthorized.

No code change can remove this vendor dependency.

---

## 6. Safety

| Check | Result |
|---|---|
| Physical camera/shutter | **NONE** |
| Physical print/spooler | **NONE** |
| USE_NATIVE_CAMERA enabled | **NO** |
| MockCamera default | **YES** |
| MockPrinter active | **YES** |
| Customer data changed/deleted | **NO** |
| Authentication/idempotency changed | **NO** |
| Licence/provisioning changed | **NO** |
| Secrets exposed | **NO** |

**Ready for the next licensed physical camera evaluation; no hardware action was
taken.**
