# Phase 6D-5 — DNP DS-RX1 Print Pipeline Readiness

## Overall result

**PASS for source/test readiness; BLOCKED for physical print.**
**MockPrinter remains active. No print job was submitted.**

The pipeline now distinguishes machine, user and job-level ticket information,
fails closed when the two configured tickets are not safe, and refuses to invoke
the spooler unless the DNP queue is in the required state.

---

## 1. Actual root cause

The old path did not request DNP vendor job features explicitly:

```text
1200×1800 JPEG
  → WindowsSpoolerPrinter.submit
  → print_image.ps1
  → System.Drawing.Printing.PrintDocument
  → 4×6 PaperSize + Portrait + zero margins
  → Windows spooler/DNP driver
```

`PrintDocument` only set page geometry. It did **not** set the DNP vendor
`DocumentCUTTERCONTROL` feature or force the driver media option. The actual
spooler job therefore depended on the effective DEVMODE/PrintTicket defaults.

The old preflight read `Get-PrintConfiguration` only. That reflected the machine
ticket (PC 6×4 / CUT_STANDARD) while the per-user ticket was different
(PR_4x6 / CUT_2INCH). This made the preflight misleading.

### Current live evidence

| Source | Media | Orientation | Resolution | Cut |
|---|---|---|---|---|
| Machine DefaultPrintTicket | PC (6×4) | Portrait | 300×300 | CUT_STANDARD |
| Per-user UserPrintTicket | PR_4x6 | Portrait | 300×300 | CUT_2INCH |
| Effective job | **Not inspectable without submitting** | — | — | — |

The new preflight reports each source separately and labels effective job
configuration unavailable rather than guessing.

---

## 2. Changes

### Preflight (`scripts/printer_preflight.ps1`)

- Uses `System.Printing` to read:
  - `PrintQueue.DefaultPrintTicket` (machine default)
  - `PrintQueue.UserPrintTicket` (per-user)
  - `PrintCapabilities` (supported media/orientation/resolution/cut)
  - queue/driver/port/status/offline/shared/jobs
- Reports:
  - `machine_default`, `user_default`, `capabilities`
  - `job_request` (what Terabooth requests)
  - `job_level` with `available=false` because no job was submitted
  - `blockers`, `ready`, flat user-facing fields
- Does not print or modify any queue.

### Fail-closed adapter (`app/printer.py`)

`WindowsSpoolerPrinter.submit` now calls preflight first and refuses to invoke
PowerShell if:

- preflight is unavailable;
- queue/driver/status is not Normal;
- machine or user ticket is not PR_4x6 / Portrait / Option1 (300×300) /
  CUT_STANDARD;
- required capabilities are absent.

This is a **safety block**, not an inferred success.

### Print script (`scripts/print_image.ps1`)

Calls the same preflight before opening/printing the image. Direct execution of
the print script cannot bypass the gate. It still sets 4×6 page geometry,
portrait orientation, zero margins and full-page draw.

The script does not blindly set CUT_2INCH; standard cut is required by the gate.

### Safe defaults

- `run_windows.ps1` now defaults to **mock**, not spooler.
- `config.py` default mode remains mock; default queue is **DS-RX1**.
- Added `.env.example` with mock and DS-RX1.
- Existing `.env` is still authoritative and is **not modified**.

### Job safety

Preserved:
- idempotency keys;
- explicit reprint only;
- no automatic resubmit after restart;
- queued/printing recovery policy;
- `unknown` completion after spooler acceptance;
- one print orchestration at a time;
- no physical completion claim.

---

## 3. Configuration enforcement

| Setting | Required | Current runtime |
|---|---|---|
| Media | PR_4x6 | Machine PC / user PR_4x6 → **blocked** |
| Orientation | Portrait | both Portrait |
| Resolution | 300×300 (Option1) | both Option1 |
| Cut | CUT_STANDARD | user CUT_2INCH / machine CUT_STANDARD → **blocked** |
| Queue | DS-RX1 | DS-RX1 |
| Driver | DNP | Dai Nippon Printing DS-RX1 |
| Port | USB001 | USB001 |
| Status | Normal | Normal |
| Jobs | 0 | 0 |
| Mode | mock | mock |

Because both machine and user tickets must be safe, the current runtime would be
blocked. This is intentional until the operator aligns both tickets.

### Effective job-level vendor enforcement

`System.Drawing.Printing.PrintDocument` does not expose a supported API for the
DNP vendor cut feature. No job is submitted to inspect an effective per-job
ticket. Therefore:

- job-level effective settings remain **unknown/unavailable**;
- no code claims they are enforced;
- the spooler path is fail-closed unless both visible tickets match the desired
  configuration.

If the driver cannot reliably honor the safe ticket, the correct behavior is a
preflight blocker, not a fabricated success.

---

## 4. Tests

```text
Windows Bridge tests: 69 passed
```

Coverage includes:
- queue default DS-RX1;
- mock default;
- fail-closed preflight unavailable;
- media/cut blockers;
- machine/user/job source normalization;
- spooler subprocess never called when not ready;
- mock `/v1/printers` preflight;
- existing idempotency, timeout, restart, auth and print-job tests.

No physical print test was run. No spooler queue was modified.

---

## 5. Remaining blocker before physical print

1. On Windows, align **both** machine and per-user DNP tickets:
   - media PR_4x6
   - portrait
   - 300×300
   - CUT_STANDARD (not CUT_2INCH)
2. Fix Windows `.env` queue override:
   ```dotenv
   TERABOOTH_PRINTER=mock
   TERABOOTH_PRINTER_NAME=DS-RX1
   ```
3. Sync the changed Bridge code/scripts to the Windows runtime.
4. Run the new preflight and verify `ready=true`.
5. Only after explicit authorization, change mode to `spooler` and make one
   physical calibration print.
6. Visually verify 4×6 output and standard cut before production use.

No automatic restart or Windows setting change was performed.

---

## 6. Safety confirmation

| Check | Result |
|---|---|
| Physical print submitted | **NO** |
| `test_print.ps1` executed | **NO** |
| Spooler enabled | **NO — mock** |
| Queue/jobs modified | **NO** |
| Printer preferences changed | **NO** |
| Auth/idempotency disabled | **NO** |
| Camera/Cascable changed | **NO** |
| Secrets exposed | **NO** |
| MockPrinter default | **YES** |

**Stopped before physical printing. Awaiting Windows ticket alignment and explicit
operator authorization.**
