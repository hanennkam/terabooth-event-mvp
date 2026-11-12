# Phase 1E — Deployment Readiness & Event Operations

> **Scope:** preparation/audit. No CascableCore, no camera-topology change, no print-layout change.
> **No physical iPad, Canon EOS R, DNP printer, Windows machine or guest phone test has been completed.**
> **Event:** Saturday 14 November 2026.

---

## 1. Readiness verdict

| Area | Status |
|---|---|
| Flutter analyze/tests | **PASS — clean / 87 tests** |
| Python bridge tests | **PASS — 20 tests** |
| iOS unsigned build | **PASS — 16.5 MB** |
| Windows startup scripts | Prepared; **not executed on Windows** |
| iPad signing/install | **BLOCKED** — no Apple identity/team, no iPad |
| EOS R capture | **BLOCKED** — CascableCore pending; mock only |
| DNP physical print | **BLOCKED** — no Windows/DNP hardware |
| Guest QR on phone | **BLOCKED** — no phone/router |
| Print layout | Code verified; physical 2×6 cut unverified |

This is **not** physical readiness. The app currently runs the mock camera by default.

---

## 2. Repository / build audit

### Flutter dependencies

`ipad_app/pubspec.yaml`:

- `http ^1.6.0`
- `path_provider ^2.1.6`
- `crypto ^3.0.8`
- `qr_flutter ^4.1.0`
- dev: `flutter_test`, `flutter_lints ^6.0.0`

No CascableCore package. No camera plugin package.

### Python bridge dependencies

`windows_bridge/requirements.txt`:

- `fastapi==0.162.2`
- `uvicorn==0.54.0`
- `pillow==13.0.0`
- `qrcode==8.2`
- `python-multipart==0.0.33`
- `pytest==9.2.0`
- `httpx==0.28.1`

Requires Python 3.11+; developed/tested with Python 3.11.9 on macOS.

### iOS configuration

| Item | Value |
|---|---|
| Workspace | `ipad_app/ios/Runner.xcworkspace` |
| Bundle ID | `com.terabooth.teraboothIpad` |
| Deployment target | **iOS 13.0** |
| Device family | iPhone + iPad |
| Signing style | Automatic |
| Code sign identity | `iPhone Developer` |
| Development team | **empty** |
| Valid signing identities | **0** |
| Provisioning profile | **none** |
| Permissions | Camera, Local Network, Bonjour `_ptp._tcp`, ATS local networking |

Do **not** raise the deployment target to iOS 14 until CascableCore is actually added; the current app builds at 13.0.

### Bridge endpoints / configuration

| Endpoint | Purpose | Auth |
|---|---|---|
| `GET /v1/health` | service/printer/delivery status | Bearer if configured |
| `GET /v1/printers` | printer health | Bearer if configured |
| `POST /v1/print-jobs` | submit 3 images + metadata | Bearer if configured + `Idempotency-Key` |
| `GET /v1/print-jobs/{id}` | state/completion/delivery URL | Bearer if configured |
| `GET /v1/print-jobs/{id}/artefact` | composed 4×6 JPEG | Bearer if configured |
| `POST /v1/print-jobs/{id}/reprint` | new job referencing original | Bearer if configured |
| `DELETE /v1/print-jobs/{id}` | cancel before printing | Bearer if configured |
| `GET /d/{token}` | guest download page | HMAC token |
| `GET /d/{token}/original/{image_id}` | original JPEG | HMAC token |
| `GET /d/{token}/strip` | composed strip | HMAC token |
| `GET /d/{token}/qr.png` | QR PNG | HMAC token |

`base_url()` precedence:

1. `TERABOOTH_PUBLIC_BASE_URL` if set.
2. Otherwise `request.base_url` (the Host the iPad/guest used).

`create_app()` rejects a configured `TERABOOTH_PUBLIC_BASE_URL` containing `localhost` or `127.0.0.1`.

`BridgeClient` default URL is `http://192.168.8.50:8787`; the welcome screen allows the operator to enter the actual Windows LAN IP. The URL is not persisted across app restarts.

### Localhost audit

- iPad default is a **LAN IP**, not localhost.
- iPad welcome field is editable.
- Windows bridge binds `0.0.0.0:8787` in `run_windows.ps1`.
- QR URL uses the configured public LAN base or the request Host.
- `TERABOOTH_PUBLIC_BASE_URL` rejects localhost.
- `lan_check.py` explicitly warns that the Windows LAN IP must be used.

**Operational requirement:** no component should use `localhost` for iPad↔Windows or guest↔Windows. Windows-local health checks may use `127.0.0.1`.

### Print job flow

1. iPad sends 3 JPEGs + metadata with `Idempotency-Key`.
2. Bridge validates auth, hashes, count and dimensions; stores job/session/images.
3. Background task composes the 4×6 artefact and submits to printer.
4. States: `received → validated → composing → queued → printing → completed|failed|unknown`.
5. `202` means accepted, not printed.
6. `unknown` is never auto-resubmitted.
7. Reprint creates a new job with `reprint_of`; it is a real second print.
8. iPad polls `GET /v1/print-jobs/{id}` for up to 60 iterations at 1 s.

