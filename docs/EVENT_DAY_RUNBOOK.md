# Terabooth Event-Day Runbook

**Event:** Saturday 14 November 2026
**Topology:** Canon EOS 60D → USB → iPad (capture/review/approve) → LAN → Windows bridge → DNP DS-RX1HS; QR downloads from Windows over the same LAN.
**Internet:** not required for printing or QR. No cloud/account dependency.

> **Current status:** the iPad app is mock-camera by default; CascableCore/EOS 60D was physically validated over USB on this Mac for discovery, settings read, Live View, one shutter request and disconnect/reconnect. **iPadOS USB and image transfer remain unverified**; the EOS 60D is not listed in Cascable's official Canon compatibility table. Use this runbook only after the pre-event gates pass. Otherwise use the proven fallback rig.
>
> **Physical validation checklist:** [PHYSICAL_VALIDATION_CHECKLIST.md](PHYSICAL_VALIDATION_CHECKLIST.md)
> **Windows bridge audit:** [PHASE_1G_WINDOWS_BRIDGE_AUDIT.md](technical/PHASE_1G_WINDOWS_BRIDGE_AUDIT.md)
> **Software integration:** [PHASE_2_SOFTWARE_INTEGRATION.md](technical/PHASE_2_SOFTWARE_INTEGRATION.md)
> **Live local integration:** [PHASE_2B_LIVE_LOCAL_INTEGRATION.md](technical/PHASE_2B_LIVE_LOCAL_INTEGRATION.md)
> **Windows/DNP validation:** [PHASE_2C_WINDOWS_DNP_VALIDATION.md](technical/PHASE_2C_WINDOWS_DNP_VALIDATION.md) — **BLOCKED**
> **Operator UI:** [PHASE_2D_OPERATOR_EXPERIENCE.md](technical/PHASE_2D_OPERATOR_EXPERIENCE.md)
> **Template engine:** [PHASE_2E_TEMPLATE_ENGINE.md](technical/PHASE_2E_TEMPLATE_ENGINE.md)
> **Animated GIF:** [PHASE_2F_ANIMATED_GIF.md](technical/PHASE_2F_ANIMATED_GIF.md)
> **Initial audit:** [PHASE_2G_AUDIT.md](technical/PHASE_2G_AUDIT.md)
> **Final QA:** [PHASE_2G_FINAL_SOFTWARE_QA.md](technical/PHASE_2G_FINAL_SOFTWARE_QA.md)
> **Operational security/reconciliation:** [PHASE_2H_FINAL_REPORT.md](technical/PHASE_2H_FINAL_REPORT.md)
> **CascableCore setup:** [PHASE_3A_1_CASCABLE_SETUP.md](technical/PHASE_3A_1_CASCABLE_SETUP.md) — simulated camera PASS; EOS 60D **BLOCKED**
> **Licence/SPM evidence:** [PHASE_3A_1A_LICENCE_AND_SPM.md](technical/PHASE_3A_1A_LICENCE_AND_SPM.md)
> **EOS 60D macOS SDK validation:** [PHASE_3A_1B_CANON_60D_MAC_SDK_VALIDATION.md](technical/PHASE_3A_1B_CANON_60D_MAC_SDK_VALIDATION.md) — USB/settings/Live View/control PASS on Mac; iPad/image transfer unverified
> **iOS adapter foundation:** [PHASE_3A_2A_IOS_CAMERA_ADAPTER_FOUNDATION.md](technical/PHASE_3A_2A_IOS_CAMERA_ADAPTER_FOUNDATION.md) — compiled; physical iPad test still required
> **EOS 60D original-transfer validation:** [PHASE_3A_2B_CANON_60D_ORIGINAL_TRANSFER_VALIDATION.md](technical/PHASE_3A_2B_CANON_60D_ORIGINAL_TRANSFER_VALIDATION.md) — attempted; blocked at that time
> **EOS 60D USB preflight:** [PHASE_3A_2C_CANON_60D_USB_PREFLIGHT.md](technical/PHASE_3A_2C_CANON_60D_USB_PREFLIGHT.md) — **PASS when Cascable Studio is closed**; storage detected; no shutter
> **EOS 60D original JPEG transfer:** [PHASE_3A_2D_CANON_60D_ORIGINAL_JPEG_TRANSFER.md](technical/PHASE_3A_2D_CANON_60D_ORIGINAL_JPEG_TRANSFER.md) — **BLOCKED** (camera not enumerated; no shutter)
> **EOS 60D stable USB/capability:** [PHASE_3A_2E_EOS60D_STABLE_USB_CAPABILITY_VALIDATION.md](technical/PHASE_3A_2E_EOS60D_STABLE_USB_CAPABILITY_VALIDATION.md) — **PASS** (capability only; original transfer unverified)
> **EOS 60D single-shot original transfer:** [PHASE_3A_2F_EOS60D_SINGLE_SHOT_ORIGINAL_TRANSFER.md](technical/PHASE_3A_2F_EOS60D_SINGLE_SHOT_ORIGINAL_TRANSFER.md) — preflight-only protocol blocker
> **EOS 60D authorized single shot:** [PHASE_3A_2G_AUTHORIZED_SINGLE_SHOT_ORIGINAL_TRANSFER.md](technical/PHASE_3A_2G_AUTHORIZED_SINGLE_SHOT_ORIGINAL_TRANSFER.md) — **PARTIAL**: one shot, original CR2 received; JPEG not validated
> **EOS 60D JPEG-only single shot:** [PHASE_3A_2H_SINGLE_SHOT_ORIGINAL_JPEG_VALIDATION.md](technical/PHASE_3A_2H_SINGLE_SHOT_ORIGINAL_JPEG_VALIDATION.md) — **BLOCKED** at discovery; no shutter
> **EOS 60D capability preflight:** [PHASE_3A_2K_CLEAN_USB_CAPABILITY_PREFLIGHT.md](technical/PHASE_3A_2K_CLEAN_USB_CAPABILITY_PREFLIGHT.md) — **PARTIAL**: capability PASS; Live View cleanup error 1008
> **Live View cleanup correction:** [PHASE_3A_2L_LIVE_VIEW_LIFECYCLE_CLEANUP_CORRECTION.md](technical/PHASE_3A_2L_LIVE_VIEW_LIFECYCLE_CLEANUP_CORRECTION.md) — static correction
> **Live View hardware verification:** [PHASE_3A_2M_LIVE_VIEW_LIFECYCLE_HARDWARE_VERIFICATION.md](technical/PHASE_3A_2M_LIVE_VIEW_LIFECYCLE_HARDWARE_VERIFICATION.md) — **PARTIAL**: ordering works; termination still 1008
> **Current audit:** only the iPad A16 Simulator is connected; there is no Apple signing identity/team/profile, no physical iPad, no Windows/DNP, no guest phone/router. See [PHASE_1F_PHYSICAL_VALIDATION.md](technical/PHASE_1F_PHYSICAL_VALIDATION.md).

