# Phase 6E — Physical DNP Calibration & Print Verification

## Overall result

**FAIL for 4×6 standard-cut calibration.**
**One physical calibration sheet was printed; it emerged cut into two 2×6
pieces, not one uncut 4×6 sheet.**

The spooler job itself was accepted but completion remained `unknown`. No retry
was submitted. Production was restored to MockPrinter immediately.

No customer image, customer data, camera action or queue modification occurred.

---

## 1. Pre-print readiness

Before the calibration:

- Queue: `DS-RX1`
- Driver: `DS-RX1`, Dai Nippon Printing
- Port: `USB001`
- Status: Normal
- Machine and user tickets: PR_4x6 / Portrait / 300×300 / CUT_STANDARD
- Queue jobs: 0
- Bridge production mode: **mock**
- Production preflight: `ready=true`

The physical print was run through a **temporary Bridge on port 8788** with
spooler mode. Production on 8787 stayed mock throughout.

---

## 2. Calibration job

Command executed once with the project virtualenv:

```text
.\.venv\Scripts\python.exe .\scripts\calibration_print.py \
  --url http://127.0.0.1:8788 --confirm-one-print
```

The client generated a synthetic 1200×1800 JPEG containing:

- 4×6 calibration title
- eight colour bars
- border and corner registration marks
- resolution/orientation/standard-cut labels
- a synthetic-image marker

Submission result:

```text
HTTP 202
job_id=job_c8e41a6c86fd43de9fcae63eead29c15
idempotency=calibration-24f63e3f8e15
state=unknown
completion=unknown
printer_mode=spooler
error=spooler accepted; physical completion unverified
image_sha256=7445cb4d0a75fef1bb1918e6865fa6edfc770c918390deac2c02f442a65f1ddf
image=1200x1800
artefact_size=1200x1800
artefact_bytes=131756
```

Only one job was submitted. The initial failed client attempts used system Python
without `httpx` and failed **before sending a request**; they did not print.

---

## 3. Physical result

Operator observation:

- **One 4×6 sheet was cut into two 2×6 pieces.**
- No printer error was reported.
- The calibration content was produced.

This is **not** a 4×6 standard-cut PASS. The requested output was one uncut
4×6 sheet.

### What is confirmed

- Exactly one physical print job was submitted and processed.
- The page physically emerged and was cut.
- The printer did not report a mechanical error to the operator.

### What is not confirmed

- 4×6 standard cut (it failed: two 2×6 pieces).
- Spooler completion as physical completion (job remains `unknown`).
- Exact colour/alignment quality against the reference within a 4×6 uncut sheet,
  because the cut changed the physical output.

No second print was attempted.

---

## 4. Restoration and post-test state

The temporary 8788 Bridge was stopped by PID. Its temporary calibration data
directory was removed. Production 8787 was not restarted or reconfigured.

Production API after restoration:

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

Unauthenticated production `/v1/health` returned **401**, confirming
authentication remains enforced.

Temporary 8788 no longer accepts connections.

---

## 5. Root cause / remaining blocker

The Windows preflight tickets were both PR_4x6 / CUT_STANDARD, but the actual
`PrintDocument` job was cut into two 2×6 pieces. This confirms that the visible
machine/user PrintTickets and preflight did **not** reliably control the actual
job-level vendor cut behaviour.

`System.Drawing.Printing.PrintDocument` does not expose a supported job-level DNP
`DocumentCUTTERCONTROL` setting. The physical output is the authoritative result:
the DNP job cut at 2×6 despite the preflight reporting standard cut.

Do not interpret the spooler acceptance or `unknown` state as a 4×6 success.

### Required next work

- Implement a job-level DNP cut configuration path, or switch to the DNP Hot
  Folder Print/vendor-supported path that explicitly controls media and cut.
- Validate the actual DEVMODE/PrintTicket sent with the spool job, not only
  `PrintQueue` defaults.
- Keep MockPrinter as production default until an uncut 4×6 physical check
  passes.
- No further physical print without a new explicit authorization.

---

## 6. Tests

```text
Windows Bridge tests (before calibration): 69 passed
Mac Bridge tests: 69 passed
Calibration client syntax/compile: PASS
```

No automated test can validate the physical cut; the operator observation is the
authoritative evidence.

---

## 7. Safety confirmation

| Check | Result |
|---|---|
| Physical jobs submitted | **ONE** |
| Automatic retry | **NO** |
| Customer images/data | **NONE TOUCHED** |
| Production Bridge mode | **mock** |
| Production spooler enabled | **NO** |
| Production queue jobs | **0** |
| Temp Bridge | **stopped** |
| Temp calibration data | **removed** |
| Authentication | **enforced (401 unauthenticated)** |
| Camera/Cascable | **NONE** |
| Secrets exposed | **NO** |

**Stopped after the single authorized calibration attempt. No retry.**
