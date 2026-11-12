# Terabooth Windows Runtime Validation Package

This package validates the Phase 5A-1 bridge on the **low-resource Windows
laptop**. It intentionally uses runtime dependencies only.

## Safety

- No printer driver is installed.
- No DNP communication is performed.
- No production data is read or deleted.
- All generated session data goes under a fresh `%TEMP%\terabooth-validation-*`
  directory.
- The bridge runs with `TERABOOTH_PRINTER=mock`.
- Do not run this on a production event database.

## Prerequisites

- Windows 10/11 64-bit.
- Python 3.11+ 64-bit, or an approved installation of it.
- The `windows_bridge` folder copied to the laptop.
- Network access from another device for the optional guest gallery check.

## 1. Preflight (no installation)

```powershell
cd C:\Terabooth\terabooth-event-mvp\windows_bridge
powershell -ExecutionPolicy Bypass -File validation\preflight.ps1 |
  Tee-Object validation\preflight-output.txt
```

If Python 3.11+ is missing, stop. Do not install it automatically.

## 2. Runtime install (explicit approval required)

Review `install_runtime.ps1` first. It creates a local `.venv` and installs only
`requirements-runtime.txt`; it does not install pytest/httpx or drivers.

```powershell
powershell -ExecutionPolicy Bypass -File validation\install_runtime.ps1
```

## 3. Runtime import checks

```powershell
.\.venv\Scripts\python.exe validation\validate_runtime.py
```

This checks FastAPI, Uvicorn, Pillow, qrcode, SQLite, Unicode temp paths and
atomic replacement. It does not start the bridge.

## 4. Bridge validation

```powershell
.\.venv\Scripts\python.exe validation\validate_bridge.py `
  --keep-report
```

The script:

1. Starts `scripts/run_bridge.py` in a disposable data directory.
2. Checks health and diagnostics.
3. Creates one mock 2-photo job.
4. Checks guest page, manifest, original and ZIP.
5. Checks single-instance and port-conflict failures.
6. Stops/restarts the bridge and verifies token/database persistence.
7. Checks Unicode/atomic/SQLite WAL behavior.
8. Records actual RSS/process timings where Windows APIs allow.

The report is written to `validation\validation-report.json` and the script
prints a human summary. It never touches production `data/`.

## Optional LAN/guest check

After starting the bridge normally with mock printer:

```powershell
.\.venv\Scripts\python.exe scripts\lan_check.py 8787
```

Then open the printed LAN URL from another device. Do not disable Windows
Firewall; allow the bridge port only on the Private profile.

## Status vocabulary

- **PASS**: executed on this Windows machine and passed.
- **PARTIAL**: executed but some checks unavailable.
- **BLOCKED**: precondition failed.
- **NOT TESTED**: no execution performed.
