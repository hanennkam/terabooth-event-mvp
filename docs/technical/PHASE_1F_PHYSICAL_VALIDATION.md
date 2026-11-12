# Phase 1F — Physical Deployment & Hardware Validation Preparation

> **Preparation/documentation only.** No physical iPad, EOS R, DNP, Windows or phone operation was performed.
> **No code was changed in this phase.** CascableCore remains uninstalled.
> **Event:** Saturday 14 November 2026.

---

## 1. Current environment snapshot

| Item | Actual state |
|---|---|
| Xcode | 26.6 (17F113), `/Applications/Xcode.app/Contents/Developer` |
| CocoaPods | 1.17.0 |
| iOS runtime | iOS 26.5 simulator installed |
| Flutter | 3.44.1 / Dart 3.12.1 |
| Detected device | **iPad (A16) Simulator** (`552D64BA-85B9-4DFE-B3EA-10E24FDDCC34`) — **not physical** |
| Physical iPad | **Not connected** |
| Apple Development identity | **0 valid identities** |
| Apple team | **empty** |
| Provisioning profiles | **none** |
| Bundle ID | `com.terabooth.teraboothIpad` |
| Deployment target | **13.0** (do not raise; CascableCore not installed) |
| Camera | Mock default; CascableCore pending |
| Windows/DNP | Not available to this Mac |
| Guest phone/router | Not available |

**No physical installation or hardware validation is claimed.**

---

## 2. Signing and deployment audit

### Current Xcode settings

| Setting | Value |
|---|---|
| Workspace | `ipad_app/ios/Runner.xcworkspace` |
| Signing style | Automatic |
| Code sign identity | `iPhone Developer` |
| Team | **none** |
| Provisioning profile | **none** |
| Code signing required | yes |
| Signing identities | **0** |
| Device family | iPhone + iPad |
| Deployment target | iOS 13.0 |
| Entitlements/capabilities | none |
| Permissions | Camera, Files/Local Network, `_ptp._tcp` |

### Exact setup steps (when the iPad is present)

1. Connect the iPad to the Mac with a **data-capable USB cable**.
2. Tap **Trust This Computer** on the iPad; enter the passcode.
3. On iPad: **Settings → Privacy & Security → Developer Mode → On**, restart, confirm.
4. Open Xcode → **Settings → Accounts**.
5. Add the Apple ID (Apple menu/plus). A **Personal Team** appears if no paid team exists.
6. Open:

```bash
cd /Users/Apple/Dev/terabooth-event-mvp/ipad_app
open ios/Runner.xcworkspace
```

7. Select **Runner → Signing & Capabilities**.
8. Enable **Automatically manage signing**.
9. Select the **Team** (Personal Team is acceptable for testing).
10. Keep bundle ID `com.terabooth.teraboothIpad` unless Xcode reports it already registered by another team; only then change it in Xcode.
11. Connect/select the iPad in Xcode; wait for “Preparing device for development”.
12. Xcode will create the development certificate/profile and register the device.

### Personal Team limitations

- Free Personal Team provisioning typically expires after **7 days**.
- Sign/install close to 14 November; do not expect a free build to remain valid indefinitely.
- Device/app limits apply; only the registered iPad.
- A paid Apple Developer team is more robust, but is not claimed/available.

### Build/install commands

```bash
cd /Users/Apple/Dev/terabooth-event-mvp/ipad_app
flutter pub get
flutter devices
flutter run -d <ipad-device-id> \
  --dart-define=TERABOOTH_API_TOKEN=<API_TOKEN>
```

Release:

```bash
flutter build ipa --release \
  --dart-define=TERABOOTH_API_TOKEN=<API_TOKEN>
```

- Do not use the `--no-codesign` artifact for installation.
- Do not use `USE_NATIVE_CAMERA=true` until CascableCore/native adapter is implemented/tested.
- If no bridge token is configured, omit the `--dart-define`.

### Why this is blocked now

`flutter devices` lists only the **iPad (A16) Simulator**; there is no physical iPad, no Apple identity/team and no provisioning profile. Simulator build success is **not** physical deployment.

---

## 3. Windows Bridge deployment audit

### Runtime/dependencies

| Item | Actual |
|---|---|
| Python | 3.11.9 in project venv |
| FastAPI | 0.162.2 |
| Uvicorn | 0.54.0 |
| Pillow | 13.0.0 |
| qrcode | 8.2 |
| python-multipart | 0.0.33 |
| pytest | 9.2.0 |
| httpx | 0.28.1 |

Windows needs **Python 3.11+ 64-bit**. Dependencies are installed by `scripts/install_windows.ps1`.

