# Terabooth Event MVP — Implementation Log

> **Phase 0 historical log.** Current Phase 1A.1 status: Xcode 26.6 and CocoaPods 1.17.0 installed; iOS 26.5 platform runtime missing; `flutter build ios` still blocked. See `../../docs/IMPLEMENTATION_LOG.md` and `CAMERA_SPIKE_REPORT.md` §9.

> Concise, timestamped log. Status labels: **IMPLEMENTED** (code exists), **TESTED** (automated test), **VERIFIED** (physical hardware), **UNVERIFIED** (no hardware).
> No feature is marked VERIFIED without actual hardware evidence.

---

## 2026-11-09 — Phase 0: environment

- macOS 26.5.1 arm64; Flutter 3.44.1 stable; Dart 3.12.1.
- `flutter doctor`: Xcode incomplete; CocoaPods missing; no iPad/iPhone; Android cmdline-tools missing.
- Python 3.11.9; FastAPI/Uvicorn/Pillow/pytest available; qrcode installed in project venv.
- No Canon EOS R, DNP DS-RX1HS, Windows machine, guest phones or router attached.
- New workspace created at `/Users/Apple/Dev/terabooth-event-mvp` (was absent).

## 2026-11-09 — Phase 0: camera feasibility

- Canon EDSDK: Windows/macOS/Linux only — **no iOS**; not usable on iPad.
- Canon CCAPI: network/Wi-Fi API; iOS supported by Canon, but not a USB cable API; EOS R CCAPI support unconfirmed.
- iOS USB: ExternalAccessory requires MFi; iPadOS DriverKit exists but a custom Canon PTP driver is not feasible for the event.
- CascableCore: third-party commercial SDK; EOS R listed as USB-supported on iPad; 30-day evaluation; requires licence, native Swift/ObjC wrapper, Xcode and physical test.
- **G0: NO-GO current; CONDITIONAL GO via CascableCore only.** Gate remains physically UNVERIFIED.
- Document: `docs/technical/CANON_EOS_R_IPAD_FEASIBILITY.md`.

## 2026-11-09 — Phase 0: architecture and plan

- Topology corrected: iPad owns camera; Windows is print/delivery companion only.
- Documented: `MVP_ARCHITECTURE.md`, `IMPLEMENTATION_PLAN.md`.
- API, job states, 2×6 composition, QR delivery, failure handling, gates defined.

## 2026-11-09 — Phase 1: fresh projects

- Flutter iOS project created at `ipad_app/` (`flutter create --platforms=ios`).
- Dependencies added: `http`, `path_provider`, `crypto`, `qr_flutter`.
- Python bridge created at `windows_bridge/` with venv, FastAPI/Uvicorn/Pillow/qrcode/pytest/httpx.
- Requirements pinned to installed versions.

## 2026-11-09 — Phase 1/3: Python bridge

- Implemented:
  - `GET /v1/health`, `GET /v1/printers`.
  - `POST /v1/print-jobs` multipart; auth; SHA-256 validation; image size/dimension checks; idempotency.
  - SQLite ledger: sessions/images/jobs/attempts/delivery tokens.
  - 2×6 composition: 1200×1800 canvas; two 600×1800 panels; 300 dpi JPEG.
  - Print adapters: `MockPrinter`, `HotFolderPrinter`, `WindowsSpoolerPrinter` + PowerShell script.
  - Job states: received → validated → composing → queued → printing → completed/failed/unknown.
  - `POST /v1/print-jobs/{id}/reprint` new job with `reprint_of`.
  - QR delivery: `/d/{token}`, original, strip, QR PNG; HMAC token; TTL.
- **TESTED:** `pytest -q` → **8 passed** (API flow, duplicate suppression, reprint, hash rejection, failure, unknown, expired/invalid token, composition dimensions).
- **UNVERIFIED:** Windows spooler/DNP physical print, HFP archive behaviour, 2×6 cut/orientation.

## 2026-11-09 — Phase 1/2: Flutter iPad app

- Implemented:
  - Welcome (event branding, bridge URL, camera label, Start).
  - Capture (3-photo countdown, progress, thumbnails).
  - Review/retake/approve.
  - Print status (honest state mapping) + QR display.
  - Local original storage (atomic write, per event/session).
  - Bridge client (multipart, idempotency, status, reprint).
  - `MockCameraService` generating labelled 1200×1800 simulated images.
  - `CascableCameraService` placeholder that throws — no fake EOS R capture.
- **TESTED:** `flutter analyze` → no issues; `flutter test` → **6 passed** (widget label, mock camera, storage, bridge client, controller flow).
- **UNVERIFIED:** iOS build/run, real EOS R capture, bridge over iPad LAN, guest QR on phone.

## 2026-11-09 — live bridge smoke (macOS)

- Started Uvicorn on `127.0.0.1:8788` (8787 occupied by an unrelated local process).
- `GET /v1/health` → 200, mock printer ready.
- `POST /v1/print-jobs` with 3 JPEGs → 202; job reached `completed` / `confirmed`.
- `GET /d/{token}` → 200 HTML; `/strip` → 200 JPEG; `/qr.png` → 200 PNG; `/artefact` → 200.
- **Note:** mock printer only; no physical DNP print.

## 2026-11-09 — iOS build attempt

- `flutter build ios --no-codesign` → **failed**: "Application not configured for iOS" / Xcode incomplete. Full Xcode + CocoaPods are required.
- No iOS binary exists. iPad deployment is blocked by the environment, not by code.

---

## Current status matrix

| Item | Status |
|---|---|
| Fresh workspace | Created |
| Flutter app code | IMPLEMENTED / TESTED (Dart tests) |
| Python bridge | IMPLEMENTED / TESTED |
| Mock camera | IMPLEMENTED / TESTED / clearly simulated |
| Real EOS R capture | **NOT IMPLEMENTED / UNVERIFIED** |
| iOS build | **BLOCKED** (no Xcode/CocoaPods) |
| iPad local storage | IMPLEMENTED / TESTED (unit) |
| Bridge transfer client | IMPLEMENTED / TESTED (mock HTTP) |
| 2×6 composition | IMPLEMENTED / TESTED (dimensions) |
| Windows/DNP print | **CODE PATH ONLY / UNVERIFIED** |
| QR delivery server | IMPLEMENTED / TESTED (macOS HTTP) |
| Guest phone QR | **UNVERIFIED** |
| Physical cut/orientation | **UNVERIFIED** |

---

## Blockers

1. **Full Xcode absent** — no iOS build/deployment.
2. **CocoaPods absent** — plugins/native integration blocked.
3. **No iPad/EOS R** — G0 cannot be physically tested.
4. **No CascableCore licence** — cable integration not started.
5. **No Windows/DNP** — physical print path unverified.
6. **No guest phones/router** — QR phone test unverified.

## Next actions

1. Install Xcode + CocoaPods; verify `flutter doctor -v`.
2. Obtain CascableCore evaluation; build the Swift plugin spike; test EOS R USB capture.
3. Move the bridge to the Windows machine; run the spooler/HFP print probe.
4. Test QR on iPhone + Android over the event router with WAN unplugged.
5. Run the dress rehearsal; if any gate fails, use the proven rig.
