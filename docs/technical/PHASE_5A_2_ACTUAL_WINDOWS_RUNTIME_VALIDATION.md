# Phase 5A-2 — Actual Windows Runtime Validation

## Overall result

**BLOCKED — no Windows machine was accessible for execution in this session.**

The Phase 5A-1 portability package was inspected and a runtime-only Windows
validation package was prepared. A macOS smoke run of the validation script
passed, but **no Windows startup, dependency installation, filesystem, memory,
network or restart result is claimed**.

Status vocabulary for this report:

- **PASS**: physically executed on the Windows laptop and passed.
- **PARTIAL**: executed but incomplete.
- **BLOCKED**: precondition prevented execution.
- **NOT TESTED**: no execution performed.

Windows status: **BLOCKED / NOT TESTED**.

---

## 1. Phase 5A-1 inspection

Inspected:

- `windows_bridge/scripts/run_bridge.py`
- `windows_bridge/scripts/run_windows.ps1`
- `windows_bridge/requirements-runtime.txt`
- `windows_bridge/app/config.py`
- `windows_bridge/app/runtime.py`
- `windows_bridge/app/main.py`
- `windows_bridge/scripts/firewall.ps1`
- `windows_bridge/tests/test_portability.py`

The launcher already provides config validation, a persisted delivery secret,
an OS-backed instance lock, port preflight and single-worker Uvicorn. No working
code was rewritten for this phase.

---

## 2. Validation package prepared

Directory: `windows_bridge/validation/`

| File | Purpose |
|---|---|
| `README.md` | Safe execution checklist |
| `preflight.ps1` | Read-only Windows/CPU/RAM/disk/network/Python inventory |
| `install_runtime.ps1` | Explicitly confirmed runtime-only venv installation |
| `validate_runtime.py` | Imports, Pillow, QR, SQLite WAL, Unicode/atomic checks |
| `validate_bridge.py` | Disposable bridge startup/health/job/guest/instance/restart checks |
| `run_validation.ps1` | Sequential operator runner |

Safety properties:

- Uses `TERABOOTH_PRINTER=mock`.
- Uses a fresh `%TEMP%\terabooth-validation-*` data directory.
- Does not read/delete production event data.
- Does not install printer drivers.
- Does not modify Windows system settings.
- Does not run concurrent/heavy workloads.
- Refuses runtime installation without `-Confirm`.
- Does not claim physical printer/camera behavior.

The package uses runtime dependencies only; pytest/httpx are not required on the
Windows laptop.

---

## 3. Actual hardware / Windows results

| Item | Result |
|---|---|
| Windows version/build | **NOT TESTED — no Windows host access** |
| CPU model | **NOT TESTED** |
| Installed RAM | **NOT TESTED** |
| Available disk | **NOT TESTED** |
| Storage type | **NOT TESTED** |
| Python version/architecture | **NOT TESTED on Windows** |
| Network interfaces | **NOT TESTED on Windows** |

No hardware specifications are inferred from the target brief.

---

## 4. Runtime installation

**BLOCKED / NOT TESTED.**

No Python, virtual environment, or dependency installation was performed on
Windows. The prepared installer is:

```powershell
cd C:\Terabooth\terabooth-event-mvp\windows_bridge
powershell -ExecutionPolicy Bypass -File validation\install_runtime.ps1 -Confirm
```

It installs only `requirements-runtime.txt` after explicit confirmation.

---

## 5. Windows startup and lifecycle

| Check | Windows result |
|---|---|
| Config loading | **NOT TESTED** |
| Data/asset directory creation | **NOT TESTED** |
| Delivery secret persistence | **NOT TESTED** |
| SQLite initialization | **NOT TESTED** |
| Single-instance lock | **NOT TESTED on Windows** (macOS lock test PASS) |
| Port conflict | **NOT TESTED on Windows** (macOS port test PASS) |
| Health endpoint | **NOT TESTED on Windows** |
| Diagnostics endpoint | **NOT TESTED on Windows** |
| Clean shutdown | **NOT TESTED on Windows** |
| No unnecessary child processes | **NOT TESTED on Windows** |

The launcher's macOS behavior was previously checked: second instance and port
conflict both returned code 2.

---

## 6. Filesystem validation

**BLOCKED / NOT TESTED on Windows.**

A validation-tooling cleanup defect was reported from the Windows run:
`TemporaryDirectory` cleanup raised `WinError 32` because `sqlite3.connect(...)`
as a context manager did not close the database handle. The validation script
now closes its cursor/connection explicitly and has a regression test. The
physical Windows rerun remains required; see
`PHASE_5A_2_WINDOWS_VALIDATION_CLEANUP_FIX.md`.

A second tooling-only issue was reported from Windows: the validation report
called `sys.getwindowsversion()._asdict()`, which is not guaranteed in CPython.
The report now reads documented version attributes. The Windows rerun is still
required; see `PHASE_5A_2_WINDOWS_OS_VERSION_COMPATIBILITY_FIX.md`.

