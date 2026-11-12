# Phase 2C — Windows Bridge Deployment & DNP Physical Validation

> **STATUS: BLOCKED — WINDOWS RUNTIME AND DNP WERE NOT AVAILABLE.**
> No Windows execution, Windows mock-printer HTTP test, DNP print, physical cut or 20-print run was performed.
> Do not treat this report as Windows/DNP validation.

---

## 1. Evidence of blocker

The actual Windows event PC was not reachable on the event LAN.

| Check | Result |
|---|---|
| Mac LAN | `192.168.8.105` on `en0`; gateway `192.168.8.1` |
| Documented bridge host `192.168.8.50` | ARP **incomplete**; no ICMP reply |
| Probe of likely LAN hosts | Only router and unrelated devices responded; no identified Windows host |
| `192.168.8.114` | ICMP reply, but TCP **445**, **3389** and **8787** closed/unreachable; not identified as the event PC |
| Windows credentials/remote session | Not available |
| DNP DS-RX1HS | Not available |
| Physical printer driver/media | Not available |

No safe conclusion about Windows health, firewall, spooler or DNP output can be made from this environment.

---

## 2. Static implementation audit

### Entry point and dependencies

- FastAPI entry point: `app.main:app`.
- Local Python: **3.11.9**.
- Requirements: FastAPI 0.162.2, Uvicorn 0.54.0, Pillow 13.0.0, qrcode 8.2, python-multipart 0.0.33, pytest 9.2.0, httpx 0.28.1.
- SQLite ledger and data directory: inspected; local tests pass.
- Composition: **1200×1800**, 300 dpi, two identical **600×1800** panels; local tests pass.

### Windows scripts

| Script | Audit result |
|---|---|
| `scripts/install_windows.ps1` | Creates venv, upgrades pip, installs requirements, creates `.env` from `..\.env.example` if absent. It prints Python version but does **not enforce** >=3.11; operator must check. |
| `scripts/run_windows.ps1` | Loads `.env`, defaults printer to spooler, warns on placeholder token/secret/mock, rejects localhost public URL, binds `0.0.0.0:8787`. Static review only. |
| `scripts/firewall.ps1` | Inbound TCP 8787, **Private profile only**; requires Administrator. Static review only. |
| `scripts/print_image.ps1` | `System.Drawing.Printing`, 4×6 paper (`400×600` hundredths), zero margins, portrait; physical driver may override. Static review only. |
| `scripts/test_print.ps1` | Calibration print path; not executed. |
| `.env.example` | Contains placeholders and default mock printer; must be edited for event. |

### Runtime paths

- `TERABOOTH_PRINTER=spooler` selects `WindowsSpoolerPrinter`.
- Spooler calls `print_image.ps1`; it reports **unknown** completion after acceptance.
- `hotfolder` archive is the stronger evidence path, but unverified.
- `mock` is **not a printer**.
- No automatic resubmission of `unknown`.
- Bridge restart does not resume in-flight background jobs.
- DNP driver page risk remains: RX1 driver is listed for Windows 7/8/10, while event PC may be Windows 11.

---

## 3. What was verified (software only)

These are **macOS/software** results, not Windows validation:

| Check | Result |
|---|---|
| `flutter analyze` | **No issues** |
| `flutter test` | **58 passed** |
| `pytest -q` | **10 passed** |
| macOS local live mock HTTP (Phase 2B) | **PASS** |
| Composition dimensions | 1200×1800, 300 dpi; two 600×1800 panels |
| QR/HMAC delivery | PASS in Phase 2B macOS mock test |

Windows status:

| Check | Status |
|---|---|
| Windows version | **NOT AVAILABLE** |
| Windows Python/venv/dependencies | **NOT TESTED** |
| Windows bridge binds 0.0.0.0:8787 | **NOT TESTED** |
| Windows `/v1/health` | **NOT TESTED** |
| Windows firewall Private-only | **NOT TESTED** |
| Windows mock-printer HTTP workflow | **NOT TESTED** |
| DNP detected/driver/media/cut | **NOT TESTED** |
| Physical 4×6/2×6 print | **NOT TESTED** |
| 20 consecutive jobs | **NOT TESTED** |

---

## 4. Required next action on the actual Windows PC

### Step 1 — Identify the PC and network

```powershell
winver
ipconfig
python --version
```

Record:
- Windows edition/version/build.
- Exact LAN IPv4 address.
- Network profile must be **Private**, not Public.
- Python 3.11+ 64-bit.

Do not use `localhost` or `127.0.0.1` in `TERABOOTH_PUBLIC_BASE_URL`.

### Step 2 — Install the bridge

```powershell
cd C:\Terabooth\terabooth-event-mvp\windows_bridge
powershell -ExecutionPolicy Bypass -File scripts\install_windows.ps1
notepad .env
```

