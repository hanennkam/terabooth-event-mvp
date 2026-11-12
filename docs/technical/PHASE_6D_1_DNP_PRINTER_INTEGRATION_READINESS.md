# Phase 6D-1 — DNP DS-RX1HS Windows Printer Integration Readiness

## Overall result

**PARTIAL / BLOCKED before physical print.**

The DNP printer is installed and ready in Windows, and the existing Bridge spooler
adapter can route the 1200×1800 artefact. However, two concrete configuration
mismatches remain:

1. Windows queue is named **`DS-RX1`**, while the Bridge default is
   **`DNP DS-RX1HS`**.
2. The current DNP print ticket is **6×4 / 2-inch cut disabled**, not
   4×6 / 2-inch cut enabled.

Bridge printer mode is still **mock**. No physical print was sent and no printer
queue/spooler setting was changed.

---

## 1. Actual Windows printer environment

Operator-confirmed and read-only PowerShell evidence:

| Property | Value |
|---|---|
| Physical state | Connected and ready (operator) |
| Queue name | **`DS-RX1`** |
| Driver name | **`DS-RX1`** |
| Manufacturer | **Dai Nippon Printing** |
| Driver package version | **10.0.18362.1198** (from driver PrintCapabilities namespace; `DriverVersion` encoded as `281479271874560`) |
| Port | **USB001** |
| PrinterStatus | **Normal** |
| Shared | **False** |
| WorkOffline | Not reported/false |
| Print queue jobs | None listed by `Get-PrintJob` |
| Spooler service | Not separately queried |

### Current driver ticket

From `Get-PrintConfiguration`/PrintTicket:

| Setting | Current value |
|---|---|
| Page media | **`ns0000:PC` / “(6x4)”** — 156125 × 104987 driver units |
| PaperSize field | blank |
| Orientation | Portrait |
| Resolution | 300 × 300 dpi |
| Borders | On |
| Image color matching | System |
| 2-inch cut | **`CUT_STANDARD` / Disable** |
| Color | True |
| Duplex | OneSided |
| Copies | 1 |

The driver capabilities advertise 4×6 and `CUT_2INCH`, but the active ticket does
not select them. The 2-inch cut option's UI says “Enable (Printer V.1.10 or
later)”; actual printer firmware is unverified.

---

## 2. Existing Bridge printer architecture

```text
approved JPEG / bridge job
  → process_job composes artefact.jpg (1200×1800)
  → state queued
  → printer.submit(job_id, artefact, copies)
  → printer_mode mock: MockPrinter (default)
  → printer_mode spooler: WindowsSpoolerPrinter
       → powershell scripts/print_image.ps1
       → PrintDocument 4×6, zero margins, portrait
       → Windows spooler / DNP driver
  → status: unknown until physical completion is verified
```

Verified implementation details:

- The correct composed artefact is `jobs/<job_id>/artefact.jpg`.
- `print_image.ps1` sets 4×6 page size (`400×600` hundredths of an inch), zero
  margins, portrait, and draws the whole artefact to the page.
- Copies are looped by the script.
- Submission failure is surfaced as a failed job.
- Spooler acceptance is **not** reported as completion; status is `unknown`.
- Idempotency key prevents duplicate job creation.
- Reprint is explicit and creates a new job.
- Startup recovery prevents automatic resubmission after restart.
- `MockPrinter` remains default; physical mode requires explicit
  `TERABOOTH_PRINTER=spooler`.

### Current Bridge configuration

- Printer mode: **mock** (operator-confirmed).
- Configured/default printer name: **`DNP DS-RX1HS`**.
- Actual Windows queue: **`DS-RX1`**.

If spooler mode were enabled without changing the name, `print_image.ps1` would
fail with “Printer not valid: DNP DS-RX1HS”.

---

## 3. Risks / blockers

| Risk | Severity | Evidence |
|---|---|---|
| Queue name mismatch (`DNP DS-RX1HS` vs `DS-RX1`) | **Blocker** | Windows queue list |
| Current media is 6×4 / 2-inch cut disabled | **Blocker for intended 2×6 strips** | PrintTicket |
| PaperSize blank, driver uses vendor feature | Risk | PrintConfiguration |
| Spooler completion is `unknown` | Operational risk | Adapter behavior |
| No paper/ribbon/offline status query | Operational risk | Adapter/health |
| Driver firmware for 2-inch cut unverified | Risk | Driver option text |
| Physical print not tested | Not tested | This phase |
| Bridge mode mock | Safe default | Health/config |

---

## 4. Necessary safe configuration (not applied)

These are operator/Windows changes, not code changes:

1. In the DNP driver preferences for queue **`DS-RX1`**, select:
   - media **4×6**
   - **2-inch cut enabled** (if supported by the printer firmware)
   - portrait orientation, borders/color as desired
   - 300 dpi
2. Configure the Bridge explicitly, only after approval:
   ```dotenv
   TERABOOTH_PRINTER=spooler
   TERABOOTH_PRINTER_NAME=DS-RX1
   ```
   (or rename the Windows queue, but changing the queue is not recommended.)
3. Keep `MockPrinter` as default until the operator authorizes a physical test.
4. Record driver version, media lot, firmware and physical output.

No Windows `.env` or printer setting was changed in this phase.

---

## 5. Automated validation

```text
Windows Bridge tests: 61 passed
Unauthenticated /v1/health: HTTP 401 (authentication enforced)
```

No printer adapter code changes were necessary. No physical print command was
executed, no queue job was changed, and the spooler was not cleared.

---

## 6. Exact remaining blockers to a first physical print

1. Set the queue name and media/2-inch cut configuration above.
2. Obtain explicit operator authorization for one physical 4×6 calibration
   print.
3. Verify the physical output (dimensions, orientation, border/cut, color).
4. Only then enable spooler mode for production testing.

**Stopped before any physical print operation. Awaiting explicit operator
authorization.**
