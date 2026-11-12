# Phase 6D-2 — DNP DS-RX1HS Configuration Alignment & Print Preflight

## Overall result

**PARTIAL — repository queue default and preflight are aligned; Windows driver
media remains unaligned and was not changed.**

MockPrinter is still active. Spooler mode is disabled. No print job was
submitted, no physical print occurred, and no spooler/queue job was modified.

---

## 1. Before / after configuration

| Item | Before | After (repository) |
|---|---|---|
| Bridge default queue | `DNP DS-RX1HS` | **`DS-RX1`** |
| `run_windows.ps1` default | `DNP DS-RX1HS` | **`DS-RX1`** |
| `test_print.ps1` default | `DNP DS-RX1HS` | **`DS-RX1`** |
| Printer mode | `mock` | **`mock`** (unchanged) |
| Spooler enabled | No | **No** |
| Authentication | Bearer token | **Unchanged** |
| Actual Windows `.env` queue | Must be checked by operator | **Not modified from Mac** |

The queue name remains configurable through `TERABOOTH_PRINTER_NAME`.

---

## 2. Actual Windows printer evidence

From read-only Windows PowerShell commands:

| Property | Value |
|---|---|
| Queue | `DS-RX1` |
| Driver | `DS-RX1` |
| Manufacturer | Dai Nippon Printing |
| Driver package | `10.0.18362.1198` (capabilities namespace) |
| Port | `USB001` |
| PrinterStatus | `Normal` |
| Shared | False |
| Queue jobs | None |
| Current media option | `ns0000:PC` / “6x4” |
| PaperSize field | blank |
| Orientation | Portrait |
| Resolution | 300×300 dpi |
| Cut option | `CUT_STANDARD` / Disabled |
| Color | True |

Driver capabilities advertise **PR (4x6)**, **PR (4x6) x 2** and
**CUT_2INCH**, but the active PrintTicket is still 6×4 with cut disabled.
Firmware support for CUT_2INCH remains unverified.

**The Windows driver media was not changed.** This requires an operator in the
DNP printer preferences.

---

## 3. Preflight implementation

Added a read-only Windows preflight:

- `scripts/printer_preflight.ps1` queries:
  - queue existence/name
  - driver name, manufacturer, encoded version
  - port
  - PrinterStatus / WorkOffline / shared
  - PaperSize and selected vendor media feature
  - orientation, resolution and cut feature
  - queued job count
- `app.printer.printer_preflight(settings)` runs it only on Windows.
- Existing authenticated `GET /v1/printers` now returns:

```json
{
  "printers": ["<adapter health>"],
  "preflight": {
    "available": true/false,
    "configured_queue_name": "DS-RX1",
    "spooler_mode_enabled": false,
    "queue_exists": true/false,
    "queue_name": "...",
    "driver_name": "...",
    "driver_manufacturer": "...",
    "driver_version": "...",
    "port_name": "...",
    "printer_status": "...",
    "work_offline": false,
    "paper_size": "...",
    "media": "...",
    "orientation": "...",
    "resolution": "...",
    "cut": "...",
    "queued_jobs": 0,
    "query_error": "..."
  }
}
```

- No token, secret, customer data or queue job details are returned.
- No print or queue mutation is performed.

On the Mac test host, the preflight correctly reports:

```text
available=false
configured_queue_name=DS-RX1
spooler_mode_enabled=false
query_error=Windows PowerShell preflight unavailable on this host
```

The new preflight was not executed on the Windows host in this phase because the
updated repository/script has not been synced there. Actual Windows fields above
come from the preceding read-only PowerShell inspection.

---

## 4. Correct 4×6 media selection

Intended settings for the existing 1200×1800 portrait artifact:

- Paper/media: **4×6 / PR (4x6)** — not the current `PC` 6×4 selection.
- Orientation: **Portrait**
- Resolution: **300×300 dpi**
- Margins/borders: operator decision; current Borders=On.
- 2-inch cut: **leave disabled** unless the intended template requires it and
  firmware support is verified.

The driver's `PC` option is 6×4 landscape dimensions; `PR_4x6` is the appropriate
4×6 media. The print script already sets a 4×6 page and draws the portrait
artifact, but the driver's current ticket may override/rotate or apply the wrong
paper feature.

**Do not change CUT_2INCH** until the template and firmware are validated.

---

## 5. Regression

```text
Windows Bridge tests: 63 passed
Mock mode: active
Spooler mode: disabled
Physical print: none
Queue jobs modified: none
Authentication: unchanged
```

New tests:

- Preflight default queue is `DS-RX1`.
- Preflight reports `spooler_mode_enabled=false` in mock mode.
- `/v1/printers` exposes `preflight` without activating the spooler.

No camera/Cascable changes.

---

## 6. Remaining blockers

1. Windows `.env` may still override the queue with old
   `DNP DS-RX1HS`; verify/set:
   ```dotenv
   TERABOOTH_PRINTER_NAME=DS-RX1
   TERABOOTH_PRINTER=spooler   # only when explicitly authorized
   ```
2. DNP driver media is currently **6×4 / cut disabled**; operator must select
   **4×6 / portrait / 300 dpi** in the DNP preferences and rerun preflight.
3. Firmware support for 2-inch cut is unverified; leave cut disabled unless
   required.
4. No physical print calibration has occurred.
5. Spooler completion is `unknown` until an operator verifies physical output.
6. The updated preflight script must be synced to the Windows runtime and
   exercised there.

**Stopped before any physical print. Awaiting operator configuration and
explicit print authorization.**
