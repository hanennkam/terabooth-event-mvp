# Phase 5B-1 — DNP DS-RX1HS Printing Integration Audit & Readiness

## Overall result

**PASS for software audit and automated readiness.**  
**Physical DNP printing is NOT TESTED.**

No printer was installed, no print job was sent to a physical printer, and no DNP
driver was installed or modified. `MockPrinter` remains the default.

---

## 1. Printer architecture

### Boundary

`windows_bridge/app/printer.py` defines the existing `Printer` Protocol:

```text
submit(job_id, artefact, copies) -> PrintHandle
status(handle) -> PrintStatus
health() -> dict
```

Adapters:

| Adapter | Method | Status |
|---|---|---|
| `MockPrinter` | copies composed JPEG to outbox | Default; no physical output |
| `WindowsSpoolerPrinter` | PowerShell `System.Drawing.Printing` → Windows spooler | Implemented; physically unverified |
| `HotFolderPrinter` | DNP Hot Folder Print folder | Implemented; physically unverified |

No vendor SDK is used. The Windows path depends on the official DNP Windows
driver exposing a printer queue to `System.Drawing.Printing`.

### Exact path to a physical submission

```text
Approved Flutter session
  -> BridgeClient POST /v1/print-jobs
  -> metadata/images validated and stored
  -> background process_job:
       template/branding composition -> artefact.jpg
       state=queued
       printer.submit(job_id, artefact, copies)
       state=printing
       printer.status polling
  -> WindowsSpoolerPrinter.submit:
       powershell -File scripts/print_image.ps1
       -ImagePath artefact.jpg
       -PrinterName <configured DNP queue>
       -Copies <1|2>
  -> PrintDocument / Windows spooler
  -> DNP driver/printer (physical output)
```

`print_image.ps1`:

- loads the composed JPEG only;
- sets 4×6 paper using hundredths of an inch (`400×600`);
- zero margins, portrait;
- draws the artifact across the full page;
- loops `Print()` for the requested copies;
- returns after spooler acceptance.

The generated artifact is 1200×1800 at 300 dpi (4×6, 2:3).

---

## 2. DNP DS-RX1HS compatibility assessment

### Verified in source

- Windows spooler printing is implemented.
- Output is 4×6 portrait, 1200×1800 at 300 dpi.
- Copies 1–2 are accepted by the API and passed to the adapter.
- The printer name is configurable via `TERABOOTH_PRINTER_NAME`.
- Printer mode is configurable via `TERABOOTH_PRINTER`.
- Spooler submission errors become a failed print job.
- Acceptance is not reported as physical completion (completion is `unknown`).

### Requires physical validation

- Official DNP DS-RX1HS Windows driver availability and installation.
- Printer queue visibility/name.
- USB connection and Windows printer readiness.
- Supported media: 4×6 paper and 2-inch cut configuration.
- Orientation handling by the DNP driver.
- Color/quality settings.
- Paper-out, ribbon/media error, offline and communication failure reporting.
- Whether the driver exposes status/cut completion to the spooler.
- Actual two-copy behavior.
- Actual physical completion timing.

### Readiness reporting

`WindowsSpoolerPrinter.health()` returns `state: unknown`; it does not claim the
printer is ready. `print_image.ps1` checks `PrinterSettings.IsValid` at
submission, but there is no paper/ribbon status query. Completion after spooler
acceptance is `unknown`, not `confirmed`.

---

## 3. Output correctness

| Check | Result |
|---|---|
| 4×6 dimensions | **1200×1800, 300 dpi** |
| Aspect ratio | **2:3 portrait** |
| Orientation | Artifact portrait; driver/driver-media orientation unverified |
| Crop/fit | Existing template/crop planner |
| Branding | Applied once in the derived artifact renderer |
| Original JPEG | Read-only; never used as print mutation target |
| Copies | 1–2 accepted and passed to adapter |
| Duplicate submission | Idempotency key returns existing job |
| Retry | No automatic retry; reprint is explicit/new job |
| Double branding | No second branding pass in print script |

The print script draws the already-composed artifact; it does not apply a second
template or branding layer.

---

## 4. Queue and failure safety

### States

```text
received -> validated -> composing -> queued -> printing
                                               -> completed
                                               -> failed
                                               -> unknown
```

- State and attempts are persisted in SQLite.
- `print_semaphore = 1`: one composition/print orchestration at a time.
- Single-instance launcher protects against two bridge processes.
- Guest QR/GIF/ZIP work is separate and still available.