### Error handling/logging

- FastAPI returns explicit HTTP errors; job-level errors persist in SQLite and job JSON.
- Printer submission exceptions become `failed`; ambiguous completion becomes `unknown`.
- No Python logging configuration/rotation; Uvicorn console output is the operational log.
- Bridge restart does **not** resume in-flight background print tasks. A job left in `printing`/unknown requires physical inspection; do not auto-resubmit.

### Concrete defects fixed this phase

1. **`.env` was ignored by `run_windows.ps1`.** The install script told operators to create `.env`, but the startup script never loaded it, so printer mode, tokens, secrets and LAN URL were silently missed. Added a `.env` loader (explicit process env wins) and install-time `.env` creation.
2. **Bridge API token had no iPad counterpart.** Enabling `TERABOOTH_API_TOKEN` would cause 401s. Added `--dart-define=TERABOOTH_API_TOKEN=...` to the iPad build; `BridgeClient` already sends the Bearer token.
3. Placeholder token/secret and `mock` printer now produce startup warnings.

No MySQL/cloud/auth/login was added.

---

## 3. Windows deployment procedure

> Requires a real Windows laptop and DNP DS-RX1HS; not executed here.

### Prerequisites

- Windows 11 x64, updated, high-performance power plan, sleep disabled.
- Python **3.11+ 64-bit** (`python --version`).
- DNP DS-RX1HS + USB cable + power.
- DNP Windows driver installed; printer visible in Windows.
- 4×6 media loaded; 2-inch cut enabled.
- Project copied to e.g. `C:\Terabooth\terabooth-event-mvp\windows_bridge`.
- Router/static IP/DHCP reservation planned.

### Install

```powershell
cd C:\Terabooth\terabooth-event-mvp\windows_bridge
powershell -ExecutionPolicy Bypass -File scripts\install_windows.ps1
```

This creates `.venv`, installs requirements, and creates `.env` from `..\.env.example` if absent.

### Configure `.env`

Edit `windows_bridge\.env`:

```dotenv
TERABOOTH_PRINTER=spooler
TERABOOTH_PRINTER_NAME=DNP DS-RX1HS
TERABOOTH_API_TOKEN=<long-random-token>
TERABOOTH_DELIVERY_SECRET=<long-random-secret>
TERABOOTH_PUBLIC_BASE_URL=http://<windows-lan-ip>:8787
TERABOOTH_DATA_DIR=C:\Terabooth\data
TERABOOTH_TOKEN_TTL_HOURS=24
TERABOOTH_JOB_TIMEOUT_SECONDS=60
```

- Use `spooler` for the PowerShell 4×6 driver path, or `hotfolder` for DNP HFP.
- `mock` writes files only; it is not a printer.
- If `TERABOOTH_API_TOKEN` is set, the iPad must be built with the same `--dart-define`.
- `TERABOOTH_DELIVERY_SECRET` must be long/random; it signs guest links.

### Firewall

Run PowerShell **as Administrator**:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\firewall.ps1
```

Creates inbound TCP 8787 on the **Private** profile only. Windows network must be Private.

### Printer checks

```powershell
# Windows test page first
# Then DNP driver/media checks
.\.venv\Scripts\python.exe scripts\make_test_sheet.py --out-dir data
powershell -ExecutionPolicy Bypass -File scripts\test_print.ps1
```

- Confirm printer name exactly matches `TERABOOTH_PRINTER_NAME`.
- Confirm 4×6 media and 2-inch cut in driver/HFP.
- Measure the physical output before the event.
- `WindowsSpoolerPrinter` reports completion `unknown`; the operator must verify the physical print.

### Start

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_windows.ps1
```

- Loads `.env`, defaults to spooler if unset, binds `0.0.0.0:8787`.
- Keep the PowerShell window open; Ctrl+C stops the bridge.
- Do not close/restart while a print is in progress.

Health:

```powershell
curl.exe http://<windows-lan-ip>:8787/v1/health
```

If a token is set:

```powershell
curl.exe -H "Authorization: Bearer <token>" http://<windows-lan-ip>:8787/v1/health
```

### Persistent data / shutdown

- `TERABOOTH_DATA_DIR` contains SQLite DB, job inputs, artefacts, outbox.
- Default `C:\Terabooth\data` is outside the project; back it up after the event.
- Normal shutdown: wait for prints to finish, then Ctrl+C in the bridge window.
- On restart, inspect jobs in `printing`/`unknown`; do not auto-reprint without checking physical output.

---

## 4. iPad deployment procedure

### Current config

- Bundle ID `com.terabooth.teraboothIpad`.
- Deployment target **13.0** (do not raise to 14 until CascableCore requires it).
- Automatic signing, but **no team/identity** currently.
- Camera/native flag: default mock; `--dart-define=USE_NATIVE_CAMERA=true` only after Cascable integration.

### Signing

1. Xcode → Settings → Accounts → add Apple ID.
2. Open:

