# Phase 1G — Windows Bridge & Event Integration Final Audit

> **Audit-first phase.** No camera integration, print geometry, template engine or GIF implementation changed.
> **No Windows execution or physical DNP test.** No physical hardware claims.
> **One low-risk fix applied:** original-image QR delivery now serves the actual JPEG/PNG MIME type.

---

## 1. Executive verdict

| Area | Verdict |
|---|---|
| iPad ↔ Windows API (JPEG event path) | **PASS with observations** |
| Print pipeline geometry | **PASS (code/tests); physical unverified** |
| QR token/page/download | **PASS (mock HTTP); physical/network unverified** |
| Windows scripts | **PASS by static review; not executed on Windows** |
| PNG/mock original MIME | **FIXED** |
| DNP spooler/HFP | **UNVERIFIED** |
| Cross-platform tests | **Flutter 46 / Python 10 / simulator build success** |
| Event readiness | **NOT physically verified** |

No camera topology, print dimensions, template layout or camera source was changed.

---

## 2. API contract audit

### Endpoints used by the iPad

| Client call | Server endpoint | Match |
|---|---|---|
| `submit()` multipart + metadata | `POST /v1/print-jobs` | Yes |
| `getJob()` | `GET /v1/print-jobs/{id}` | Yes |
| `reprint()` | `POST /v1/print-jobs/{id}/reprint` | Yes |
| `health()` | `GET /v1/health` | Yes |
| QR URL from response | `GET /d/{token}` | Yes |

### Headers and authentication

- Client sends `Authorization: Bearer <token>` only when a token is configured.
- Server enforces the same header when `TERABOOTH_API_TOKEN` is set; otherwise auth is open on the LAN.
- Client sends `Idempotency-Key` on submit (deterministic from session + image SHA-256 + template/copies).
- Server requires the header, returns the existing job for a duplicate key.
- Reprint sends a new random idempotency key per call; a deliberate second reprint is a second physical print.
- No automatic retry of submit/reprint exists in the iPad client. This is correct for print safety; idempotency covers accidental duplicate HTTP submits.

### Response model

`PrintJob.fromJson` consumes `job_id`, `state`, `completion`, `attempts`, `delivery_url`, `error`, `reprint_of`; the server returns all of them. Additional server fields are ignored by the client. Match.

### Observations / mismatches

| # | Observation | Impact | Action |
|---|---|---|---|
| A1 | Client sends `session_id`, but the server creates a **new server session** (`db.create_session`) and returns that ID. The iPad’s local session ID is not preserved in the bridge. | Traceability only; print/QR function | **Not changed.** Recommend aligning in a later phase or documenting bridge-created sessions. |
| A2 | Client sends EXIF-effective `width`/`height`; server validates raw Pillow dimensions only (minimum 600) and does not compare declared dimensions. | Normal EOS R JPEGs pass; metadata semantics differ for rotated images | **Not changed.** Print composition applies EXIF correctly. |
| A3 | Client declares `delivery.ttl_hours: 24`; server ignores that field and uses `TERABOOTH_TOKEN_TTL_HOURS` (default 24). | Matches by default; custom TTLs are server-controlled | **Not changed.** Documented. |
| A4 | Server’s input validation accepts any Pillow-decodable image (PNG/GIF included), not explicitly JPEG-only. | Native event path sends JPEG; mock uses PNG | **Not changed**; input remains permissive. |
| A5 | Original QR endpoint previously served all images as `image/jpeg`, even PNG/mock originals. | Wrong MIME for mock/PNG; browsers may fail | **FIXED** — actual JPEG/PNG MIME and filename suffix; regression test added. |
| A6 | Reprint path writes a file using one generated ID but stores a different `image_id` in the DB. | Path/ID naming inconsistency only; delivery uses the stored path | **Not changed**; low risk. |
| A7 | Reprint uses a random idempotency key per client call. Two separate taps can create two jobs. | Duplicate physical print if operator double-taps | No auto retry; UI changes phase on first call. Document; verify operator flow. |
| A8 | Server requires exactly 3 images and template `strip_2x6_3up_v1`; client sends exactly that. | Match | None |

### Timeouts/polling

- Client submit timeout: 30 s.
- Status poll timeout: 5 s per request; up to 60 polls at 1 s.
- Reprint timeout: 10 s.
- Server job timeout: 60 s default.
- Poll errors are retained in the UI but the loop continues; after 60 iterations the app shows terminal-ish UI with the last state.
- `202`/duplicate `200` is accepted; physical print completion is a separate state.

