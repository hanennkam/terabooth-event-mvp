# Terabooth Windows Print Bridge

FastAPI + SQLite + Pillow print bridge for the Terabooth event MVP.

## What it does

- Receives 3 approved JPEGs + metadata from the iPad over local HTTP.
- Validates auth, hashes, dimensions and counts.
- Persists sessions/images/jobs in SQLite.
- Composes two identical 2×6 strips on a 4×6 canvas (1200×1800 at 300 dpi).
- Submits to a printer adapter:
  - `mock` — writes the artefact to `data/outbox/`; **not a real printer**.
  - `spooler` — PowerShell `System.Drawing.Printing`; **unverified on Windows/DNP**.
  - `hotfolder` — DNP Hot Folder Print; **unverified**.
- Tracks honest states and completion confidence.
- Serves QR guest downloads over LAN.

## Run (macOS development)

```bash
python3 -m venv .venv
./.venv/bin/pip install -r requirements.txt
./.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8787
```

Health:

```bash
curl http://127.0.0.1:8787/v1/health
```

Tests:

```bash
./.venv/bin/pytest -q
```

## Windows event setup

1. Install Python 3.11+ (64-bit).
2. Create venv and `pip install -r requirements.txt`.
3. Install the DNP DS-RX1HS Windows driver and configure 4×6 media + 2-inch cut.
4. Print a Windows test page and a 4×6 photo outside the bridge first.
5. Copy `.env.example` to `windows_bridge\.env` (or run `scripts\install_windows.ps1`, which creates it if missing). `run_windows.ps1` loads `.env`. Edit:

```dotenv
TERABOOTH_PRINTER=spooler
TERABOOTH_PRINTER_NAME=DNP DS-RX1HS
TERABOOTH_API_TOKEN=<random-token>
TERABOOTH_DELIVERY_SECRET=<long-random-secret>
TERABOOTH_PUBLIC_BASE_URL=http://192.168.8.50:8787
TERABOOTH_DATA_DIR=C:\Terabooth\data
```

6. Start (loads `.env`, binds LAN):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_windows.ps1
```

If you set `TERABOOTH_API_TOKEN`, build the iPad app with the same `--dart-define=TERABOOTH_API_TOKEN=...`; otherwise the iPad receives 401.

7. Add a Windows Firewall inbound rule for TCP 8787 on the **Private** profile.
8. Reserve a static IP/DHCP reservation for the Windows machine.
9. Run one print through `scripts/print_image.ps1` directly before using the API.

### DNP Hot Folder Print alternative

If the spooler path is unreliable on Windows 11, configure DNP HFP with a `4x6` folder and 2-inch cut, then:

```powershell
$env:TERABOOTH_PRINTER="hotfolder"
$env:TERABOOTH_HOT_FOLDER="C:\DNP\HFP\4x6"
$env:TERABOOTH_HOT_FOLDER_ARCHIVE="C:\DNP\HFP\archive"
```

The bridge copies the strip into the hot folder and watches the archive. This path is **unverified** until tested with the actual printer.

## API

See `docs/technical/MVP_ARCHITECTURE.md` §3.3. Key rules:

- `POST /v1/print-jobs` requires `Idempotency-Key`; duplicate returns the existing job.
- `202 Accepted` is not “printed”.
- `GET /v1/print-jobs/{id}` returns `state` + `completion` (`confirmed|assumed|unknown`).
- `POST /v1/print-jobs/{id}/reprint` creates a new job.
- Guest links are `/d/{token}`; never use `localhost` in a QR.
- `unknown` jobs are never auto-resubmitted.

## Known limitations

- The macOS mock printer does **not** prove Windows/DNP compatibility.
- The spooler PowerShell script is a best-effort adapter; physical completion is `unknown` until the operator verifies the print.
- No physical 2×6 cut/orientation test has been performed.
- The QR page has been smoke-tested via local HTTP only; no guest phone has been tested.
