# Phase 6D-6 — Windows DNP Deployment & Final Alignment

## Overall result

**PASS — Phase 6D-5 deployed to Windows, DNP tickets aligned, and live preflight
is ready=true.**
**Physical printing remains NOT TESTED and NOT AUTHORIZED.**

MockPrinter remains active. No print job was submitted, no spooler mode was
enabled, and no queue job was modified.

---

## 1. Deployment

| Item | Evidence |
|---|---|
| Bundle | `phase6d6c.zip` |
| SHA-256 | `1bb73f90c5b14aa8f3261f76d95f0e2ea1f5fd52807a7bcb75226f2eea158725` |
| Extraction | `%TEMP%\phase6d6c\phase6d6` |
| Copy | Contents deployed into `windows_bridge` |
| `.env` | Preserved; not in bundle |
| Database/assets/customer data | Preserved |
| Windows tests | **69 passed**, 197 warnings |
| Mac tests | **69 passed** |

The first copy attempt used the older `phase6d6b` extraction; the final
`phase6d6c` source was then copied and the complete Windows suite passed.

### Windows `.env` printer configuration

```dotenv
TERABOOTH_PRINTER=mock
TERABOOTH_PRINTER_NAME=DS-RX1
```

Expected and verified. Authentication/secrets were not printed.

---

## 2. DNP ticket alignment

The machine default was already PR4x6/Portrait/300×300/CUT_STANDARD. The per-user
ticket still had CUT_2INCH, so the supported per-user ticket helper was run:

```text
scripts\align_dnp_user_ticket.ps1 -QueueName DS-RX1
→ Per-user ticket cut updated to CUT_STANDARD
→ backup written under %TEMP%\terabooth-DS-RX1-user-ticket-*.xml
```

Final live values:

| Source | Media | Orientation | Resolution | Cut |
|---|---|---|---|---|
| Machine default | PR_4x6 | Portrait | Option1 (300×300) | CUT_STANDARD |
| Per-user | PR_4x6 | Portrait | Option1 (300×300) | CUT_STANDARD |
| Job-level | **Not inspectable without submitting** | — | — | — |

`PaperSize` remains blank in the legacy Get-PrintConfiguration field; the vendor
PrintTicket media is authoritative and reports PR_4x6.

No machine default was changed by the helper. No firmware/driver install or
spooler change occurred.

---

## 3. Live Bridge API / preflight

Standalone preflight and authenticated `/v1/printers` agree.

Summary:

```json
{
  "available": true,
  "ready": true,
  "queue_exists": true,
  "queue_name": "DS-RX1",
  "driver_name": "DS-RX1",
  "driver_manufacturer": "Dai Nippon Printing",
  "port_name": "USB001",
  "printer_status": "Normal",
  "work_offline": false,
  "shared": false,
  "media": "ns0000:PR_4x6",
  "orientation": "psk:Portrait",
  "resolution": "ns0000:Option1",
  "cut": "ns0000:CUT_STANDARD",
  "queued_jobs": 0,
  "blockers": [],
  "query_error": ""
}
```

Capabilities now populate correctly:

- media includes `ns0000:PR_4x6`
- orientation includes `psk:Portrait`
- resolution includes `ns0000:Option1`
- cut includes `ns0000:CUT_STANDARD` and `ns0000:CUT_2INCH`

Bridge API:

```json
{
  "printers": [{
    "name": "Mock Printer",
    "state": "ready",
    "mode": "mock",
    "note": "NOT a physical printer"
  }],
  "preflight": {
    "ready": true,
    "spooler_mode_enabled": false,
    "configured_queue_name": "DS-RX1",
    "queued_jobs": 0,
    "blockers": []
  }
}
```

`job_level.available=false` is intentional: no print job was submitted, so no
effective per-job ticket can be claimed.

### Restart note

A second `run_windows.ps1` attempt correctly refused to start because the existing
Bridge instance held `data\.bridge.lock`. The live API already exposes the new
Phase 6D-5 preflight schema, confirming the running process is serving the
updated code. No unrelated process was killed.

---

## 4. Fail-safe / job safety

- MockPrinter is active; spooler disabled.
- `run_windows.ps1` defaults to mock.
- Spooler submission is gated by preflight `ready=true`; otherwise it raises
  before invoking PowerShell.
- `print_image.ps1` independently runs preflight before printing.
- Standard cut is required; CUT_2INCH is not assumed.
- Idempotency, explicit reprint, restart recovery and unknown-completion semantics
  remain intact.
- No physical completion is claimed from spooler acceptance.

---

## 5. Remaining hardware-only verification

1. Explicit operator authorization for one physical 4×6 calibration print.
2. Switch to `TERABOOTH_PRINTER=spooler` only after that authorization.
3. Confirm physical dimensions/orientation/standard cut/color.
4. Confirm spooler acceptance versus actual physical completion.
5. Record firmware/media lot and printer response.

Until then, physical printing is **NOT TESTED**.

---

## 6. Safety confirmation

| Check | Result |
|---|---|
| Physical print submitted | **NO** |
| `test_print.ps1` executed | **NO** |
| Spooler enabled | **NO — mock** |
| Queue/jobs modified | **NO** |
| Machine defaults changed by helper | **NO** |
| Per-user cut changed | **YES — CUT_STANDARD via supported helper with backup** |
| Auth/idempotency disabled | **NO** |
| Camera/Cascable changed | **NO** |
| Secrets exposed | **NO** |
| MockPrinter active | **YES** |

**Stopped after ready=true preflight. Awaiting explicit physical-print
authorization.**