### Live mock audit (no hardware)

- `POST /v1/print-jobs` → `202`; job reached `completed/confirmed` with mock printer.
- QR URL used configured public base (`http://<LAN_IP>:8787/d/<token>`).
- Page `200 text/html`; strip `200 image/jpeg` with attachment filename; QR `200 image/png`.
- Original JPEG `200 image/jpeg` attachment.
- Bad token `404`; duplicate submit `200` with existing job.
- **Now fixed:** PNG original returns `image/png` and `.png` filename; test passes.

---

## 3. Print pipeline audit

| Item | Finding |
|---|---|
| Canvas | 1200×1800 at 300 dpi = 4×6 in |
| Strips | Two identical 600×1800 panels = 2×6 each |
| Photos | 3 slots per strip; fixed template |
| Fit | Pillow `ImageOps.fit` cover crop, center |
| Orientation | `ImageOps.exif_transpose` before crop |
| Output | JPEG quality 95, 300 dpi |
| Spooler | PowerShell `System.Drawing.Printing`; 4×6 paper, zero margins |
| HFP | Copy to configured 4×6 folder, watch archive |
| Status | Spooler submission returns `unknown` for physical completion |
| Duplicate | API idempotency key prevents duplicate job creation |
| Reprint | New job with `reprint_of`; new physical print |
| Unknown | No auto-resubmit |
| Restart | In-flight background tasks do not resume; operator must inspect/reprint |

No print geometry/layout changes were made. DNP driver, 4×6 media and 2-inch cut remain **physically unverified**.

---

## 4. QR delivery audit

| Item | Finding |
|---|---|
| Token | HMAC-SHA256 `body.signature`; payload includes event/session/job/exp |
| Validation | HMAC compare + DB token hash + job binding |
| Expiry | Server TTL default 24 h; expired/invalid → 404 |
| Page | HTML links to 3 originals + strip; no GIF link |
| Original | `FileResponse`; MIME now detects JPEG/PNG; attachment filename |
| Strip | JPEG, attachment filename |
| QR PNG | PNG |
| URL | `TERABOOTH_PUBLIC_BASE_URL` or request Host; localhost rejected when configured |
| Internet | No external assets/CDN; local only |
| AP isolation | Must be off or guest VLAN must route to Windows; unverified |

### Known gap

There is **no GIF endpoint or artefact**. Animated GIF is deferred; the bridge cannot download a GIF today.

---

## 5. Windows deployment audit

### Scripts

- `install_windows.ps1`: creates `.venv`, installs `requirements.txt`, creates `.env` from root example if absent.
- `run_windows.ps1`: loads `.env` (process env wins), defaults printer to spooler, warns on placeholders/mock, rejects localhost public URL, binds `0.0.0.0:8787`.
- `firewall.ps1`: inbound TCP 8787, Private profile, requires Administrator.
- `test_print.ps1`: calibration print through spooler.
- `lan_check.py`: prints LAN IPs/probes health.

### Runtime/paths

- Python 3.11+ (audited with 3.11.9).
- Data directory `TERABOOTH_DATA_DIR` (absolute recommended).
- SQLite DB, job input/artefact/outbox under data dir.
- `.env` in `windows_bridge`; no secrets in logs.
- Printer queue name must match actual Windows queue; no invented value.

### Static-only status

The Windows scripts have **not been executed on Windows**. PowerShell 5.1 is assumed for the event PC; `curl.exe` is used in docs because PowerShell aliases `curl` to `Invoke-WebRequest`.

---

## 6. Low-risk fix applied

**File:** `windows_bridge/app/main.py`

`GET /d/{token}/original/{image_id}` now:

- detects actual stored format with Pillow;
- serves `image/jpeg` for JPEG, `image/png` for PNG;
- adjusts filename suffix;
- falls back to `application/octet-stream` if undetectable.

**Test added:** `test_delivery_original_content_type_matches_png` verifies PNG bytes are returned as `image/png` and `.png`.

No other bridge behavior, print layout or camera code changed.

---

## 7. Windows deployment procedure for tomorrow

> Use these on the actual Windows PC. Do not paste secrets into reports/logs.

### Commands