Set placeholders to real values privately:

```dotenv
TERABOOTH_PRINTER=spooler
TERABOOTH_PRINTER_NAME=<exact Windows queue name>
TERABOOTH_API_TOKEN=<strong random token>
TERABOOTH_DELIVERY_SECRET=<strong random secret>
TERABOOTH_PUBLIC_BASE_URL=http://<windows-lan-ip>:8787
TERABOOTH_DATA_DIR=C:\Terabooth\data
```

Do not commit `.env`; do not put credentials in screenshots or reports.

### Step 3 — Firewall and start

```powershell
# Administrator
powershell -ExecutionPolicy Bypass -File scripts\firewall.ps1

# Normal PowerShell
powershell -ExecutionPolicy Bypass -File scripts\run_windows.ps1
```

Expected:
- `Printer mode: spooler / <queue>`
- `Listening on 0.0.0.0:8787`
- no placeholder/mock warnings.

From another LAN device:

```powershell
curl.exe http://<windows-lan-ip>:8787/v1/health
curl.exe -H "Authorization: Bearer <token>" http://<windows-lan-ip>:8787/v1/health
```

Expected JSON includes `service: terabooth-print`, `printer_mode: spooler`, and the LAN public URL.

### Step 4 — Windows mock-printer HTTP test first

Before DNP:

1. Set `TERABOOTH_PRINTER=mock` temporarily.
2. Restart the bridge.
3. Submit one 3-photo job from the iPad simulator with the Windows LAN URL/token.
4. Verify real HTTP job state, composition, QR page and artefacts.
5. Confirm `data\outbox\<job>.jpg` is JPEG 1200×1800 at 300 dpi.
6. Switch back to `spooler` only after mock passes.

This test **has not been performed on Windows**.

### Step 5 — DNP driver/media/cut

- [ ] DNP DS-RX1HS connected/powered; Windows detects it.
- [ ] Correct DNP driver installed; record version.
- [ ] 4×6 media loaded; confirm actual media lot.
- [ ] Driver configured for 4×6 and **2-inch cut**.
- [ ] Windows test page outside the bridge.
- [ ] `scripts\test_print.ps1` calibration print.
- [ ] Measure physical output with a ruler; verify orientation/cut/borders/colour.

Do not claim 2×6 success from the 1200×1800 JPEG alone.

### Step 6 — Physical and reliability gates

- [ ] Inspect both 2×6 strips.
- [ ] Verify correct left/right alignment and cut position.
- [ ] Verify no clipping, unintended scaling, or white borders.
- [ ] Run 20 consecutive jobs.
- [ ] Record success/failure counts, printer errors, unknown states.
- [ ] Verify duplicate submit does not print twice.
- [ ] Verify deliberate reprint creates a new job/print.
- [ ] Verify printer offline/cover/paper error handling.
- [ ] Verify unknown state never auto-resubmits.
- [ ] Restart the bridge and confirm job records persist.
- [ ] Do **not** claim in-flight job recovery unless physically tested.

---

## 5. Failures / root causes

1. **Windows PC not reachable**
   - Documented host `192.168.8.50` has incomplete ARP and no ICMP response.
   - No alternative host was identified as the event PC.
   - No Windows credentials/remote access.

2. **No DNP**
   - The printer and driver are physically unavailable in this environment.

3. **No Windows mock test**
   - Requires the actual Windows Python/runtime and a reachable 8787 listener.

4. **Static-only limitations**
   - PowerShell script parse/runtime, firewall rule, spooler driver, DNP cut and physical output remain unverified.

---

## 6. Source changes

**None.** No Windows Bridge, Flutter, camera, composition or print-geometry code was changed in Phase 2C. No temporary credentials were created or committed.

---

## 7. Cleanup and credential handling

- No Windows server was started.
- No temporary Windows credentials were created.
- No `.env` was modified or committed.
- Prior macOS mock bridge/data were already cleaned in Phase 2B.
- Port 8790 is closed; unrelated port 8787 process was untouched.
- No secrets are included in this report.

---

## 8. Remaining blockers

| Blocker | Status |
|---|---|
| Windows event PC | **BLOCKED** — not reachable |
| Windows runtime/dependencies | **NOT TESTED** |
| Windows firewall/LAN | **NOT TESTED** |
| DNP DS-RX1HS | **BLOCKED** — unavailable |
| DNP driver/media/2-inch cut | **NOT TESTED** |
| Physical 4×6 print | **NOT TESTED** |
| 2×6 cut/orientation | **NOT TESTED** |
| 20-print reliability | **NOT TESTED** |
| Canon EOS R/CascableCore | **Not in scope / not integrated** |

**No Windows or physical readiness is claimed.**
