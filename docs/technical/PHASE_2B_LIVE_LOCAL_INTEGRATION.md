# Phase 2B — Live Local Network Integration Test

> **Result:** PASS for the real macOS-hosted FastAPI bridge, mock printer and iPad A16 Simulator.
> **Not Windows/printer/hardware validation.** No physical iPad, iPhone, Canon EOS R or DNP was used.
> **No production credentials are included in this document.**

---

## 1. Scope and event policy

- Actual HTTP workflow: iPad A16 Simulator → MacBook LAN → FastAPI → mock printer.
- Event retake policy remains **Retake All only**. Individual retake is a software-only, non-event feature.
- No camera topology, CascableCore, print geometry, template engine or GIF changes.

---

## 2. Environment and real network endpoints

| Item | Value |
|---|---|
| Mac LAN IP | **192.168.8.105** (`en0`) |
| Temporary bridge port | **8790** |
| Bridge base URL | `http://192.168.8.105:8790` |
| Printer mode | `mock` |
| iPad device | iPad (A16) Simulator `552D64BA-85B9-4DFE-B3EA-10E24FDDCC34` |
| Guest device | iPhone 17 **Simulator** `19191B2F-287D-4C22-823F-1BE1D4D234C0` |
| Physical iPhone | **Not detected** |

The existing `python3.1` process on `127.0.0.1:8787` was unrelated and was not stopped or modified.

---

## 3. Temporary server setup

Temporary credentials and data were created under a `/tmp/terabooth-live.*` directory with `chmod 600`; they were never written into the repository.

Actual startup shape:

```bash
cd /Users/Apple/Dev/terabooth-event-mvp/windows_bridge

# Temporary env file supplied API token, delivery secret, mock printer,
# temporary data directory and public base URL.
set -a
. "$ENVFILE"
set +a

./.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8790
```

Equivalent non-secret configuration:

```dotenv
TERABOOTH_PRINTER=mock
TERABOOTH_DATA_DIR=<temporary>/data
TERABOOTH_API_TOKEN=<temporary-token>
TERABOOTH_DELIVERY_SECRET=<temporary-secret>
TERABOOTH_PUBLIC_BASE_URL=http://192.168.8.105:8790
TERABOOTH_TOKEN_TTL_HOURS=2
TERABOOTH_JOB_TIMEOUT_SECONDS=60
```

The server was bound to `0.0.0.0`; health was reachable at both the LAN IP and loopback.

---

## 4. Real HTTP workflow

### Flutter simulator command

```bash
cd /Users/Apple/Dev/terabooth-event-mvp/ipad_app
flutter test integration_test/live_bridge_test.dart \
  -d 552D64BA-85B9-4DFE-B3EA-10E24FDDCC34 \
  --dart-define=TERABOOTH_BRIDGE_URL=http://192.168.8.105:8790 \
  --dart-define=TERABOOTH_API_TOKEN=<temporary-token>
```

The integration test used the real UI:

1. Created an event.
2. Started a session.
3. Captured 3 mock photos.
4. Reached review.
5. Approved.
6. Submitted to FastAPI over HTTP.
7. Polled the real job.
8. Waited for `/artefact`.
9. Confirmed the composition action and QR URL were displayed.

**Result:** `All tests passed` (15 seconds after build).

Post-cleanup verification: `flutter analyze` clean, `flutter test` **58 passed**, `pytest -q` **10 passed**, default simulator build **144 MB**.

### Actual requests observed server-side

| Request | Result |
|---|---|
| `GET /v1/health` with valid token | 200 |
| `GET /v1/health` missing/invalid token | 401 |
| `POST /v1/print-jobs` | 202 |
| `GET /v1/print-jobs/{id}` | 200 |
| `GET /v1/print-jobs/{id}/artefact` | 200 |
| `GET /d/{token}` guest page | 200 |
| 3 × `GET /d/{token}/original/{id}` | 200 each |
| `GET /d/{token}/strip` | 200 |
| `GET /d/{token}/qr.png` | 200 |

### Test job

| Field | Value |
|---|---|
| Job ID | `job_971d4ba7a4cb497cbf90eb77025aade4` |
| State | `completed` |
| Completion | `confirmed` (mock printer) |
| Attempts | 1 |
| Event | `evt_1794249838412` |
| Event title/date | Live Integration Event / 10 Nov 2026 |
| Originals | 3 |
| Composition | 1200×1800 JPEG, 300×300 dpi, 255,866 bytes |

A final clean rerun also passed and produced another completed job (`job_4099e6ba3ca24f79809e8c1f10e582af`).

---

## 5. Composition and file validation

