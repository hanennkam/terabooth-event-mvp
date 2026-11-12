# Phase 2 — Software-Only End-to-End Integration

> **Software-only integration.** Hardware/camera/printer/signing validation remains deferred.
> **No physical iPad, Canon EOS R, DNP or Windows execution.**
> **Bridge remains the canonical 4×6 compositor; no print geometry or API contract was changed.**

---

## 1. Assessment before implementation

### Already present

- Mock camera 3-photo capture and countdown.
- Review screen (Retake All event workflow; individual retake software-only).
- Original storage, unique filenames, atomic writes, EXIF-aware validation.
- Bridge submission with `Idempotency-Key`.
- Print job status polling and success/failure/unknown states.
- QR URL display and QR code.
- Windows bridge composition, print adapters, QR delivery and HMAC tokens.
- 46 Flutter tests and 10 Python tests (at the start of this phase; Python count includes the Phase 1G MIME test).

### Missing or incomplete

| Gap | Resolution |
|---|---|
| No event create/select UI; fixed event only | Added local event catalog + picker |
| No final composition visible in iPad | Added bridge artefact retrieval and viewer |
| No copy/view action for delivery URL | Added SelectableText + copy button |
| Duplicate `approve()` could theoretically be invoked twice | Guarded to `phase == review` |
| Generic client errors/timeouts | Typed `BridgeException`, configurable timeouts |
| No software E2E tests for composition/status/copy | Added tests |
| QR expiry only server-side | Server tests retained; app displays/copies URL |

---

## 2. Composition architecture decision

The existing Windows bridge owns the **1200×1800, 300 dpi, 4×6** composition and the two **600×1800** panels. To preserve the existing API and avoid two divergent renderers:

1. iPad submits the **three originals + metadata** via the unchanged `POST /v1/print-jobs`.
2. Bridge composes the final 4×6 JPEG.
3. iPad retrieves it via `GET /v1/print-jobs/{id}/artefact`.
4. Print screen offers **View final composition**.

This satisfies the final-composition workflow without changing the print contract. The iPad does **not** upload a pre-composed sheet; doing so would require a new API contract and duplicate the canonical renderer.

---

## 3. Event create/select

- Added `EventProfile` and a persisted `event_catalog.json` (local app documents).
- Welcome screen offers **Change event**:
  - select an existing event;
  - create a new event title/date with a generated `evt_<timestamp>` ID.
- Selected event is first in the catalog and used for storage paths and bridge metadata.
- Event catalog writes are atomic; failure keeps the in-memory selection and is non-fatal.
- Events can only be changed at the welcome/idle screen.

---

## 4. Workflow implemented

1. Select/create event.
2. Start session.
3. Mock camera captures 3 photos (visibly distinct SIMULATED images).
4. Review all three.
5. Retake All for the event workflow; individual retake remains software-only; other successful photos remain.
6. Approve & Print.
7. Submit three originals + metadata (idempotency key).
8. Poll job state through bridge.
9. Retrieve bridge composition via `/artefact`.
10. Show success/failure/unknown, QR URL, composition viewer and copy-link action.

Controller-level individual retake remains for non-event regression tests, but the app UI and 14 November event scope are **Retake All only**.

---

## 5. Reliability behaviour

| Case | Behaviour |
|---|---|
| Bridge timeout | `SUBMIT_TIMEOUT`/`STATUS_TIMEOUT` etc.; no automatic retry |
| Connection failure | Typed `SUBMIT_FAILED`; app shows error state |
| Duplicate approve | `approve()` only runs from `review`; second call is a no-op |
| Duplicate submit | Deterministic idempotency key; bridge returns existing job |
| Job status sequence | Polling handles queued/printing/completed/failed/unknown |
| Unknown status | Terminal; no automatic resubmit |
| QR URL | Displayed, selectable and copyable; no URL validation call |
| QR expiry | Server returns 404; Python tests cover; app cannot know until guest opens it |
| App background | Camera pipeline fails active capture; no false success |
| Session restart | Originals remain; temp/orphan recovery exists; no active-session UI restoration |
| Composition 404 | No fatal error; preview remains unavailable; job/QR continue |