```powershell
# 0. Open PowerShell, verify Python
python --version

# 1. Project location (adjust only if different)
cd C:\Terabooth\terabooth-event-mvp\windows_bridge

# 2. Install venv + dependencies; creates .env if missing
powershell -ExecutionPolicy Bypass -File scripts\install_windows.ps1

# 3. Edit .env with the actual values
notepad .env

# 4. Firewall as Administrator
powershell -ExecutionPolicy Bypass -File scripts\firewall.ps1

# 5. Start bridge (loads .env, binds 0.0.0.0:8787)
powershell -ExecutionPolicy Bypass -File scripts\run_windows.ps1
```

In another Administrator/ordinary PowerShell window:

```powershell
# Health (use curl.exe; PowerShell 5.1's curl alias is Invoke-WebRequest)
curl.exe http://<WINDOWS_LAN_IP>:8787/v1/health

# If token configured
curl.exe -H "Authorization: Bearer <API_TOKEN>" http://<WINDOWS_LAN_IP>:8787/v1/health

# LAN/IP probe
.\.venv\Scripts\python.exe scripts\lan_check.py 8787

# Calibration
.\.venv\Scripts\python.exe scripts\make_test_sheet.py --out-dir data
powershell -ExecutionPolicy Bypass -File scripts\test_print.ps1
```

Expected `.env` keys:

```dotenv
TERABOOTH_PRINTER=spooler
TERABOOTH_PRINTER_NAME=<ACTUAL_WINDOWS_QUEUE>
TERABOOTH_API_TOKEN=<API_TOKEN_OR_EMPTY>
TERABOOTH_DELIVERY_SECRET=<LONG_RANDOM_SECRET>
TERABOOTH_PUBLIC_BASE_URL=http://<WINDOWS_LAN_IP>:8787
TERABOOTH_DATA_DIR=C:\Terabooth\data
```

### Expected outputs

| Step | Expected |
|---|---|
| `python --version` | Python 3.11+ |
| install | venv exists; pip succeeds; `.env` created/preserved |
| run | `Printer mode: spooler / <queue>`; `Listening on 0.0.0.0:8787`; no mock/placeholder warnings |
| health | JSON service `terabooth-print`; printer mode `spooler`; delivery base URL |
| LAN probe | `OK http://<LAN_IP>:8787/...` |
| calibration print | printer submits; physical output must be inspected |
| QR test | page/original/strip load from phone on same LAN |

### Failure indicators

- `python` not found / version <3.11.
- `python -m venv` or pip resolution failure.
- `.env` missing, `TERABOOTH_PRINTER=mock`, placeholder token/secret.
- `TERABOOTH_PUBLIC_BASE_URL must be ...` (localhost configured).
- `[Errno 10048]` / port 8787 already in use.
- Health `401` → iPad/bridge token mismatch.
- Health `200` but phone cannot connect → firewall/Private profile/LAN/AP isolation.
- Spooler error `Printer not valid: <queue>` → exact queue name/driver.
- Print job `unknown` → inspect physical output; do not blind reprint.
- 4×6/2×6 wrong → stop; verify media/cut/driver; do not change layout.
- QR `404` → expired/invalid token or wrong URL.
- No output but job accepted → check printer queue/spooler; `unknown` is not success.

---

## 8. Cross-platform test results

| Check | Result |
|---|---|
| `flutter analyze` | **No issues** |
| `flutter test` | **46 passed** |
| `pytest -q` | **10 passed** |
| `flutter build ios --simulator` | **Success** — 144 MB debug simulator app |
| Windows execution | **Not performed** |
| DNP physical print | **Not performed** |
| Physical iPad/EOS R | **Not performed** |

The one new Python test covers PNG MIME delivery.

---

## 9. Remaining blockers / recommended order

| Blocker | Status |
|---|---|
| Apple signing/team/profile | **BLOCKED** |
| Physical iPad install | **BLOCKED** |
| CascableCore/EOS R adapter | **BLOCKED** |
| Windows execution | **BLOCKED** until tomorrow |
| DNP physical print | **BLOCKED** |
| Guest QR/network | **BLOCKED** |
| Template/GIF | Deferred |

**Tomorrow's order:**

1. Windows install/`.env`/firewall/start/health.
2. DNP driver/media/4×6/2×6/20 prints.
3. QR iPhone/Android with WAN off and AP-isolation check.
4. Signed iPad install when available.
5. Cascable/EOS R only after approval and native adapter; 10 sessions.
6. Full rehearsal and fallback decision.

**No physical readiness claim.** The PNG MIME fix is verified only through the mock HTTP test.