### Restart recovery (new)

Previously, open jobs could remain stuck after a bridge restart. Added
`recover_print_jobs()` at startup:

- `printing` → **unknown**, completion unknown, error asks operator to verify
  physical output.
- `received`, `validated`, `composing`, `queued` → **failed**, completion
  unknown, error asks for explicit Reprint.
- **No automatic resubmission or physical retry.**
- Attempt records are written for audit.

This avoids both indefinite `printing` jobs and silent duplicate prints.

### Printer unavailable

- `submit` exception → job `failed`, completion `unknown`.
- Spooler accepted → job `unknown`/completion `unknown`; never claimed physical.
- Operator must verify physical print before handing it to a guest.

### Multiple copies

- API accepts 1–2 copies; both are passed to the adapter.
- `print_image.ps1` loops the print request.
- Mock test records copy count; physical two-copy behavior remains unverified.

---

## 5. Changes made

- `app/main.py`: added startup `recover_print_jobs()`; no auto-resubmit.
- `app/db.py`: added `jobs_in_states()` for recovery.
- `app/printer.py`: `MockPrinter` now records submitted copy counts.
- `tests/test_print_readiness.py`: new readiness/regression tests.

No change to the print API, metadata contract, template renderer, Flutter app,
camera, QR/GIF/ZIP or production bundle.

---

## 6. Tests and verification

### Bridge

```text
.venv/bin/python -m pytest -q
61 passed
```

New tests:

- Valid 4×6 job completes.
- Two-copy request accepted and recorded.
- Original image hashes unchanged after job.
- Duplicate idempotency key returns same job.
- Mock printer failure is terminal and never claims success.
- Invalid image rejected before print.
- Restart:
  - printing job becomes unknown, not completed;
  - queued job becomes failed, not automatically submitted;
  - no duplicate print is attempted.
- Mock copy count recorded.

### Flutter

```text
flutter analyze: No issues
flutter test --concurrency=1: 137 passed
```

No Flutter source changed.

---

## 7. Exact physical Windows test checklist

Do not run steps 6–8 without explicit operator authorization.

1. On the Windows laptop, confirm the official DNP DS-RX1HS Windows driver is
   installed and the printer appears:
   ```powershell
   Get-Printer | Where-Object Name -match "DNP|DS-RX1"
   ```
2. Confirm USB/printer connection and print a Windows test page through the DNP
   driver (outside this app).
3. Set the DNP media to **4×6**, portrait; configure **2-inch cut** if using two
   strips. Record the exact driver/media settings.
4. Confirm `TERABOOTH_PRINTER_NAME` exactly matches the Windows queue name and
   `TERABOOTH_PRINTER=spooler`.
5. Start the bridge with the portable launcher and verify health/diagnostics:
   ```powershell
   cd C:\Users\User.IZZATY\Documents\Terabooth\terabooth-event-mvp\windows_bridge
   powershell -ExecutionPolicy Bypass -File scripts\run_windows.ps1
   ```
6. **Authorized single calibration print** (operator present):
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\test_print.ps1 `
     -ImagePath data\test-4x6-calibration.jpg `
     -PrinterName "DNP DS-RX1HS"
   ```
7. Submit one approved test session with `copies=1`; record job ID, state,
   attempts, artefact, and physical output. Compare orientation, crop, branding
   and dimensions to the expected 4×6 layout.
8. Submit a controlled two-copy check only after step 7 passes; verify two
   physical prints, no automatic duplicates, and queue behavior.
9. Check paper-out/offline behavior manually; record whether the Windows queue /
   DNP driver reports an error or leaves the job in spooler.
10. Do not claim completion from spooler acceptance alone. Verify the physical
    output before guest handoff.

---

## 8. Known limitations / unresolved risks

- No physical DNP print has been made.
- The current adapter uses the Windows spooler/driver, not a DNP vendor SDK.
- Physical completion remains `unknown`; only spooler acceptance is known.
- No paper/ribbon/offline status query is implemented.
- 2-inch cut and 4×6 media behavior depend on driver configuration and remain
  unverified.
- Orientation after driver processing is unverified.
- Two-copy physical behavior is unverified.
- Hot-folder transport is an alternative but also unverified.
- A bridge restart during spooler submission is marked unknown and requires
  operator verification; no automatic retry.
- The Windows machine and driver are not accessed in this phase.

**Stopped after audit and automated verification. No physical print was
submitted.**
