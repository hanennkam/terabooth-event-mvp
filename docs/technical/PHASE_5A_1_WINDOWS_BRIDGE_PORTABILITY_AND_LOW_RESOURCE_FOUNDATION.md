# Phase 5A-1 — Windows Bridge Portability & Low-Resource Deployment Foundation

## Overall result

**PASS for the implemented portability and low-resource foundation.**

The bridge remains a single-process FastAPI/Uvicorn service with the existing
API, SQLite schema, guest delivery, QR/GIF/ZIP paths and print-adapter boundary.
Changes are additive and preserve Phase 4A/4B/4C behavior.

No physical Windows, DNP printer, camera or iPad validation is claimed.

---

## 1. Architecture audit

| Area | Current implementation | Assessment |
|---|---|---|
| Runtime | Python 3.11.9, FastAPI 0.162.2, Uvicorn 0.54.0 | Portable, pinned |
| Database | stdlib SQLite, WAL, additive migrations | Windows-compatible in code; physical test pending |
| Images | Pillow 13.0.0, qrcode 8.2 | Portable |
| HTTP | FastAPI/Starlette, python-multipart | Portable |
| Background work | asyncio tasks for print composition and GIF | Was unbounded; now bounded |
| Print | `Printer` Protocol: mock, spooler, hot-folder | Boundary already clean; physical DNP unverified |
| Guest delivery | tokenized `/d/{token}` page, originals/strip/GIF | Preserved and extended |
| Storage | pathlib paths under data dir/jobs | Mostly portable; ZIP was in-memory |
| Startup | PowerShell had direct `uvicorn` call | No single-instance/port/config guard |

### Portability findings

- Paths were mostly `pathlib`; font fallbacks already include Windows.
- `resource` is unavailable on Windows; diagnostics code now guards it.
- `os.chmod` has no meaningful effect on Windows but already catches failures.
- PowerShell scripts use Windows paths and `Join-Path`; the launcher had a
  path-escaping bug in the new launcher transition and was corrected.
- ZIP download built the complete archive in memory.
- No startup lock or port preflight.
- No configuration validation; the delivery secret had a source-code default.
- Two duplicate helper definitions remained in `main.py`; cleaned.
- No Windows service installation is performed.

---

## 2. Changes made

### Configuration and validation

`app/config.py`:

- `ConfigurationError`, `validate_settings`.
- `Settings` now supports:
  - `host` (`TERABOOTH_HOST`, default `0.0.0.0`)
  - `port` (`TERABOOTH_PORT`, default `8787`)
  - `assets_dir` (`TERABOOTH_ASSETS_DIR`, default `<data>/jobs`)
- `load_settings` creates data/jobs/outbox/DB/asset directories.
- Validation checks printer mode, host/port range, TTL, image limits, writable
  paths and non-loopback `TERABOOTH_PUBLIC_BASE_URL`.
- Delivery secret:
  - `TERABOOTH_DELIVERY_SECRET` if supplied.
  - Otherwise generated once and stored in `<data>/.delivery_secret` (mode 600
    where supported). No secret is hardcoded in source.
- Safe warnings for empty API token and unverified printer modes.

### Portable foreground launcher

`scripts/run_bridge.py`:

1. Loads optional `.env`.
2. Loads and validates settings.
3. Acquires an OS-backed single-instance lock at `<data>/.bridge.lock`.
4. Preflights the configured host/port and reports port conflicts.
5. Starts Uvicorn with **one worker**, one process, access logging off.
6. Releases the lock in a `finally` block on Ctrl+C/failure.

`scripts/run_windows.ps1` now invokes this launcher instead of calling Uvicorn
directly. It supports `-Port` and leaves host/data configuration to `.env`.

### Concurrency and memory

- Print composition/printing: one active job (`Semaphore(1)`).
- GIF generation: one active generator (`Semaphore(1)`).
- ZIP generation: one active archive build (`Semaphore(1)`), moved off the event
  loop with `asyncio.to_thread`.
- ZIPs are generated as temporary files on disk and returned via `FileResponse`
  with a background delete; no full archive is kept in memory.
- Shutdown cancels and awaits outstanding background tasks.
- Manifest writes use temp file + retrying atomic replacement.
- GIF output and composed JPEGs use the same atomic replacement helper.
- Active task counters are exposed for diagnostics.

### Diagnostics

`GET /v1/diagnostics` (operator auth) returns lightweight values:

- process PID, RSS, CPU seconds, uptime
- queue depth
- active print/GIF/ZIP tasks and total background tasks
- asset bytes, disk total/free

