# Phase 6D-4A — Windows Bridge Configuration Refresh

## Overall result

**PASS — Windows `.env` queue name aligned to `DS-RX1`, the Bridge was
restarted with the existing supported launcher, and the Phase 6D-2 preflight
is now live.**

MockPrinter remains active. Spooler mode is disabled. No print job was
submitted, no physical printer command was executed, no Windows printer
preference or queue setting was changed, and no token or secret was exposed.

The DNP driver media remains `6x4 / cut disabled`; that operator-side change is
still outstanding from Phase 6D-2.

---

## 1. Discovery summary

Actual repository source and the latest reports were treated as the source of
truth. Key findings before the change:

| Item | Observed |
|---|---|
| Bridge printer architecture | iPad → LAN upload → Windows Bridge → mock/spooler/hot-folder adapter |
| Repository default queue | `DS-RX1` (`app/config.py`) |
| Phase 6D-2 preflight code | Present in repository; `GET /v1/printers` returns `preflight` |
| Running production Bridge | Port `8787`, started **17:47**, old process **without** the preflight response |
| Windows `.env` | `TERABOOTH_PRINTER=mock`, `TERABOOTH_PRINTER_NAME=DNP DS-RX1HS` |
| Actual Windows queue | `DS-RX1` (driver `DS-RX1`, port `USB001`, status `Normal`) |
| Spooler mode | Disabled (`mock`) |

### Missing report / documentation differences

1. **`PHASE_6D_3_WINDOWS_RUNTIME_PREFLIGHT.md` is absent** from
   `docs/technical/`; only Phase 6D-1 and 6D-2 exist. The findings attributed
   to Phase 6D-3 were confirmed directly against the running host.
2. `scripts/run_windows.ps1` defaults to `TERABOOTH_PRINTER=spooler` when the
   variable is unset, whereas `README.md` and `app/config.py` describe `mock`
   as the default. The explicit `.env` value keeps the effective mode `mock`.
   This discrepancy was **not changed** in this phase.
3. `.env.example` still documents `TERABOOTH_PRINTER_NAME=DNP DS-RX1HS`, while
   the repository default is now `DS-RX1`. Not changed in this phase.

An additional mock Bridge instance was found listening on port `8788`
(PIDs `11952`/`14040`, started 19:28 from a separate PowerShell session). It
was **not** part of the canonical port-8787 service and was left untouched.

---

## 2. Backup

Before editing:

```text
Source: windows_bridge\.env                    (961 bytes)
Backup: windows_bridge\.env.phase6d4a-backup-20261112-224508.bak (961 bytes)
SHA256 source: 48340EDF8CF2A895F4B47C66313D1FA8F0C1983CF0F8EC03867BB8C8C1780D8E
SHA256 backup: 48340EDF8CF2A895F4B47C66313D1FA8F0C1983CF0F8EC03867BB8C8C1780D8E
```

The backup is ignored by `.gitignore` (`.env.*`) and contains the original
secrets; it must not be committed or shared.

---

## 3. Configuration change

Only the following changed:

| Setting | Before | After |
|---|---|---|
| `TERABOOTH_PRINTER` | `mock` | `mock` (unchanged) |
| `TERABOOTH_PRINTER_NAME` | `DNP DS-RX1HS` | **`DS-RX1`** |

Line count before/after: **24 / 24**. A line-by-line comparison shows exactly
one removed line and one added line, both being the printer-name value.

Every other setting was preserved, including API token, delivery secret,
public base URL, data directory, host, port, TTL and job timeout. Values of
secret settings were not printed.

### Effective settings (secret-free verification)

Loaded through the Bridge's own `load_dotenv` + `load_settings` path:

```text
printer_mode=mock
printer_name=DS-RX1
host=0.0.0.0
port=8787
data_dir=C:\Users\User.IZZATY\Documents\Terabooth\terabooth-event-mvp\windows_bridge\data
public_base_url=http://192.168.8.192:8787
api_token_configured=True
delivery_secret_configured=True
mock_fail=False
mock_unknown=False
```

No secret value was read into the report or shell output.

---

## 4. Running process identification

### Before restart

| PID | Parent | Role |
|---:|---:|---|
| `8248` | `6232` | `powershell -ExecutionPolicy Bypass -File scripts\run_windows.ps1` |
| `10148` | `8248` | venv `python.exe scripts/run_bridge.py` |
| `11600` | `10148` | listening `0.0.0.0:8787`; diagnostics confirmed this PID |

Launcher method: **existing supported `scripts\run_windows.ps1`**, started from
the `windows_bridge` directory. Uptime at inspection was **17,877 s**, and its
`/v1/printers` response contained only `printers` with no `preflight` object.

