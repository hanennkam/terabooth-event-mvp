# Phase 2G — Final Software QA

> **Overall: PASS for software/simulator QA. Physical hardware remains unverified.**

## 1. Result summary

- Full workflow passes on macOS + iPad A16 Simulator + local FastAPI mock bridge.
- GIF recovery, session recovery, security and UI wording issues found in audit were fixed.
- Existing Retake All-only, print geometry, HMAC, idempotency and no-auto-resubmit behavior preserved.
- No Windows, DNP, camera, signing or physical-phone claims.

## 2. Fixes implemented

### GIF recovery

- Startup recovery scans `pending`, `processing` and `ready` jobs.
- A valid existing GIF is promoted to `ready` and never overwritten.
- Stale `processing` claims are atomically released and retried.
- Attempts are capped (`gif_attempts < 3`); exhausted jobs become `failed` with diagnostic.
- Jobs with missing/invalid artefacts or wrong image count fail safely.
- Abandoned `.guest.gif.*.part` files are removed only inside job directories.
- Ready GIF bytes and metadata persist across restart.
- Recovery never changes print state.

### Session recovery

- Complete, unsubmitted sessions are discoverable from local `session.json` + original files.
- Welcome screen offers explicit **Resume**; nothing auto-restores.
- Approved sessions (`approved: true`) are excluded.
- Restoration preserves template, version, crops and original bytes.
- Incomplete sessions are ignored.
- No automatic print resubmission.

### UI and security

- Mock printer completion is unmistakably “Mock print complete — no physical print.”
- Failed/unknown print states show “Needs attention,” not “Complete.”
- Job printer mode comes from the bridge, not the camera simulation flag.
- Guest token DB expiry enforced alongside HMAC.
- API token comparison is constant-time.
- Post-submission metadata failure no longer hides an accepted job.

### Guest/GIF states

- Pending: 409 endpoints; guest page says GIF is being prepared; photos/strip remain.
- Failed: 404 endpoints; guest page says GIF unavailable; photos/strip remain.
- Ready: GIF89a, 3 frames, 360×540, 1800 ms, loop=0.
- Temp GIF files have restricted permission attempt; originals untouched.

## 3. Validation evidence

### Live workflow

| Field | Value |
|---|---|
| Bridge | macOS FastAPI mock, LAN `192.168.8.185:8795` |
| Job | `job_638f196bc01a44b99b6c5b2e1a06c0e0` |
| Print | `completed` / `confirmed` (mock) |
| UI | **Mock print complete — no physical print** |
| GIF | `ready`, 3 frames, 360×540, 1800 ms, loop=0, GIF89a, **281,515 bytes** |
| Authenticated GIF | 200 |
| Guest GIF | 200 |
| Guest page | contains **Download animated GIF** |
| Live simulator test | **PASS** |

Print state, composition, QR and GIF all completed; the mock printer was never presented as physical.

### Tests

| Check | Result |
|---|---|
| `flutter analyze` | **No issues** |
| `flutter test` | **81 passed** |
| `pytest -q` | **35 passed** |
| `flutter build ios --simulator` | **Success — 145 MB** |
| Live MacBook FastAPI workflow | **PASS** |
| Real Apple Vision | **Skipped — simulator inference unavailable** |
| Windows runtime | **Not tested** |

Recovery tests cover stale processing, valid-ready preservation without overwrite, missing artefact regeneration, wrong image count, attempt exhaustion, abandoned temp cleanup and duplicate claims. Session recovery tests cover complete/unsubmitted restore and approved exclusion.

## 4. Known limitations

- Physical hardware is unavailable.
- Windows runtime and DNP validation not performed.
- Real Vision only mocked; simulator returns `Could not create inference context`.
- No automatic print-job recovery after app termination; operator intervention required.
- No auto-restore of approved sessions.
- Uvicorn access logs may contain guest token URLs.
- FastAPI startup event deprecation warning remains.
- No download analytics.
- Identical GIF source frames are rejected rather than published.
- No physical guest phone download test.

## 5. Outstanding hardware checklist

- [ ] Windows 11 PC, Private network, firewall TCP 8787.
- [ ] Python/venv/dependencies on Windows.
- [ ] `/v1/health` from iPad LAN.
- [ ] DNP DS-RX1HS driver, 4×6 media, 2-inch cut.
- [ ] Physical 4×6 / two 2×6 strips, orientation, borders, colour.
- [ ] 20 consecutive print jobs and offline/error behavior.
- [ ] Bridge restart with ready/pending GIF.
- [ ] Physical iPad signing/install and animated GIF playback.
- [ ] Real Apple Vision face detection and safe fallback.
- [ ] Physical iPhone/Android originals/strip/GIF download.
- [ ] AP isolation and Windows firewall checks.
- [ ] CascableCore/EOS R capture validation (separate gate).

## 6. Next step

Run the physical Windows/DNP and iPad/device validation checklist. Do not claim physical readiness until those gates pass.
