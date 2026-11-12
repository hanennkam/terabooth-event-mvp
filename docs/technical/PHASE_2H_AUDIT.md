# Phase 2H — Operational Security & Reconciliation Audit

## 1. Current architecture

- iPad Flutter: event/template selection, capture/review/retake-all, crop metadata, bridge submission/polling, composition/GIF/QR, local originals and session metadata.
- FastAPI bridge: auth, idempotency, template renderer, GIF generator, mock/spooler/HF printer, HMAC guest delivery.
- SQLite: jobs, images, attempts, delivery tokens, GIF/printer state, template/crop metadata.

## 2. Completed

- Event/template/session lifecycle, ordered originals, Retake All only.
- Idempotent print submission/status/reprint; mock printer explicitly labelled.
- Template engine/crops/preview; canonical Pillow composition.
- Independent GIF generation and guest delivery.
- Guest HMAC tokens, originals/strip/GIF/QR.
- Local complete-review recovery from Phase 2G.
- GIF stale-claim recovery and print/GIF failure isolation.

## 3. Incomplete / risks audited

| Area | Finding |
|---|---|
| Uvicorn access logging | Raw `/d/<token>` paths were written to access logs. |
| FastAPI/app logs | No custom logging, but exception/trace text could include tokenized URLs or secrets. |
| Authorization headers | Not normally logged; no centralized guarantee. |
| Client logs | No production HTTP client logging; debug prints only in tests. |
| Submitted jobs | Only `approved` + `job_id` in session metadata; no status/GIF state, no startup reconciliation. |
| App restart offline | No submitted-job UI/offline state. |
| Manual refresh | No submitted-job refresh action. |
| Job identity safety | Must never POST a new job during reconciliation. |

## 4. Findings by severity

| ID | Severity | Finding | Action |
|---|---|---|---|
| H1 | **Critical** | Uvicorn access logs contained raw guest tokens. | Fixed with central redaction. |
| H2 | **High** | Exception/application-formatted logs could contain tokenized URLs or secrets. | Fixed with redacting formatter/filter. |
| H3 | **High** | Submitted job status/GIF/QR could not be restored after app termination. | Fixed with local `submitted_jobs/*.json` + GET-only reconciliation. |
| H4 | **High** | Offline/unknown submitted job had no safe operator state. | Fixed with offline banner, refresh, dismiss and Needs attention. |
| H5 | **Medium** | Reconciliation could accidentally resubmit if implemented as submit. | Explicitly excluded; tests assert POST count 0. |
| H6 | **Medium** | QR token may expire while app is closed. | Restored URL is shown only as server data; no validity claim; expired guest requests 404. |
| H7 | **Low** | No automatic submitted-job reconciliation if local metadata corrupt. | Corrupt records are ignored; originals remain untouched. |
| H8 | **Low** | No download analytics (unchanged). | Out of scope. |

## 5. Recommended fixes

Implemented in Phase 2H: H1–H6. Deferred: no physical validation, no analytics, no QR preflight.

## 6. Deferred hardware work

Windows/DNP, physical iPad/signing, Canon EOS R/CascableCore, physical guest phone/AP isolation, real Vision.
