# Phase 6D-3 — Windows DNP Runtime Preflight Verification

## Overall result

**BLOCKED — runtime configuration is not aligned and the running Bridge does not
have the new preflight endpoint.**

Read-only evidence confirms:

- Windows queue and driver are `DS-RX1` on USB001, status Normal, zero jobs.
- The Windows `.env` still overrides with:
  - `TERABOOTH_PRINTER=mock`
  - `TERABOOTH_PRINTER_NAME=DNP DS-RX1HS`
- The active driver ticket remains **`ns0000:PC` / 6×4**, not PR_4x6.
- The running Bridge `/v1/printers` response has no `preflight` object.
- No spooler mode, print job, driver change or queue change was made.

---

## 1. Windows checkout/script

The read-only preflight script exists and ran successfully on Windows:

```text
scripts\printer_preflight.ps1
```

Actual output:

```json
{
  "available": true,
  "queue_exists": true,
  "queue_name": "DS-RX1",
  "driver_name": "DS-RX1",
  "driver_manufacturer": "Dai Nippon Printing",
  "driver_version": "281479271874560",
  "port_name": "USB001",
  "printer_status": "Normal",
  "work_offline": false,
  "shared": false,
  "paper_size": "",
  "media": "ns0000:PC",
  "orientation": "psk:Portrait",
  "resolution": "ns0000:Option1",
  "cut": "ns0000:CUT_STANDARD",
  "queued_jobs": 0,
  "query_error": ""
}
```

The first attempted hash/check command ran in `cmd.exe`, so `Get-FileHash` was
not available. The preflight script itself is present and functional. A
PowerShell file-hash comparison remains outstanding, but the live output proves
the Windows copy has the preflight script.

---

## 2. Effective Windows configuration

From `findstr /B "TERABOOTH_PRINTER" .env`:

```dotenv
TERABOOTH_PRINTER=mock
TERABOOTH_PRINTER_NAME=DNP DS-RX1HS
```

### Mismatch

The repository default was changed to `DS-RX1`, but the Windows `.env` override
still supplies the old **`DNP DS-RX1HS`**. If spooler mode were enabled now, the
printer name would not match the Windows queue.

Bridge mode remains **mock**, which is correct for this phase.

---

## 3. Driver preferences

The operator reports the DNP preferences dialog visibly shows **PC 6x4**, despite
the intended manual change to PR (4x6). The active preflight ticket independently
confirms:

```text
media: ns0000:PC
```

This is the 6×4 option, not PR (4x6). The preference change did not persist or
apply.

Current ticket details:

| Setting | Observed |
|---|---|
| Media | **PC / 6×4** |
| PaperSize | blank |
| Orientation | Portrait |
| Resolution option | Option1 = 300×300 dpi per driver capabilities |
| 2-inch cut | **CUT_STANDARD / disabled** |
| Queue jobs | 0 |
| Status | Normal |

The 2-inch cut being disabled matches the requested state. Media is not aligned.

---

## 4. Authenticated Bridge API

`GET /v1/printers` returned only:

```json
{
  "printers": [
    {
      "name": "Mock Printer",
      "state": "ready",
      "mode": "mock",
      "note": "NOT a physical printer"
    }
  ]
}
```

No `preflight` object is present. This means the currently running Bridge process
predates the Phase 6D-2 endpoint change. The code/script is present, but the
process must be safely restarted to expose it. Restart was not performed.

---

## 5. Check status

| Check | Result |
|---|---|
| Queue exists: DS-RX1 | **PASS** |
| Driver: DS-RX1 / Dai Nippon Printing | **PASS** |
| Port: USB001 | **PASS** |
| PrinterStatus: Normal | **PASS** |
| Media: PR (4x6) | **FAIL — PC 6×4** |
| Orientation: Portrait | **PASS** |
| Resolution: 300×300 | **PASS (Option1)** |
| 2-inch cut disabled | **PASS** |
| Queue jobs: 0 | **PASS** |
| Spooler mode disabled | **PASS — mock** |
| Bridge configured queue DS-RX1 | **FAIL — `.env` has DNP DS-RX1HS** |
| Bridge preflight endpoint available | **FAIL — old running process** |

---

## 6. Exact remaining actions

Operator-only, no physical print:

1. Edit Windows `windows_bridge\.env`:
   ```dotenv
   TERABOOTH_PRINTER=mock
   TERABOOTH_PRINTER_NAME=DS-RX1
   ```
   Do not enable spooler.
2. Reopen DNP `DS-RX1` preferences, select **PR (4x6)**, portrait, 300×300,
   2-inch cut disabled; click Apply/OK. Reopen the dialog to confirm it shows
   PR (4x6), not PC 6×4.
3. Rerun:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\printer_preflight.ps1 -QueueName DS-RX1
   ```
   Confirm `media` is `ns0000:PR_4x6`, not `ns0000:PC`.
4. Only if needed, restart the Bridge **preserving mock mode**, then query
   `/v1/printers` and confirm the `preflight` object appears.
5. Stop before any physical print; await explicit authorization.

---

## 7. Safety / regression

```text
Windows Bridge tests (Mac checkout): 63 passed
Bridge mode: mock
Spooler mode: disabled
Physical print: none
Print job submitted: none
Spooler/queue modified: none
Driver preferences changed by agent: none
Authentication/secrets exposed: none
```

No camera/Cascable changes.

**Stopped before physical printing. Runtime media and queue configuration remain
blocked.**
