# Windows / DNP Print Bridge Readiness

> **Phase 1A status:** code audit and deployment preparation. **No Windows machine or DNP DS-RX1HS is available; no physical print has been made.**
> **Status labels:** DONE — verified · BLOCKED · READY FOR PHYSICAL TEST · NOT STARTED.

---

## 1. Audit summary

| Area | Status | Evidence |
|---|---|---|
| FastAPI service / endpoints | DONE — tested on macOS | 8 pytest tests pass |
| SQLite job ledger | DONE — tested | API + restart-independent DB |
| Multipart validation / hashes | DONE — tested | hash-mismatch test 422 |
| Idempotency / duplicate suppression | DONE — tested | duplicate returns same job |
| 2×6 composition dimensions | DONE — tested | 1200×1800, two 600×1800 panels |
| QR delivery | DONE — tested on macOS HTTP | page/strip/QR/artefact 200 |
| Mock printer | DONE — tested | success/failure/unknown |
| Windows spooler adapter | **READY FOR PHYSICAL TEST** | PowerShell script; **unverified** |
| DNP Hot Folder Print adapter | **READY FOR PHYSICAL TEST** | folder/archive watcher; **unverified** |
| Physical 4×6 print / 2×6 cut | **BLOCKED** | no Windows/DNP |
| Windows 11 driver compatibility | **BLOCKED / risk** | DNP RX1 driver listed Win7/8/10 |
| Windows service / auto-start | NOT STARTED | out of scope for MVP; Task Scheduler manual |
| Programmatic physical completion | **PARTIAL** | spooler returns `unknown`; HFP archive is evidence |

---

## 2. What the bridge does

- Receives 3 approved JPEGs + metadata from the iPad.
- Validates bearer token, SHA-256, dimensions, count and total size.
- Persists session/images/job/attempts in SQLite.
- Composes two identical 2×6 strips on a 4×6 canvas.
- Submits to the selected printer adapter.
- Exposes honest states:
  `received → validated → composing → queued → printing → completed | failed | unknown`.
- `completed` only with evidence; spooler acceptance is **not** completion.
- No automatic resubmission of `unknown`.
- Reprint creates a new job with `reprint_of`.
- QR delivery remains available after validation, even if printing fails.

---

## 3. Printer adapters review

### 3.1 Spooler (`WindowsSpoolerPrinter`)

**Implementation:** Python calls `scripts/print_image.ps1`, which uses `System.Drawing.Printing.PrintDocument`:
- Printer name from `TERABOOTH_PRINTER_NAME`.
- Margins 0.
- `PaperSize("4x6", 400, 600)` in 1/100 inch units.
- Portrait; draws the image to page bounds.
- Copies loop.

**Strengths:** uses the installed DNP Windows driver; no proprietary SDK; straightforward.

**Gaps / risks:**
- The DNP RX1 driver page lists **Windows 7/8/10**, not Windows 11. Windows 11 compatibility must be tested.
- `PrintDocument` does not return a spooler job ID here; status is reported as `unknown` until physical verification.
- Driver may override paper size/orientation; the 4×6 and 2-inch cut settings must be verified in the driver.
- The PowerShell script is **unverified** on Windows/DNP.
- No print-quality/ICC control; driver defaults apply.

**Verdict:** READY FOR PHYSICAL TEST; do not claim DNP printing.

### 3.2 DNP Hot Folder Print (`HotFolderPrinter`)

**Implementation:** copies the composed 4×6 JPEG into a configured size-named folder; watches the archive folder for the same filename.

**Strengths:** DNP HFP is officially listed for Windows 10/11 and supports DS-RX1/DS-RX1HS, 2×6 cut, multiple printers, media/status monitoring and daily archives.

**Gaps / risks:**
- HFP prints a single copy per image; multi-copy needs multiple files (MVP uses one 4×6 sheet = two strips).
- Archive timing/error semantics must be verified; exact status logs are not documented here.
- HFP must be configured for 4×6 paper and 2-inch cut.
- No programmatic API documented.

**Verdict:** READY FOR PHYSICAL TEST; keep as fallback if spooler is unreliable on Windows 11.

### 3.3 Mock (`MockPrinter`)

- Writes the composed strip to `data/outbox/`.
- Simulates completed/failed/unknown.
- **Not a printer.** Used for tests and macOS development.

---

## 4. Deployment scripts (added)

| Script | Purpose |
|---|---|
| `scripts/install_windows.ps1` | Create venv, upgrade pip, install `requirements.txt` |
| `scripts/run_windows.ps1` | Set defaults, validate LAN URL/token, start Uvicorn on `0.0.0.0:8787` |
| `scripts/firewall.ps1` | Add inbound TCP 8787 rule on Private profile (admin) |
| `scripts/test_print.ps1` | Submit the calibration sheet through `print_image.ps1` |
| `scripts/make_test_sheet.py` | Generate 4×6 calibration + 2×6 strip JPEGs |
| `scripts/lan_check.py` | Print LAN IPs and probe `/v1/health` |
| `scripts/print_image.ps1` | Windows `System.Drawing.Printing` print helper |

### Exact Windows setup