### Configuration / startup

- `windows_bridge/.env` is loaded by `scripts/run_windows.ps1`; explicit process env wins.
- `install_windows.ps1` creates `.env` from `..\.env.example` if absent.
- `TERABOOTH_PRINTER`: `mock` | `spooler` | `hotfolder`; **mock is not a printer**.
- `TERABOOTH_PRINTER_NAME`: the exact Windows printer queue name; verify in Windows; do not assume.
- `TERABOOTH_API_TOKEN`: optional; if set, iPad build must use the same token.
- `TERABOOTH_DELIVERY_SECRET`: long random; signs QR tokens.
- `TERABOOTH_PUBLIC_BASE_URL`: actual Windows LAN IP; no localhost.
- `TERABOOTH_DATA_DIR`: persistent data directory (absolute recommended).
- `TERABOOTH_TOKEN_TTL_HOURS`: default 24.
- `TERABOOTH_JOB_TIMEOUT_SECONDS`: default 60.
- Spooler/HFP paths as configured; no invented values.

### Start / health / stop

```powershell
cd C:\Terabooth\terabooth-event-mvp\windows_bridge
powershell -ExecutionPolicy Bypass -File scripts\install_windows.ps1
notepad .env
powershell -ExecutionPolicy Bypass -File scripts\firewall.ps1   # Administrator
powershell -ExecutionPolicy Bypass -File scripts\run_windows.ps1

# LAN health (token only if configured)
curl.exe http://<WINDOWS_LAN_IP>:8787/v1/health
curl.exe -H "Authorization: Bearer <API_TOKEN>" http://<WINDOWS_LAN_IP>:8787/v1/health
```

- Binds `0.0.0.0:8787`.
- Firewall inbound TCP 8787 on **Private** profile.
- Ctrl+C stops; wait for current print first.
- `TERABOOTH_DATA_DIR` contains SQLite DB, inputs, artefacts; back up after event.

### Known Windows/bridge limits

- Windows scripts are not executed in this environment; static review only.
- Bridge restart does **not** resume in-flight background print tasks. Inspect and reprint manually.
- Spooler completion is reported `unknown`; operator must verify the physical print.
- DNP driver on Windows 11 and HFP behavior are unverified.
- No auto-retry of `unknown`.
- `.env` placeholder token/secret warnings must be resolved before the event.

---

## 4. Canon EOS R physical validation procedure

**Current blocker:** CascableCore evaluation/integration is pending; the app’s native path returns `CAMERA_SDK_MISSING`. **Do not run this section until the licensed adapter is implemented and a signed app is installed.**

### Preconditions

- CascableCore licence approved/installed; native adapter built into Runner.
- Signed iPad app installed.
- EOS R charged/AC; card inserted.
- Camera: **Wi-Fi disabled**, PTP/default USB, JPEG Large/Fine, auto power-off off.
- Direct data USB cable; no unpowered hub.
- iPad Settings: Camera, Files and Folders, Local Network allowed.
- App launched with `USE_NATIVE_CAMERA=true` (only after adapter exists).

### Tests

1. **USB detection**: connect; app discovers EOS R.
2. **Authorization**: wired-camera authorization prompt/status; grant.
3. **Connection**: model/transport; USB.
4. **Live view**: frames update; usable latency.
5. **Single capture**: physical shutter fires; original JPEG received.
6. **JPEG transfer**: saved file opens; dimensions/orientation correct; capture ID.
7. **Three-photo session**: existing countdown/review flow.
8. **Retake All**: restarts the complete three-photo session; all three replacements are valid; previous session originals remain preserved; review/approval work after recapture. Individual per-photo retake is out of event scope.
9. **Disconnect/reconnect**: unplug during capture/transfer and idle; no false success; reconnect or clear failure.
10. **Repeated sessions**: 10 consecutive sessions; 30 originals; restart app; no duplicates.

### Pass criteria

- 10/10 sessions, 30 valid JPEGs.
- No fake success; no overwriting; no corrupt file.
- Retake All works; all three replacement captures are valid; previous session originals remain preserved.
- Disconnect/power-off cannot mark active capture successful.
- App restart preserves originals and recovers.

### Evidence

Screenshots/logs/model/transport, file paths, photo/video of shutter, timings, failures. **No physical result is verified until this is run.**

---

## 5. DNP DS-RX1HS physical validation procedure

**Current blocker:** no Windows/DNP hardware; no driver verification. Do not install drivers on an unavailable machine.

### Preconditions