---

## 0. Critical go/no-go

Do not run a paid event on this stack unless all are true:

- [ ] iPad app is signed and installed; launch checked.
- [ ] EOS 60D USB capture has passed the 10-session test **if using Canon capture** — this is currently unverified/blocked; EOS 60D is not listed in Cascable's official Canon compatibility table.
- [ ] DNP 4×6 / 2×6 print test has passed.
- [ ] QR download on a guest phone with WAN off has passed.
- [ ] Windows bridge health is green and `.env` is correct.
- [ ] Signed physical validation checklist is complete (PASS/BLOCKED marked).
- [ ] Backup/fallback rig is on site.

If camera or printer gate fails, switch to the proven LumaBooth rig.

---

# A. Before the event

## A1. Windows bridge setup

1. Windows 11 updated; sleep disabled; high-performance power plan.
2. Python 3.11+ 64-bit installed (`python --version`).
3. Project copied to e.g. `C:\Terabooth\terabooth-event-mvp`.
4. Install:

```powershell
cd C:\Terabooth\terabooth-event-mvp\windows_bridge
powershell -ExecutionPolicy Bypass -File scripts\install_windows.ps1
```

5. Edit `windows_bridge\.env`:

```dotenv
TERABOOTH_PRINTER=spooler
TERABOOTH_PRINTER_NAME=DNP DS-RX1HS
TERABOOTH_API_TOKEN=<long-random-token>
TERABOOTH_DELIVERY_SECRET=<long-random-secret>
TERABOOTH_PUBLIC_BASE_URL=http://<windows-lan-ip>:8787
TERABOOTH_DATA_DIR=C:\Terabooth\data
TERABOOTH_TOKEN_TTL_HOURS=24
TERABOOTH_JOB_TIMEOUT_SECONDS=60
```