RSS uses stdlib/platform APIs (`/proc`, `resource`, Windows `ctypes`), not a
monitoring dependency.

### Windows scripts/dependencies

- `requirements-runtime.txt` contains only runtime packages.
- `requirements-dev.txt` adds pytest/httpx for development.
- `install_windows.ps1` installs runtime-only requirements and checks Python
  >= 3.11.
- `firewall.ps1` accepts a configurable `-Port`.
- `.env.example` documents host, port and optional asset root.

### Printer boundary

The existing `Printer` Protocol/adapters remain the boundary:

- `MockPrinter` for Mac/CI and development.
- `HotFolderPrinter` and `WindowsSpoolerPrinter` remain clearly unverified.
- Print orchestration is separate from transport; no DNP driver or physical
  communication was added.

---

## 3. Dependencies

Runtime (`requirements-runtime.txt`):

```text
fastapi==0.162.2
uvicorn==0.54.0
pillow==13.0.0
qrcode==8.2
python-multipart==0.0.33
```

Development-only (`requirements-dev.txt`):

```text
pytest==9.2.0
httpx==0.28.1
```

Python: **3.11+**, 64-bit. No Docker, WSL, Redis, Celery, PyInstaller or
monitoring agent.

---

## 4. Startup and shutdown

Operator flow (Windows):

```powershell
cd C:\Terabooth\terabooth-event-mvp\windows_bridge
powershell -ExecutionPolicy Bypass -File scripts\run_windows.ps1
```

Portable foreground flow on any OS:

```bash
python scripts/run_bridge.py
```

Configuration is read from `.env` plus process environment. Stop with Ctrl+C;
the lock is released and background tasks are cancelled. No Windows service or
system-level configuration is installed in this phase.

Port conflict and second-instance startup exit with code `2` and a clear message.

---

## 5. Configuration

```dotenv
TERABOOTH_PRINTER=mock
TERABOOTH_PRINTER_NAME=DNP DS-RX1HS
TERABOOTH_API_TOKEN=change-me
TERABOOTH_DELIVERY_SECRET=change-me-long-random
TERABOOTH_PUBLIC_BASE_URL=http://192.168.8.50:8787
TERABOOTH_DATA_DIR=./data
# TERABOOTH_ASSETS_DIR=C:\Terabooth\assets
TERABOOTH_HOST=0.0.0.0
TERABOOTH_PORT=8787
TERABOOTH_TOKEN_TTL_HOURS=24
TERABOOTH_JOB_TIMEOUT_SECONDS=60
```

Rules:

- `TERABOOTH_PUBLIC_BASE_URL` must be a LAN address, not localhost.
- `TERABOOTH_HOST=0.0.0.0` is required for guest phones on the LAN.
- Existing data/assets are preserved; no migration or deletion.
- Optional asset root must be writable.
- `TERABOOTH_API_TOKEN` should be set for event operation.
- `TERABOOTH_DELIVERY_SECRET` may be omitted; the launcher creates a persisted
  random secret.

---

## 6. Storage requirements

- Python runtime + venv: roughly 100–200 MB on disk.
- Data/DB/originals/assets: event-dependent; keep at least several GB free for
  photos, strips, GIFs and ZIP temp files.
- ZIP temp files live in the job directory and are deleted after the response.
- Manifest and GIF temp files are atomic-replaced; abandoned GIF temp files are
  cleaned on startup.
- SQLite WAL files may remain beside the DB.
- Existing `data/jobs/<job>` and guest delivery structure is unchanged.

---

## 7. Resource benchmark

Measured on the macOS development machine with a temporary mock bridge;
this is **not** a Windows measurement.

Procedure: start `scripts/run_bridge.py`, submit a 4-photo grid job, wait for
print/GIF completion, request five gallery pages + five ZIP downloads, and read
the diagnostics endpoint.

Results:

| Measurement | Result |
|---|---:|
| Startup to healthy | **0.417 s** |
| Idle RSS | **57.7 MB** (~55 MiB) |
| RSS after 4-photo composition + GIF | **108.9 MB** (~104 MiB) |
| RSS after 10 guest page/ZIP requests | **109.2 MB** (~104 MiB) |
| 5 page + 5 ZIP requests | **0.09 s** total |
| Active print/GIF/ZIP after completion | **0 / 0 / 0** |
| GIF state | **ready** |
| ZIP status | **200** on all requests |

Practical 4GB target budget:

- Bridge idle: **< 120 MB**.
- Bridge peak during composition/GIF/download: **< 250 MB**.
- Leave at least **2.5–3 GB** for Windows, browser, antivirus and OS cache.
- Do not run heavy developer tools on the event laptop.
- `TERABOOTH_PRINTER=mock` for development; actual DNP is a later phase.

The measured values are from macOS/Pillow/CPython and will differ on Windows;
they are evidence for sizing, not a Windows guarantee.

---

## 8. Verification

### Bridge

```text
.venv/bin/python -m pytest -q
53 passed
```

New portability tests cover:

- Config validation and safe defaults.
- Single-instance lock and release.
- Port conflict detection.
- Unicode paths/filenames and path-free manifest.
- Atomic manifest replacement.
- Disk-backed ZIP generation.
- Diagnostics endpoint.

Existing Phase 4C/4B guest, QR, GIF, ZIP, branding and API tests remain green.

### Manual launcher checks

```text
second instance: RC 2 — another Terabooth Bridge instance is already running
same port, different data: RC 2 — cannot bind ... Address already in use
startup health: 200
```

### Flutter

```text
flutter analyze: No issues
flutter test --concurrency=1: 124 passed
```

No Flutter source was changed in this phase.

### Build

```text
flutter build ios --simulator --no-codesign: PASS
bundle: com.terabooth.teraboothIpad
demo licence: absent
```

---

## 9. Remaining Windows-specific risks

- No actual Windows execution was performed in this phase.
- Windows file locking/antivirus behavior, Defender exclusions, and SQLite WAL
  behavior remain unverified on the target laptop.
- Windows Firewall and router client/AP isolation can still block guest access.
- Python 3.11+ and Visual C++ runtime availability on the laptop must be checked.
- The spooler/hot-folder adapters remain unverified; no DNP driver is installed.
- `uvicorn` shutdown on Windows may leave a short port-release delay; restart
  after a few seconds if needed.
- Path length/Unicode behavior is covered by portable tests but not physically
  exercised on Windows.

---

## 10. Exact Windows laptop validation steps

Do this on the 4GB laptop with **mock printer only**; do not install DNP drivers
or claim printer validation.

1. Confirm Windows 10/11 64-bit, Python 3.11+ installed, and at least 3 GB free.
2. Copy `terabooth-event-mvp\windows_bridge` to e.g. `C:\Terabooth\bridge`.
3. Run PowerShell as the normal operator:
   ```powershell
   cd C:\Terabooth\bridge
   powershell -ExecutionPolicy Bypass -File scripts\install_windows.ps1
   ```
4. Copy `..\.env.example` to `.env`; set:
   - `TERABOOTH_PRINTER=mock`
   - `TERABOOTH_DATA_DIR=C:\Terabooth\data`
   - `TERABOOTH_HOST=0.0.0.0`
   - `TERABOOTH_PORT=8787`
   - `TERABOOTH_PUBLIC_BASE_URL=http://<laptop-LAN-IP>:8787`
   - unique API token and delivery secret.
5. Open the firewall for the configured port (Private profile) as Administrator:
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\firewall.ps1 -Port 8787
   ```
6. Start:
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\run_windows.ps1
   ```
7. From another LAN device:
   ```text
   http://<laptop-LAN-IP>:8787/v1/health
   http://<laptop-LAN-IP>:8787/v1/diagnostics
   ```
   Use the API token header if configured.
8. Run `scripts\lan_check.py 8787` on the laptop and confirm a non-loopback URL.
9. With mock printer, submit a small test job and open the guest QR from a phone;
   verify gallery, original, strip, GIF when ready, manifest and ZIP.
10. Start a second instance in another terminal; confirm exit code 2 and no
    duplicate service.
11. Stop with Ctrl+C, confirm port 8787 is released, restart, and verify existing
    jobs/guest links still resolve.
12. Record Task Manager memory idle/peak and disk free; keep the laptop otherwise
    idle. Do not run the benchmark-heavy tests on the event laptop.

If any step fails, report the exact command/output rather than assuming Windows
compatibility.

---

## 11. Recommended next phase

Proceed only after the Windows laptop completes the mock-printer validation:

1. Phase 5B can add the physical DNP adapter using the existing `Printer`
   boundary.
2. Keep the runtime-only dependency set and foreground launcher.
3. Add a signed/packaged deployment only if a real operator workflow justifies it.
4. Never treat macOS benchmark numbers as Windows acceptance evidence.

Stopped after Phase 5A-1. No physical printer or Phase 5B work was started.