```bash
cd /Users/Apple/Dev/terabooth-event-mvp/ipad_app
open ios/Runner.xcworkspace
```

3. Runner → Signing & Capabilities → Automatically manage signing.
4. Select the Team; keep bundle ID unless registration conflicts.
5. Connect/trust iPad; enable Developer Mode; restart.

### Commands

```bash
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run -d <ipad-device-id>
```

If a bridge token is configured:

```bash
flutter run -d <ipad-device-id> \
  --dart-define=TERABOOTH_API_TOKEN=<same-token>
```

Release build:

```bash
flutter build ipa --release \
  --dart-define=TERABOOTH_API_TOKEN=<same-token>
```

Do **not** use `--no-codesign` for installation. Do **not** use `USE_NATIVE_CAMERA=true` until the native adapter is implemented and tested.

### Permissions on first launch

- Camera.
- Files and Folders.
- Local Network.
- Verify in iPad Settings → Privacy & Security and app Settings.

### Lifecycle / build differences

- Background/foreground handling exists; a capture interrupted by background fails deliberately.
- Debug build needs the Flutter host/hot-reload; release build is standalone and should be used for the event.
- Unsigned release build only proves compilation, not installation.

---

## 5. Network and QR requirements

### Router

- iPad and Windows on the same LAN/VLAN.
- **AP/client isolation must be OFF** for iPad↔Windows and guest↔Windows.
- If guests use a separate SSID/VLAN, it must route/allow access to the Windows IP:8787; do not assume it does.
- No internet/WAN required for printing or QR.
- DHCP reservation/static IP for Windows.
- Avoid guest networks that block client-to-client traffic.

### Verification

On Windows:

```powershell
.\.venv\Scripts\python.exe scripts\lan_check.py 8787
```

On iPad:
- Enter `http://<windows-lan-ip>:8787` in the welcome screen.
- Session submit must succeed.

On guest phone (WAN off):
- Scan QR; confirm page, originals and strip download.

### QR behaviour

- token HMAC signed with `TERABOOTH_DELIVERY_SECRET`.
- DB record binds token to job; expiry default 24 h.
- QR uses `TERABOOTH_PUBLIC_BASE_URL` if set; otherwise request Host.
- Do not use localhost/127.0.0.1 in QR.
- If the guest network isolates clients, QR will fail even though the bridge is healthy.

---

## 6. Printer workflow audit

- Canvas: **1200×1800** at 300 dpi = 4×6 in.
- Two identical strips: **600×1800** each = 2×6 in.
- 3 photo slots per strip; header/footer; `ImageOps.fit` cover crop.
- `ImageOps.exif_transpose` applied before crop (all orientation tests pass).
- Printed sheet: one 4×6 sheet, two 2×6 strips, DNP 2-inch cut.
- Submission: spooler PowerShell 4×6 zero margins, or HFP folder.
- Duplicate protection: `Idempotency-Key` at API; duplicate returns existing job.
- Reprint: explicit new job; it prints again.
- Unknown status: no auto-resubmit; operator inspects physical output.

### Requires physical DNP testing

- Driver on Windows 11.
- Actual 4×6 dimensions and margins.
- 2×6 cut alignment.
- Orientation/EXIF on real EOS R JPEGs.
- Colour/quality.
- 20 consecutive prints.
- Spooler vs HFP reliability.
- Duplicate and reprint physical counts.

---

## 7. Tests / build (final)

```bash
cd ipad_app
flutter analyze
flutter test
flutter build ios --no-codesign

cd ../windows_bridge
./.venv/bin/pytest -q
```

| Check | Result |
|---|---|
| `flutter analyze` | **No issues** |
| `flutter test` | **87 passed** |
| `pytest -q` | **39 passed** |
| iOS unsigned build | **Success — 16.5 MB** |
| Physical deployment | **Not performed** |

---

## 8. Potential blockers

1. **No Apple signing identity/team/profile** — cannot install on iPad.
2. **No CascableCore / native adapter** — EOS R capture cannot be used; mock only.
3. **No Windows/DNP verification** — spooler/HFP unverified.
4. **No guest phone/router test** — QR/AP isolation unverified.
5. **Windows `.env` loader untested on Windows** — static review only.
6. **Bridge restart does not resume in-flight jobs** — inspect/reprint manually; no auto-retry.
7. **Printer completion is unknown with spooler** — operator must verify physical output.
8. **Default URL hardcoded** — operator must enter actual Windows LAN IP.
9. **Token default/placeholder** — must be replaced; matching iPad build required.

---

## 9. Remaining physical tests

- Sign/install launch on iPad; permissions.
- Mock 3-photo workflow on device.
- QR from guest phone with WAN off.
- DNP 4×6 print, 2×6 cut, orientation, 20 prints, duplicate/reprint.
- EOS R USB capture only after CascableCore approval/integration.
- Camera disconnect/power-off/background/reconnect.
- Full 10-session rehearsal.

See `docs/EVENT_DAY_RUNBOOK.md` for operations.
