# Phase 6F — DNP Job-Level Media, Orientation & Cutter Control

## Overall result

**PASS for implementation and automated/preflight readiness.**
**Physical print remains BLOCKED / NOT AUTHORIZED.**

The legacy `PrintDocument` path was replaced with a Windows XPS job that carries
an explicit per-user PrintTicket, a 4×6 portrait FixedPage, and a captured
job-config sidecar. MockPrinter remains active; spooler is disabled.

No physical print was submitted in this phase.

---

## 1. Confirmed root cause

Phase 6E physically proved:

- machine/user tickets both reported PR_4x6 / Portrait / 300×300 / CUT_STANDARD;
- preflight reported ready;
- the actual print was rotated 90°, split across panels and cut into two 2×6
  pieces.

The old path used `System.Drawing.Printing.PrintDocument`, which applies page
geometry but does not expose a supported DNP vendor `DocumentCUTTERCONTROL`
setting. The actual spool job therefore used driver/DEVMODE behaviour not
represented by the visible PrintTicket preflight.

`Get-PrintConfiguration` / `PrintQueue` defaults alone cannot prove effective
job-level cut/orientation.

---

## 2. Chosen implementation

### Windows XPS + explicit PrintTicket

The supported Windows spooler path now uses:

```text
1200×1800 JPEG
  → print_xps.ps1
  → 4×6 FixedPage (384×576 at 96 XPS DPI)
  → Image Stretch=Uniform (no rotation/stretch/crop)
  → per-user PrintTicket:
       media PR_4x6
       orientation Portrait
       resolution Option1 (300×300)
       cut CUT_STANDARD
  → XpsDocumentWriter.Write(page, ticket)
  → Windows spooler / DNP driver
```

Why this approach:

- It is a documented Windows print API (`XpsDocumentWriter.Write` with an
  explicit `PrintTicket`), not an undocumented DEVMODE offset.
- It applies a ticket at the job submission call rather than relying only on
  machine/user defaults.
- It gives an explicit page geometry and image placement.
- No vendor SDK or DNP Hot Folder installation is required for this path.
- Unsupported/missing ticket capabilities fail closed.

The following were not used:

- guessed DEVMODE offsets;
- CUT_2INCH;
- machine/user preference edits from code;
- DNP SDK/HFP (not installed/available for this implementation).

---

## 3. Code changes

- `scripts/print_xps.ps1` — new job-level XPS backend.
- `scripts/print_image.ps1` — delegates to the XPS backend (legacy entrypoint
  retained for compatibility).
- `app/printer.py`:
  - `WindowsSpoolerPrinter` invokes `print_xps.ps1` with `-Sta`.
  - captures `print_job_config.json` next to the job.
  - requires preflight `ready=true` and `job_level.available=true`.
  - never claims physical completion; status remains `unknown`.
- `scripts/printer_preflight.ps1`:
  - reports machine default, per-user ticket, capabilities and job-level support.
  - `physical_ready=false`.
  - `job_level.available` reflects XPS/ReachFramework availability.
  - `effective_settings_verified=false` until a job is physically calibrated.
- Tests cover the XPS backend, page geometry, explicit cut validation, fail-closed
  behavior and job-level availability.

### Job configuration capture

Each submitted job writes:

```text
data/jobs/<job_id>/print_job_config.json
```

It records:

- mechanism `XpsDocumentWriter+explicit_PrintTicket`
- queue
- image path
- 4×6 page / 384×576 page units
- Portrait / 300×300 / PR_4x6 / CUT_STANDARD
- ticket source and selected ticket values
- `effective_job_settings_verified=false`
- `physical_calibrated=false`

No token or customer delivery secret is written there.

---

## 4. Preflight behavior

Live Windows preflight after deploying the XPS backend:

```json
{
  "ready": true,
  "physical_ready": false,
  "configuration_ready": true,
  "queue_name": "DS-RX1",
  "driver_name": "DS-RX1",
  "driver_manufacturer": "Dai Nippon Printing",
  "port_name": "USB001",
  "printer_status": "Normal",
  "media": "ns0000:PR_4x6",
  "orientation": "psk:Portrait",
  "resolution": "ns0000:Option1",
  "cut": "ns0000:CUT_STANDARD",
  "queued_jobs": 0,
  "machine_default": {... PR_4x6 / Portrait / Option1 / CUT_STANDARD ...},
  "user_default": {... PR_4x6 / Portrait / Option1 / CUT_STANDARD ...},
  "capabilities": {... PR_4x6 ... CUT_STANDARD ...},
  "job_level": {
    "available": true,
    "mechanism": "XpsDocumentWriter + explicit per-user PrintTicket",
    "requested_media": "PR_4x6",
    "requested_orientation": "Portrait",
    "requested_resolution": "300x300",
    "requested_cut": "CUT_STANDARD",
    "effective_settings_verified": false,
    "physical_calibrated": false
  },
  "blockers": []
}
```

`ready=true` means **configuration preflight is ready**, not physical
verification. `physical_ready` remains false and no physical pass is claimed.

---

## 5. Tests and deployment

```text
Mac Bridge tests: 72 passed
Windows Bridge tests: 72 passed
Windows preflight: PASS (configuration_ready=true, physical_ready=false)
```

Deployed bundle:

```text
phase6f_xps.zip
SHA-256 f91913029131305a9b026060c59c26bc1d7a29fe70a93380106630915e849b04
```

Deployment preserved `.env`, data, authentication and customer records.

---

## 6. Remaining hardware verification

Required after explicit operator authorization:

1. Start a temporary spooler-mode Bridge only.
2. Submit exactly one 4×6 calibration print through the new XPS backend.
3. Confirm one uncut 4×6 sheet, portrait orientation, no split, correct scaling.
4. Confirm physical completion separately from spooler acceptance.
5. Inspect `print_job_config.json` and the final ticket/scaling.
6. Restore mock immediately; no automatic retry.

Until then: **physical job-level cut/orientation is unverified**.

---

## 7. Safety confirmation

| Check | Result |
|---|---|
| Physical print submitted | **NO** |
| Production spooler | **disabled — mock** |
| Printer defaults/queue modified | **NO** |
| Driver/firmware changed | **NO** |
| Authentication/idempotency disabled | **NO** |
| Customer data changed/deleted | **NO** |
| Camera/Cascable changed | **NO** |
| Secrets exposed | **NO** |
| MockPrinter default | **YES** |

**Stopped before physical printing. Awaiting explicit authorization for one
XPS-backed calibration.**
