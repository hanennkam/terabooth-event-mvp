# Phase 2H — Operational Security & Submitted Job Reconciliation

> **Overall: PASS for software QA on macOS.** Physical hardware remains BLOCKED/unverified.

## 1. Audit findings fixed

- Raw guest-token paths in Uvicorn access logs.
- Potential token/secret exposure in formatted exception/application logs.
- No submitted-job status/GIF restoration after app termination.
- No safe offline/manual refresh state for submitted jobs.
- No explicit prohibition on reconciliation resubmission.
- No local persisted submitted-job identity beyond `job_id`.

## 2. Guest-token log redaction

Central strategy in `windows_bridge/app/log_redaction.py`:

- Redacts `/d/<token>` path segments to `/d/<redacted>`.
- Redacts `Authorization: Bearer …`.
- Redacts token query parameters.
- Redacts configured API token and delivery secret values.
- `RedactingFormatter` wraps existing Uvicorn/FastAPI/root handler formatters, so access lines, application messages and exception tracebacks are redacted.
- `RedactionFilter` is a second layer for handler messages.
- Normal method, path category, status and duration are preserved.
- Token format, HMAC validation and expiry semantics are unchanged.

Installed when `create_app()` starts.

### Live proof

A log-capturing Uvicorn run produced:

```text
/d/<redacted>/gif
```

and `GET /v1/print-jobs/<job_id>/gif` remained useful. Automated checks found:

- raw guest token: **absent**
- API token: **absent**
- delivery secret: **absent**
- `/d/<redacted>`: **present**
- normal health/print status logs: **present**

## 3. Submitted-job restoration

Local record `events/<event>/submitted_jobs/<job_id>.json` stores:

- event ID, session ID, bridge job ID
- submission timestamp
- last print state/completion
- last GIF state
- template ID/version
- delivery URL
- dismissed flag

Flow:

1. On startup, load latest non-dismissed submitted job for selected event.
2. Reconcile with authenticated `GET /v1/print-jobs/{id}` only.
3. Restore terminal print/GIF/composition/QR or begin status polling.
4. Persist updated state after every status update.
5. If Bridge is offline, keep the local record, show an offline banner with **Refresh status** and **Dismiss**; block new session.
6. Never POST, never resubmit, never create a new idempotency key.
7. Unknown remains **Needs attention**; mock remains **Mock print complete — no physical print**.
8. Next guest/dismiss marks the record dismissed without deleting originals.

Manual refresh is available on the welcome and print screens. Print/GIF status is not inferred from a local timestamp.

## 4. UI changes

- Offline submitted-job banner with Refresh status/Dismiss.
- Print screen **Refresh status** action.
- Mock print never shown as physical.
- Failed/unknown header **Needs attention**.
- GIF pending/ready/failed retained.
- Resume unsubmitted review remains distinct from submitted-job reconciliation.
- Start Session blocked while an unresolved submitted job exists.

## 5. Evidence of no resubmission

Automated Flutter tests use a MockClient with counters:

- reconciliation performs GETs only; POST count = **0**
- unknown status remains unknown; POST = **0**
- offline reconciliation retains local job and blocks new session
- completed/unknown/GIF states restore
- event isolation and multiple-job latest selection pass
- dismissal works.

## 6. Tests

| Check | Result |
|---|---|
| `flutter analyze` | **No issues** |
| `flutter test` | **87 passed** |
| `pytest -q` | **39 passed** |
| `flutter build ios --simulator` | **Success — 145 MB** |
| Live macOS FastAPI workflow | **PASS** |
| Windows runtime | **Not tested** |
| Physical hardware | **Not tested** |

## 7. Live evidence

- Bridge: `http://172.20.10.6:8796` macOS mock.
- Job: `job_9acedd5ff2cc4b2c8c065e51d1624df3`
- Print: completed/confirmed **mock**
- GIF: ready, GIF89a, 360×540, 3 frames, 1800 ms each, loop=0, **281,515 bytes**
- Authenticated/guest GIF: **200**
- Guest page: **Download animated GIF**
- UI live flow: **Mock print complete — no physical print**
- Logs: token/API secret/guest secret absent; `/d/<redacted>` present.

## 8. Remaining limitations

- No physical Windows/DNP/iPad/camera/phone validation.
- Real Apple Vision unavailable on simulator; physical iPad required.
- No QR token preflight; expired links remain 404.
- No automatic reconciliation of corrupt/missing submitted-job metadata; operator gets no restored job but originals remain.
- Reconciliation requires Bridge connectivity; offline records are retained indefinitely until refresh/dismiss.
- FastAPI startup recovery uses deprecated `on_event` (functional warning).
- No download analytics.

## 9. Physical validation checklist

- [ ] Windows 11, Python/venv, `.env`, Private firewall 8787.
- [ ] `/v1/health` from iPad.
- [ ] DNP driver/media/2-inch cut.
- [ ] 4×6 physical output and two 2×6 strips.
- [ ] 20 consecutive prints, duplicate/reprint/offline/unknown.
- [ ] Bridge restart with ready/pending GIF.
- [ ] Physical iPad install, submitted-job restart reconciliation, GIF playback.
- [ ] Real Vision face detection/fallback.
- [ ] Physical guest originals/strip/GIF download, token expiry.
- [ ] AP isolation and Windows firewall.
- [ ] CascableCore/EOS R gate.

**No hardware readiness is claimed.**