The validation script covers Unicode filenames, spaces in paths, atomic replace,
ZIP temp cleanup, SQLite WAL and manifest compatibility in a disposable
directory. It was smoke-tested on macOS; no Windows NTFS/locking behavior is
claimed.

---

## 7. Low-resource measurements

**BLOCKED / NOT TESTED on Windows.**

No Windows RSS, CPU, startup or shutdown measurements were taken. The Phase
5A-1 macOS measurements (idle ~57.7 MB, post-GIF ~108.9 MB, startup ~0.417 s) are
**not** Windows results and must not be used as acceptance evidence.

The Windows validation script records process RSS where Windows APIs allow and
writes `validation/validation-report.json`.

---

## 8. Network and guest delivery

**BLOCKED / NOT TESTED on Windows.**

No Windows LAN IP, firewall profile, Windows Firewall rule, guest phone or
Windows-hosted gallery was validated. The minimum intended rule is inbound TCP
on the configured port, Private profile only; the operator must not disable the
firewall or expose the service to the public internet.

Physical guest-phone validation remains **pending**.

---

## 9. Restart and recovery

**BLOCKED / NOT TESTED on Windows.**

The validation script is designed to test normal restart, existing DB/tokens,
asset availability, absence of duplicate processes and orphaned ZIP temp files.
No forced power-loss test is permitted or performed.

---

## 10. Issues fixed

No Windows-specific defect was observed because no Windows execution occurred.
The Phase 5A-1 foundation remains:

- portable paths and `pathlib`
- guarded Windows `resource` import in diagnostics
- runtime-only dependency set
- single-instance/port guards
- disk-backed ZIPs
- atomic manifest/GIF/composed output replacement
- bounded print/GIF/ZIP concurrency
- lightweight diagnostics

---

## 11. Mac-side verification (not a Windows substitute)

```text
Bridge tests:      53 passed
Flutter tests:    124 passed
Flutter analyze:  No issues
iOS simulator:    PASS
Bundle:           com.terabooth.teraboothIpad
Demo licence:     absent
```

`validation/validate_bridge.py` was smoke-run on macOS only and passed its
standalone checks. That report was removed; it is not retained as Windows
evidence.

---

## 12. Exact Windows validation procedure

1. Copy `windows_bridge` to the Windows laptop (e.g. `C:\Terabooth\bridge`).
2. Run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File validation\preflight.ps1
   ```
   Record Windows build, CPU, RAM, disk, storage type, Python version/arch and
   LAN IP. If Python 3.11+ is missing, stop and install it only with approval.
3. Review and run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File validation\install_runtime.ps1 -Confirm
   ```
4. Run:
   ```powershell
   .\.venv\Scripts\python.exe validation\validate_runtime.py
   ```
5. Run:
   ```powershell
   .\.venv\Scripts\python.exe validation\validate_bridge.py --port 18787 --keep-report
   ```
6. Start normally with mock printer:
   ```powershell
   powershell -ExecutionPolicy Bypass -File validation\run_validation.ps1
   ```
   For the full operator launcher use `scripts\run_windows.ps1` after setting
   `.env`.
7. Add the firewall rule only on the Private profile:
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\firewall.ps1 -Port 18787
   ```
8. From another LAN client, open:
   ```text
   http://<laptop-LAN-IP>:18787/v1/health
   http://<laptop-LAN-IP>:18787/v1/diagnostics
   ```
9. Run the guest gallery/manifest/ZIP checks from a phone or separate LAN client.
10. Repeat start, single-instance and stop checks; confirm no duplicate process,
    no orphaned temp ZIP, and persisted guest tokens.
11. Record actual Task Manager / validation-report values. Do not run heavy
    concurrent tests.
12. Return `validation/validation-report.json`, preflight output and any error
    logs for defect handling.

Do not install DNP drivers or claim physical printer validation.

---

## 13. Remaining limitations

- No actual Windows execution: all Windows-specific results are **BLOCKED/NOT
  TESTED**.
- No Windows firewall, NTFS, antivirus, SQLite WAL or process-memory evidence.
- No physical guest phone/Windows LAN validation.
- No DNP/printer validation.
- The MacBook remains the primary development machine.

**Stopped after Phase 5A-2 preparation. No Phase 5B or physical printer work
was started.**


---

## Validation tooling addendum — disposable guest smoke

A separate disposable guest phone smoke script now exists:

- `windows_bridge/validation/run_guest_phone_smoke.ps1`
- `windows_bridge/validation/guest_phone_smoke.py`

Local macOS self-test passed all guest checks and cleanup. Actual Windows
execution and the physical phone scan remain **PENDING**. See
`PHASE_5A_2_DISPOSABLE_GUEST_PHONE_SMOKE.md`.