- `mock` is **not** a printer.
- If using `hotfolder`, set `TERABOOTH_HOT_FOLDER` and archive too.
- If API token is set, build iPad with the same `--dart-define`.

6. Firewall (Administrator):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\firewall.ps1
```

Windows network profile must be **Private**.

7. Start:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_windows.ps1
# Stop with Ctrl+C. The launcher enforces one instance and validates host/port/config.
# Runtime-only install (no pytest/httpx on the event laptop):
#   powershell -ExecutionPolicy Bypass -File scripts\install_windows.ps1
```

8. Health from another device:

```powershell
curl.exe http://<windows-lan-ip>:8787/v1/health
```

If token:

```powershell
curl.exe -H "Authorization: Bearer <token>" http://<windows-lan-ip>:8787/v1/health
```

Expect `service: terabooth-print`, printer state, and no localhost warning for production.

## A2. DNP printer setup

- [ ] DNP DS-RX1HS connected to Windows by USB, powered.
- [ ] DNP Windows driver installed; printer visible.
- [ ] 4×6 media/ribbon loaded; 2-inch cut enabled.
- [ ] Windows test page prints.
- [ ] Bridge calibration print:

```powershell
.\.venv\Scripts\python.exe scripts\make_test_sheet.py --out-dir data
powershell -ExecutionPolicy Bypass -File scripts\test_print.ps1
```

- [ ] Measure 4×6, two 2×6 strips, cut alignment, orientation.
- [ ] 20-print consistency test.
- [ ] Record printer name, driver version, media lot.

**No DNP result is verified until this passes.**

## A3. iPad installation

1. Xcode → Settings → Accounts; add Apple ID/team.
2. Open `ipad_app/ios/Runner.xcworkspace`.
3. Runner → Signing & Capabilities → Automatic signing → Team.
4. Keep bundle ID `com.terabooth.teraboothIpad` unless registration conflict.
5. iPad: trust Mac; enable **Developer Mode**, restart.
6. Build/install:

```bash
cd /Users/Apple/Dev/terabooth-event-mvp/ipad_app
flutter pub get
flutter devices
flutter run -d <ipad-device-id> \
  --dart-define=TERABOOTH_API_TOKEN=<same-token>
```

Release:

```bash
flutter build ipa --release \
  --dart-define=TERABOOTH_API_TOKEN=<same-token>
```

Do not install the `--no-codesign` artifact. Do not use `USE_NATIVE_CAMERA=true` until Cascable is integrated/tested.

7. First launch permissions: Camera, Files and Folders, Local Network.

## A4. Router / LAN

- [ ] iPad and Windows on the same LAN/VLAN.
- [ ] **AP/client isolation OFF** for relevant clients.
- [ ] Guest SSID (if separate) can reach Windows:8787; do not assume.
- [ ] DHCP reservation/static IP for Windows; record IP.
- [ ] WAN/internet can be disconnected without breaking local traffic.
- [ ] Firewall Private profile.

## A5. Camera USB (only if Cascable path is available)

- [ ] EOS 60D charged/AC; card inserted; JPEG Large/Fine.
- [ ] Wi-Fi disabled; PTP/default USB.
- [ ] Data USB cable direct to iPad; no unpowered hub.
- [ ] App built with `USE_NATIVE_CAMERA=true` and Cascable licence.
- [ ] 10/10 capture test passed; disconnect/background/reconnect tested.

If not all true: **do not use Canon capture**; use mock only for workflow rehearsal or fallback rig.

## A6. End-to-end test

- [ ] Create/select the event in **Events**; verify name, date, times, venue, photo count (1–4), countdown (Off/3/5/10) and photo layout.
- [ ] Configure **Branding** from Event details if the event has a logo/tagline; confirm the preview.
- [ ] Confirm event status is **Scheduled** or **Active**; draft/completed/archived events cannot start.
- [ ] Select the template and confirm the composition preview.
- [ ] Mock/native 3-photo session.
- [ ] Review + **Retake All** (individual retake is out of event scope).
- [ ] Confirm the expected photo count and countdown; use **Cancel countdown** before a capture if needed.
- [ ] Approve → bridge health/print.
- [ ] QR scan from guest phone with WAN off.
- [ ] Originals/artefact available.
- [ ] Restart bridge; confirm jobs/data persist.
- [ ] Repeat 10 sessions; 20 prints.
- [ ] Sign the hardware checklist.

---

# B. During the event

## B1. Start bridge