Print/QR idempotency and unknown-state safety remain unchanged.

---

## 6. Tests and exact results

```bash
cd /Users/Apple/Dev/terabooth-event-mvp/ipad_app
flutter analyze
flutter test
flutter build ios --simulator

cd ../windows_bridge
./.venv/bin/pytest -q
```

| Check | Result |
|---|---|
| `flutter analyze` | **No issues** |
| `flutter test` | **87 passed** |
| `pytest -q` | **39 passed** |
| `flutter build ios --simulator` | **Success** — 145 MB debug simulator app |
| Windows execution | **Not performed** |
| Physical hardware | **Not tested** |

New coverage includes:

- Bridge artefact retrieval and 404.
- Bridge timeout and connection failure.
- Bridge submit success/error.
- End-to-end mock workflow through composition + QR URL.
- Duplicate approval.
- Job status transitions.
- Unknown status without resubmission.
- Event catalog persistence/reload.
- Event selector UI.
- Print screen URL copy and composition action.
- Existing 3-photo, individual retake (software-only), Retake All, storage, EXIF, camera pipeline and bridge tests.

---

## 7. Files changed

**Flutter**

- `lib/models.dart` — `EventProfile`.
- `lib/services/storage_service.dart` — event catalog read/write.
- `lib/services/bridge_client.dart` — artefact fetch, typed `BridgeException`, configurable timeouts.
- `lib/booth_controller.dart` — event selection, composition retrieval, duplicate-approve guard, disposal guards.
- `lib/screens/welcome_screen.dart` — event selector/create dialog.
- `lib/screens/print_screen.dart` — composition viewer, copy URL, composition loading/error.
- `lib/main.dart` — event catalog load.

**Tests**

- `test/bridge_client_test.dart`
- `test/software_workflow_test.dart`
- `test/widget_test.dart`

**Docs**

- `docs/technical/PHASE_2_SOFTWARE_INTEGRATION.md`
- `docs/EVENT_DAY_RUNBOOK.md`
- `docs/PHYSICAL_VALIDATION_CHECKLIST.md`
- `docs/technical/PHASE_1F_PHYSICAL_VALIDATION.md`
- `docs/technical/HARDWARE_TEST_CHECKLIST.md`
- `README.md`
- `docs/IMPLEMENTATION_LOG.md`

No Windows Bridge production code, camera pipeline, print geometry or layout changed in Phase 2.

---

## 8. Known issues / incomplete

1. **No live Flutter ↔ Python bridge network test.** Flutter uses `MockClient`; Python uses TestClient. A macOS-local Uvicorn + simulator test is still recommended.
2. **No active-session restoration after app restart.** Storage/orphan recovery exists, but the review screen is not reconstructed. “Session recovery where supported” = files/temp/orphans, not a restored capture session.
3. **QR expiry is server-side.** App displays/copies the URL; it does not preflight the guest link. Expired/invalid links return 404 server-side.
4. **Composition is bridge-generated.** If the requirement literally means uploading a composed image from iPad, a new API contract would be required; not done.
5. **Composition preview may be unavailable** if `artefact` is not ready; print/QR still function.
6. **Event catalog persistence is best-effort**; a write failure does not block the session but may not survive restart.
7. **No GIF/Template Engine** (deferred).
8. **Individual retake is software-only.** Event docs use Retake All only.
9. **No hardware validation.**

---

## 9. Remaining hardware dependencies

- Apple signing/team and physical iPad install.
- CascableCore/EOS R integration and 10-session test.
- Windows bridge execution on the event PC.
- DNP 4×6/2×6 physical print.
- Guest QR on iPhone/Android with WAN off and AP-isolation checks.

---

## 10. Recommended next phase

1. Run a **live local integration**: start Uvicorn on the Mac, point a simulator build at its LAN/local URL, capture mock photos, submit, poll, view composition, open QR page from a phone on the same LAN.
2. Add active-session restoration only if desired; otherwise document restart behavior.
3. Proceed to physical Windows/DNP, signing, Cascable/EOS R and QR gates.
4. Defer Template Engine/GIF until after the event-critical gates.

No physical readiness is claimed.