### Restart procedure

1. Verified the old Bridge was idle: `queue_depth=0`, `active_tasks=0`,
   `active_print=0`, `active_gif=0`, `active_zip=0`.
2. Terminated only the port-8787 process tree rooted at PID `8248`
   (`taskkill /PID 8248 /T /F`). PIDs `11952`/`14040` on port `8788` were not
   touched.
3. Confirmed port `8787` was released.
4. Relaunched the same supported launcher:
   `powershell -ExecutionPolicy Bypass -File scripts\run_windows.ps1`.
5. Redirected launcher output to `windows_bridge\data\logs\bridge-phase6d4a.out.log`
   and `.err.log`.

### After restart

| PID | Parent | Role |
|---:|---:|---|
| `7588` | `920` | `powershell -ExecutionPolicy Bypass -File scripts\run_windows.ps1` |
| `3692` | `7588` | venv `python.exe scripts\run_bridge.py` |
| `3920` | `3692` | listening `0.0.0.0:8787`; diagnostics confirms PID `3920` |

Launcher log:

```text
WARNING: TERABOOTH_PRINTER=mock: this is NOT a physical DNP printer.
Printer mode: mock / DS-RX1
```

No unrelated Python processes were stopped.

---

## 5. Post-restart verification

| Check | Result |
|---|---|
| Unauthenticated `GET /v1/health` | **HTTP 401** (authentication still enforced) |
| Authenticated `GET /v1/health` | **HTTP 200** |
| Authenticated `GET /v1/printers` | **HTTP 200** |
| Response contains `preflight` | **Yes** |
| Configured queue name | **`DS-RX1`** |
| Queue exists on Windows / name | `true` / `DS-RX1` |
| Driver | `DS-RX1`, Dai Nippon Printing, port `USB001` |
| Printer status | `Normal`, offline `false`, shared `false` |
| Spooler mode enabled | **`false`** |
| Active printer adapter | **MockPrinter**, state `ready`, note `NOT a physical printer` |
| Queue depth / active print tasks | `0` / `0` |
| Queued Windows print jobs | `0` |
| Bridge diagnostics PID | `3920` (matches port listener) |
| `query_error` | empty |

Raw preflight excerpt (secret-free):

```json
{
  "printers": [
    {
      "name": "Mock Printer",
      "state": "ready",
      "mode": "mock",
      "note": "NOT a physical printer"
    }
  ],
  "preflight": {
    "available": true,
    "queue_exists": true,
    "configured_queue_name": "DS-RX1",
    "spooler_mode_enabled": false,
    "queue_name": "DS-RX1",
    "driver_name": "DS-RX1",
    "driver_manufacturer": "Dai Nippon Printing",
    "port_name": "USB001",
    "printer_status": "Normal",
    "work_offline": false,
    "shared": false,
    "media": "ns0000:PC",
    "orientation": "psk:Portrait",
    "resolution": "ns0000:Option1",
    "cut": "ns0000:CUT_STANDARD",
    "queued_jobs": 0,
    "query_error": ""
  }
}
```

Health confirms delivery is enabled with the LAN base URL and no configuration
warnings. Mock mode is active.

---

## 6. Safety attestations

- No print job was created or submitted.
- `test_print.ps1` was **not** executed.
- `submit_dnp_e2e.py` was **not** executed.
- Spooler mode was **not** enabled.
- Windows printer preferences, queue, driver and media were **not** modified.
- Only the two intended `.env` values were touched; the printer mode remains
  `mock`.
- Authentication was not disabled or modified.
- No token, delivery secret, customer data or job content was printed in this
  report or in command output.
- The secondary port-8788 Bridge process was left running and untouched.

---

## 7. Remaining blockers / follow-ups

1. **DNP driver media is still `ns0000:PC` (6×4), portrait, with
   `CUT_STANDARD`.** Phase 6D-2 requires the operator to select the intended
   **4×6 (PR)** media in the DNP preferences and re-run preflight. This was not
   changed here.
2. **No physical print has been authorized or attempted.** `MockPrinter`
   remains the production adapter.
3. The Phase 6D-3 report is missing from the repository and should be added or
   its findings merged into the documentation.
4. The extra mock Bridge on port `8788` should be confirmed as intentional or
   stopped by the operator; it is outside the canonical port-8787 service.
5. `run_windows.ps1` still defaults to `spooler` if `TERABOOTH_PRINTER` is
   absent. Operators must keep the explicit `mock` value until spooler mode is
   authorized.
6. `.env.example` still references the old `DNP DS-RX1HS` queue name.

**Stopped after verification. No spooler activation, physical print or printer
configuration change was performed.**