- Windows 11 x64; printer connected/powered.
- DNP Windows driver installed; exact queue name confirmed.
- 4×6 media/ribbon loaded; 2-inch cut enabled.
- `TERABOOTH_PRINTER=spooler` or `hotfolder` (not mock).
- `TERABOOTH_PRINTER_NAME` matches the Windows queue.
- Bridge health green.
- Calibration assets generated.

### Tests

1. **Driver detection**: printer visible; Windows test page prints.
2. **Media configuration**: 4×6 and 2-inch cut selected.
3. **4×6 output**: calibration sheet prints.
4. **Two 2×6 strips**: measure both; centre cut.
5. **Physical cut**: cut aligns; no trimming of photo content.
6. **Orientation**: top arrow up; no rotation.
7. **Colour/quality**: legible text/patches; acceptable cast.
8. **Repeated jobs**: 20 consecutive prints; no jams/duplicates.
9. **Failure/recovery**: offline/paper-out/cover-open; job failed/unknown; no auto-retry; recovery print only after checking output.
10. **Reprint**: new job; exactly one extra print; duplicate submission does not add a physical print.

### Pass criteria

- 4×6 dimensions within tolerance; two 2×6 strips; correct cut/orientation.
- 20/20 prints; no duplicates.
- `unknown` handled by physical inspection, not blind retry.
- No print layout changes.

### Evidence

Photos with ruler, cut sample, 20-print stack, printer/driver/media versions, API job state logs. **No DNP compatibility claim until physical test.**

---

## 6. Guest QR delivery validation procedure

**Current blocker:** no guest phones/router.

### Preconditions

- iPad and Windows on same LAN; Windows LAN IP recorded.
- `TERABOOTH_PUBLIC_BASE_URL` uses that IP; no localhost.
- Windows firewall TCP 8787 Private.
- Guest phone on SSID that can reach Windows.
- **AP/client isolation OFF**; guest SSID (if separate) can route to Windows.
- WAN/internet disabled for the test.
- Token TTL 24 h; job accepted; QR displayed.

### Tests

1. **iPhone Safari**: scan QR; page loads.
2. **Android browser** (Chrome/other): same.
3. **Same-LAN access**: Windows health/page reachable from phone.
4. **QR download**: page loads; original 1–3 download; strip download.
5. **WAN disabled**: repeat; no internet dependency.
6. **Isolation check**: enable AP isolation or guest isolation; confirm failure; document required router setting; disable isolation and retry.
7. **Token expiry/invalid**: expired/tampered link 404; no data leak.
8. **Multiple phones/concurrent**: two phones can download.

### Pass criteria

- Both phone platforms load page and download originals/strip with WAN off.
- No localhost/hostname-only URL.
- AP isolation disabled/route allowed.
- Token expiry behaves.

### Evidence

Phone screenshots/video, QR URL, router settings, WAN-off proof. **No QR claim until tested.**

---

## 7. Single operator checklist

Created: [PHYSICAL_VALIDATION_CHECKLIST.md](../PHYSICAL_VALIDATION_CHECKLIST.md)

It covers pre-event, signing, Windows, printer, camera, network, test session, print, QR, backup/recovery and shutdown. Use it as the single sign-off sheet.

---

## 8. Remaining blockers

| Blocker | Status |
|---|---|
| Apple Development identity/team/profile | **BLOCKED** |
| Physical iPad | **BLOCKED** |
| CascableCore licence/native adapter | **BLOCKED** |
| EOS R physical capture | **BLOCKED** |
| Windows machine/bridge execution | **BLOCKED** |
| DNP driver/print | **BLOCKED** |
| Guest phone/router/AP isolation | **BLOCKED** |
| Template/GIF | Deferred; not implemented |

### Recommended execution order

1. **Signing/iPad:** add Apple ID/team, automatic signing, trust/Developer Mode, install signed mock-camera build.
2. **Windows bridge:** install, `.env`, firewall, health, token match.
3. **DNP:** driver/media/test print/4×6/2×6/20 prints.
4. **QR:** iPhone + Android, WAN off, AP isolation.
5. **Cascable/EOS R:** licence, native adapter, 10 sessions; only then enable native camera.
6. **Dress rehearsal:** 10 sessions → 20 prints → QR; fallback decision.

If EOS R or DNP gates are not green by the rehearsal, use the proven fallback rig. Do not run a paid event on an unverified path.

---

## 9. Tests/build (current)

| Check | Result |
|---|---|
| `flutter analyze` | **No issues** |
| `flutter test` | **87 passed** |
| `pytest -q` | **39 passed** |
| `flutter build ios --simulator` | **Success** — 145 MB debug simulator app |
| Physical hardware | **Not tested** |

The simulator build is not physical deployment evidence.