| File | Result |
|---|---|
| Final composition | JPEG, **1200×1800**, **300 dpi**, 255,866 bytes |
| Original 1 | PNG, 1200×1800, 672,717 bytes |
| Original 2 | PNG, 1200×1800, 710,266 bytes |
| Original 3 | PNG, 1200×1800, 637,183 bytes |
| QR PNG | PNG, 552×552, 4,468 bytes |

**Important:** mock-camera originals are PNG. Native camera captures are expected to be JPEG; the bridge served the actual PNG MIME correctly. Do not report mock originals as JPEGs.

The downloaded strip opens correctly and is the expected 4×6 / 2×6 composition; the three originals open correctly.

---

## 6. Guest delivery page and iPhone test

- Generated QR URL used `http://192.168.8.105:8790/d/<token>`.
- Guest page returned 200 HTML.
- Page showed **Photo 1/2/3** and **Download your photostrip**.
- All three original URLs, strip URL and QR PNG returned 200.
- Invalid guest token returned **404**.
- A genuinely expired HMAC guest token returned **404**.
- iPhone 17 **Simulator** Safari loaded the guest page and displayed the download prompt for an original.

**Limitation:** no physical iPhone was connected. Simulator tap/download automation was not available; byte integrity of all files was validated via real HTTP downloads from macOS. The simulator was not claimed as a physical-device test.

---

## 7. Reliability results

| Test | Result |
|---|---|
| Invalid API token | **401** |
| Missing API token | **401** |
| Duplicate idempotency key | **200**, same job ID, `duplicate: true` |
| Duplicate approval in app | Blocked by review-phase guard (automated test) |
| Missing artefact file | **404 `artefact not ready`** |
| Invalid guest token | **404** |
| Expired guest token | **404** (HMAC expiry) |
| Unknown job status | Automated tests confirm terminal handling and no resubmission |
| Bridge restart | Job persisted; health 200 and job 200 after restart |
| In-flight job restart | Not tested live; code does not resume background print tasks |
| QR page | 200 |
| QR code | 200 PNG |

### Observation: delivery DB expiry

`require_delivery` validates the HMAC token expiry and the DB token binding, but does not itself compare `delivery_tokens.expires_at`. A manual DB-only expiry edit therefore did not expire the link; a genuinely expired HMAC token did. Server-issued tokens have matching HMAC/DB expiry, so normal behaviour is correct. This is documented as an observation, not changed in this phase.

---

## 8. Failures and root causes

1. **First integration attempt timed out at composition.**
   - Root cause: the test entered the event title into the welcome screen’s bridge-URL field because both were `TextField`s. The app then correctly rejected `Live Integration Event/v1/print-jobs`.
   - Fix: scoped event text entry to the event dialog. No app defect.
2. **API token build define was not applied.**
   - Root cause: `main.dart` created `BridgeClient` without reading `TERABOOTH_API_TOKEN`.
   - Fix: pass `TERABOOTH_BRIDGE_URL` and `TERABOOTH_API_TOKEN` build defines into the initial bridge client. No secret committed.
3. **Initial “expired token” setup returned 200.**
   - Root cause: DB `expires_at` alone is not the enforcement path; the HMAC payload expiry is.
   - Re-test with a genuinely expired HMAC token returned 404. Documented above.
4. **First iPhone screenshot showed Safari Start Page.**
   - Root cause: page was still loading after first launch.
   - After waiting/reopening, the guest page loaded; server log confirmed the request.

---

## 9. Cleanup

Completed after testing:

- Stopped the temporary Uvicorn process on port 8790.
- Removed the temporary data directory, env file and downloaded test files.
- Uninstalled the integration-test iPad app to remove the compiled temporary bridge settings/token.
- Rebuilt and reinstalled the default simulator app with normal source configuration (no temporary URL/token).
- Erased/shut down the iPhone 17 Simulator so the delivery token is not retained in Safari.
- Confirmed the unrelated port 8787 process was untouched.
- Scanned the repository for the temporary token/secret: **not present**.
- No temporary credentials were added to tracked source.

---

## 10. Remaining blockers

| Blocker | Status |
|---|---|
| Windows event PC | **Unavailable until tomorrow** |
| DNP DS-RX1HS | **No physical print validation** |
| Physical iPad/signing | **Unavailable** |
| Canon EOS R/CascableCore | **Unavailable; not integrated** |
| Physical iPhone/guest device | **Not available; simulator only** |
| Windows firewall/AP isolation | **Unverified** |
| macOS simulator ↔ bridge | **PASS** |

**No Windows, printer, camera, signing or physical-device readiness is claimed.**