```powershell
cd C:\Terabooth\terabooth-event-mvp\windows_bridge
powershell -ExecutionPolicy Bypass -File scripts\run_windows.ps1
# Stop with Ctrl+C. The launcher enforces one instance and validates host/port/config.
# Runtime-only install (no pytest/httpx on the event laptop):
#   powershell -ExecutionPolicy Bypass -File scripts\install_windows.ps1
```

Keep the window open. Confirm Printer mode is `spooler`/`hotfolder`, not `mock`. Confirm health from the iPad.

## B2. Start a session

- iPad unlocked; app foreground.
- Confirm the event title/date/status/count/countdown; use **Change event** to search, filter or edit events in **Select event**.
- Use **Event details** to review session history, branding and close-out CSV.
- If an interrupted session is present, use **Review recovery** and choose Resume, Close & recover, or Cancel.
- Confirm the template; use **Change template** before capture. The template locks once photos exist.
- Enter/confirm Windows LAN URL.
- Tap **Start Session**.
- 3-second countdown per photo; guest looks at camera.

## B3. Capture / review / Retake All

- Wait for the countdown; do not tap extra shutter controls.
- After 3 photos, review.
- **Individual per-photo retake is out of scope for the 14 November event.**
- Use **Retake All**: it restarts the complete three-photo session.
- All three replacement captures must be valid; review them again before approval.
- Previous session originals remain preserved under unique filenames.
- Approve only when all 3 current photos are acceptable.

## B4. Approve / print

- Tap **Approve & Print** once.
- `202`/“Sending” is not printed; wait for the status.
- `completed/confirmed` means the adapter reported completion; for spooler, still visually confirm the physical print.
- `unknown` means inspect the printer output; do **not** tap retry first.
- QR appears when job accepted; guests can download even if print is unknown/failed.
- If available, tap **View final composition** to inspect the bridge-generated 4×6 preview.
- If **Resume** appears for an unsubmitted review, confirm it before starting a new session; approved sessions are not restored.
- If a previous submitted print job is shown offline, use **Refresh status**; never start a new session until it is reconciled or explicitly dismissed. Do not resend the job.
- GIF status is independent of print status. If ready, use **View animated GIF**; if pending, photos/strip/QR remain available. Never delay the queue for GIF generation.
- The mock printer must show **Mock print complete — no physical print**. Never hand a mock result to a guest.
- Guest tokens are redacted from access logs. Do not disable access logs or add raw token logging.
- Auto Smart Crop falls back to Fit when Vision is unavailable or no safe crop exists. Use **Adjust crop** only if the operator needs a manual correction.
- Use the copy icon beside the delivery URL to copy it for the operator/guest.
- Guests can download originals, the photostrip and, when ready, the animated GIF from the same QR page.

## B5. Printer errors

| Symptom | Action |
|---|---|
| Job failed | Check printer power/cable/driver, paper/ribbon, error panel. Fix; use reprint only after checking no output. |
| Job unknown | Inspect physical output. If blank/no print, reprint. If printed, do not reprint. |
| Printer offline | Stop approving; fix printer; resume after test print. |
| Paper out/cover | Reload; clear error; test print; reprint the affected job if not physically printed. |
| Duplicate suspected | Check output tray; do not reprint until certain. |

## B6. Safe reprint

- Reprint creates a **new physical print**.
- Only after confirming the original did not print.
- Use the app’s reprint/retry path; wait for completion; record.
- Never reprint an `unknown` job blindly.

## B7. Guest QR assistance

- Guest QR is generated only after the session is approved and the bridge accepts the print job.
- The QR must contain the LAN bridge URL, never `localhost`.
- The operator can copy, regenerate or revoke the guest link from the print screen.
- Guest gallery supports inline previews, individual originals, branded strip, GIF and a ZIP of all approved assets.
- If the phone cannot open the page, check same Wi-Fi/VLAN, AP/client isolation, Windows Firewall inbound TCP 8787 and the configured LAN URL.
- Do not read a guest URL aloud or paste it into logs; it is a bearer link.

- Guest joins the event SSID/VLAN; the bridge must be reachable at the configured LAN URL.
- Scan the QR or open `/d/<token>`; no internet or account is required.
- Scan QR; open page; download originals/strip.
- If page fails:
  - confirm guest not on an isolated guest network;
  - confirm QR host is Windows LAN IP, not localhost;
  - confirm Windows firewall/Private profile;
  - confirm iPad/Windows health.
- No internet required; do not ask guests to use mobile data.