```powershell
cd C:\Terabooth\windows_bridge
powershell -ExecutionPolicy Bypass -File scripts\install_windows.ps1

$env:TERABOOTH_PRINTER="spooler"
$env:TERABOOTH_PRINTER_NAME="DNP DS-RX1HS"
$env:TERABOOTH_API_TOKEN="<random-32+ chars>"
$env:TERABOOTH_DELIVERY_SECRET="<random-long-secret>"
$env:TERABOOTH_PUBLIC_BASE_URL="http://<windows-lan-ip>:8787"
$env:TERABOOTH_DATA_DIR="C:\Terabooth\data"

# Run PowerShell as Administrator once:
powershell -ExecutionPolicy Bypass -File scripts\firewall.ps1

# Generate calibration assets:
.\.venv\Scripts\python.exe scripts\make_test_sheet.py --out-dir data

# Start:
powershell -ExecutionPolicy Bypass -File scripts\run_windows.ps1
```

Health from another device:

```powershell
curl http://<windows-lan-ip>:8787/v1/health
```

The run script refuses `localhost`/`127.0.0.1` in `TERABOOTH_PUBLIC_BASE_URL`, because guest QR codes must use the LAN IP.

---

## 5. Windows deployment checklist

### Before the event

- [ ] Windows 11 x64 laptop, fully updated.
- [ ] Python 3.11+ 64-bit installed; `python --version` works.
- [ ] `scripts\install_windows.ps1` completed.
- [ ] DNP DS-RX1HS driver installed; printer appears in Windows.
- [ ] 4×6 media loaded; 2-inch cut enabled in driver/HFP.
- [ ] Print a Windows test page **outside** the bridge.
- [ ] Print `data\test-4x6-calibration.jpg` via `scripts\test_print.ps1`.
- [ ] Measure physical output with a ruler; verify 4×6, 2×6 cut, orientation.
- [ ] Set `TERABOOTH_PUBLIC_BASE_URL` to the LAN IP; no localhost.
- [ ] Set a strong `TERABOOTH_API_TOKEN` and `TERABOOTH_DELIVERY_SECRET`.
- [ ] Firewall rule for TCP 8787 (Private) applied.
- [ ] Reserve a static IP/DHCP reservation.
- [ ] Ensure Windows sleep is disabled; power plan high performance.
- [ ] Confirm no VPN/third-party firewall blocks LAN clients.
- [ ] Start bridge; `/v1/health` returns 200 from the iPad.
- [ ] Submit one job from the iPad (mock camera acceptable only for transfer test).
- [ ] Verify QR page opens from a guest phone; WAN unplugged.

### Print test procedure

1. Generate assets:
   `.\.venv\Scripts\python.exe scripts\make_test_sheet.py --out-dir data`
2. Print:
   `powershell -ExecutionPolicy Bypass -File scripts\test_print.ps1`
3. Inspect:
   - Physical size 4×6 inches.
   - Two 2×6 strips, correct orientation (TOP arrow up).
   - Centre cut line aligns with the cut.
   - No unexpected borders/cropping/distortion.
   - Colour patches and text legible.
4. Record printer model/firmware, media lot, driver version, result.
5. Repeat 20 prints for consistency.

**Do not mark DNP printing verified until steps 2–5 are completed physically.**

---

## 6. Error handling review

| Failure | Current behaviour | Required operator action |
|---|---|---|
| Printer offline | Spooler script error → job failed; HFP timeout → unknown | Check power/cable/driver; retry |
| Paper out/cover open | Driver error → failed; exact text driver-dependent | Fix media/cover; retry |
| Ambiguous completion | `unknown`; no auto-resubmit | Inspect physical output; reprint explicitly if needed |
| Duplicate submit | Same idempotency key returns existing job | None |
| Bridge restart | SQLite persists jobs; `printing/unknown` remain | Inspect/reconcile |
| Network loss | iPad status polling fails temporarily; originals retained | Reconnect; retry status |
| QR token expired | 404 | Generate new print/job? (MVP: new job or operator decision) |
| Disk full | Python write error → job failed | Free space; check data dir |

**Gap:** no automatic physical print confirmation from the spooler. The operator must verify the output. HFP archive is stronger evidence but still requires validation.

---

## 7. DNP 2×6 assumptions to verify

- DNP DS-RX1HS accepts 4×6 media and a 2-inch cut.
- The driver/HFP cut setting is enabled and persists.
- The 4×6 canvas is 1200×1800 at 300 dpi; each strip is 600×1800.
- Two identical strips are on one sheet; cutting yields two 2×6 strips.
- Orientation: the image top is the strip top; no rotation.
- Margins: zero on the canvas; printer may impose hardware margins; verify.
- Colour: driver defaults; no ICC conversion in the MVP.

**All of the above are assumptions until measured on the actual printer.**

---

## 8. Status

| Task | Status |
|---|---|
| Audit bridge code | DONE — verified by tests |
| Fix auth/idempotency/QR gaps | DONE — tested |
| Add Windows scripts | DONE — written, not executed on Windows |
| Spooler path | READY FOR PHYSICAL TEST |
| HFP path | READY FOR PHYSICAL TEST |
| Physical DNP print | **BLOCKED** |
| 2×6 cut/orientation | **BLOCKED** |
| Windows 11 driver | **BLOCKED / risk** |

---

## 9. Sources

- DNP DS-RX1HS: <https://www.dnpphoto.com/products/printers/rx1hs>
- DNP Hot Folder Print: <https://www.dnpphoto.com/hot-folder-print>
- DNP RX1 driver (Windows 7/8/10): <https://www.dnpphoto.com/downloads/rx1-driver-for-windows-7810>
- Microsoft `PrintJobStatus`: <https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/printerextension/ne-printerextension-tagprintjobstatus>
- FastAPI: <https://fastapi.tiangolo.com/>
- Pillow: <https://pillow.readthedocs.io/>