---

# C. Emergency procedures

## C1. Camera disconnect / power-off

- Stop the session; do not continue approving unclear images.
- Reconnect camera; verify status; start a new session.
- If the camera cannot reconnect, switch to fallback rig.
- Never move EOS 60D control to Windows.

## C2. iPad app crash

- Relaunch app; enter bridge URL again if needed.
- Completed originals remain on iPad; do not fabricate missing images.
- Start a new session; if the old job was accepted, check its status/print before reprinting.
- If repeated crashes, switch to fallback rig.

## C3. Windows bridge crash

- Restart `run_windows.ps1`.
- SQLite/jobs persist. In-flight background tasks do **not** resume automatically.
- Inspect any `printing`/`unknown` job physically; reprint only if not printed.
- Reconfirm QR works after restart.

## C4. Printer offline

- Stop printing; fix power/USB/driver/media.
- Run a Windows test print.
- Reprint only jobs confirmed not printed.
- If printer cannot recover, switch to fallback print path/rig.

## C5. Network interruption

- Reconnect iPad/Windows to same LAN; confirm health.
- QR downloads depend on Windows reachability; no internet fallback.
- Do not submit repeatedly; check job status first.
- If router/AP isolation is the cause, fix router; fallback if unavailable.

## C6. Duplicate print prevention

- Tap Approve once; bridge idempotency prevents duplicate jobs for the same payload.
- Never use the same idempotency key manually; use app.
- `unknown` is not proof of failure; inspect output first.
- Reprint is a deliberate new job.
- Keep a paper log of reprints.

## C7. Manual fallback

- If camera path fails: use the proven LumaBooth rig (preferred) or explicitly agreed fallback; do not claim EOS 60D support.
- If print path fails: stop promising immediate prints; capture originals and arrange reprint/fallback.
- If QR fails: use the fallback rig's delivery method; do not add internet/cloud accounts.
- Tell the client promptly; do not hide failed prints.

---

# D. End of event

1. Stop approving new sessions.
2. Wait for current print status; inspect output.
3. Ctrl+C the bridge window; confirm it stopped.
4. Preserve `C:\Terabooth\data` (SQLite DB, job inputs, artefacts, outbox).
5. Preserve iPad originals (`events/<event>/sessions/<session>/original_*`); export/backup per policy.
6. Verify counts: sessions, images, prints, reprints; note `unknown` jobs.
7. Back up the entire data directory to a second drive.
8. Do not delete orphan/temp files manually; use recovery tools/instructions.
9. Shut down printer, Windows, iPad, camera; pack cables/media.
10. Record incidents and final printer/page counts.

### Data locations

- Windows: `TERABOOTH_DATA_DIR` (default `C:\Terabooth\data`).
- iPad: app documents `events/.../sessions/...`.
- Session metadata: `session.json`; orphan records: `orphans.json`.

### Shutdown order

iPad/guest activity → bridge Ctrl+C → printer power → Windows shutdown → iPad shutdown → camera off.

---

## Quick command reference

```powershell
# Windows
cd C:\Terabooth\terabooth-event-mvp\windows_bridge
powershell -ExecutionPolicy Bypass -File scripts\install_windows.ps1
notepad .env
powershell -ExecutionPolicy Bypass -File scripts\firewall.ps1   # admin
powershell -ExecutionPolicy Bypass -File scripts\run_windows.ps1
# Stop with Ctrl+C. The launcher enforces one instance and validates host/port/config.
# Runtime-only install (no pytest/httpx on the event laptop):
#   powershell -ExecutionPolicy Bypass -File scripts\install_windows.ps1
.\.venv\Scripts\python.exe scripts\lan_check.py 8787
.\.venv\Scripts\python.exe scripts\make_test_sheet.py --out-dir data
powershell -ExecutionPolicy Bypass -File scripts\test_print.ps1
```

```bash
# iPad
cd /Users/Apple/Dev/terabooth-event-mvp/ipad_app
flutter pub get
flutter analyze
flutter test
flutter build ios --no-codesign
# signed install: use Xcode signing, then:
flutter run -d <ipad-device-id> --dart-define=TERABOOTH_API_TOKEN=<same-token>
```

> **Windows PowerShell note:** PowerShell 5.1 aliases `curl` to `Invoke-WebRequest`; use `curl.exe` or `Invoke-RestMethod` for the health checks.

**Do not claim physical readiness until the pre-event gates and hardware checklist pass.**
