# Terabooth Physical Validation & Event Readiness Checklist

**Event:** Saturday 14 November 2026
**Operator:** __________________  **Date/time:** __________________
**Use with:** `docs/EVENT_DAY_RUNBOOK.md` and `docs/technical/PHASE_1F_PHYSICAL_VALIDATION.md`

> Mark every item **PASS / FAIL / BLOCKED**. Do not mark PASS without evidence.
> Current state: simulator only; no physical iPad/EOS R/DNP/phone test has been completed.

---

## 0. Go / no-go (event morning)

- [ ] Signed iPad app installed and launches.
- [ ] iPad permissions: Camera, Files/Folders, Local Network.
- [ ] Windows bridge health green; printer mode is **not mock**.
- [ ] DNP 4×6 + 2×6 cut sample passed.
- [ ] QR on iPhone **and** Android with WAN off passed.
- [ ] If using Canon capture: EOS R 10/10 session test passed.
- [ ] Backups and proven fallback rig on site.
- [ ] API token/secret are real (not placeholders) and iPad token matches if used.
- [ ] No unverified path is being presented as verified.

**Decision:** GO / NO-GO / FALLBACK

---

## 1. Signing / iPad install

- [ ] iPad connected by data USB cable; **Trust This Computer** accepted.
- [ ] iPad **Developer Mode** enabled and restarted.
- [ ] Xcode → Settings → Accounts: Apple ID added.
- [ ] Team selected (Personal Team or paid).
- [ ] Runner → Signing & Capabilities → Automatic signing.
- [ ] Bundle ID `com.terabooth.teraboothIpad` accepted (or documented conflict change).
- [ ] Xcode registered the iPad/created provisioning.
- [ ] `flutter devices` lists the **physical** iPad.
- [ ] Signed app installed; launch confirmed.
- [ ] Debug/release choice documented; release used for event if possible.
- [ ] Personal Team expiry noted (if applicable; ~7 days).

**Evidence:** Xcode signing screenshot, `flutter devices` output, app launch.

---

## 2. Windows bridge

- [ ] Windows 11 updated; sleep disabled; high performance.
- [ ] Python 3.11+ 64-bit.
- [ ] `install_windows.ps1` completed.
- [ ] `windows_bridge\.env` exists and edited.
- [ ] `TERABOOTH_PRINTER=spooler` or `hotfolder` (**not mock**).
- [ ] `TERABOOTH_PRINTER_NAME` matches actual Windows queue.
- [ ] `TERABOOTH_API_TOKEN` set or intentionally empty; no placeholder.
- [ ] `TERABOOTH_DELIVERY_SECRET` long/random; not placeholder.
- [ ] `TERABOOTH_PUBLIC_BASE_URL` = actual Windows LAN IP, no localhost.
- [ ] `TERABOOTH_DATA_DIR` absolute, writable, backed up location.
- [ ] Firewall TCP 8787 Private profile.
- [ ] Bridge started via `run_windows.ps1`; no warnings about mock/placeholders.
- [ ] `/v1/health` returns 200 from another device.
- [ ] Bridge restart/shutdown procedure known.

**Evidence:** health JSON, `.env` keys (not secrets), firewall rule, bridge console.

---

## 3. DNP printer

- [ ] DNP DS-RX1HS connected/powered.
- [ ] Windows driver installed; printer queue visible.
- [ ] Exact queue name matches `.env`.
- [ ] 4×6 media/ribbon loaded.
- [ ] 2-inch cut enabled.
- [ ] Windows test page prints.
- [ ] Calibration 4×6 print.
- [ ] Measure 4×6 (within tolerance).
- [ ] Two 2×6 strips present.
- [ ] Physical cut aligned; no content loss.
- [ ] Orientation correct (TOP up).
- [ ] Colour/quality acceptable.
- [ ] 20 consecutive prints; no jams/duplicates.
- [ ] Offline/paper-out recovery; no blind retry.
- [ ] Reprint produces exactly one extra print.

**Evidence:** ruler photos, cut sample, 20-print stack, driver/media versions.

---

## 4. Camera (EOS R)

**If CascableCore/native adapter is not installed/tested, mark BLOCKED and use fallback. Do not use mock for a paid camera claim.**

- [ ] EOS R charged/AC; card inserted.
- [ ] Wi-Fi **disabled**.
- [ ] PTP/default USB; JPEG Large/Fine; auto power-off off.
- [ ] Direct data USB cable; no unpowered hub.
- [ ] Native camera build installed (`USE_NATIVE_CAMERA=true` only after integration).
- [ ] Camera authorization/Camera-Files permissions granted.
- [ ] USB discovery/connection; model/transport shown.
- [ ] Live view usable.
- [ ] Single capture: physical shutter fires.
- [ ] JPEG received, saved, opens, orientation correct.
- [ ] Three-photo session/review.
- [ ] **Retake All** restarts the complete three-photo session; all three replacements are valid.
- [ ] Previous session originals remain preserved; review/approval work after recapture.
- [ ] No individual per-photo retake is used in the event workflow.
- [ ] Disconnect/reconnect during capture/transfer; no false success.
- [ ] 10 consecutive sessions / 30 originals.
- [ ] App restart preserves originals; no duplicates.

**Evidence:** screenshots/logs, file paths, shutter video, 10-session log.

---

## 5. Network / QR

- [ ] iPad + Windows on same LAN/VLAN.
- [ ] Windows LAN IP recorded: __________________
- [ ] QR base URL uses that IP (not localhost).
- [ ] Guest SSID can reach Windows:8787.
- [ ] **AP/client isolation OFF**; router setting recorded.
- [ ] iPhone Safari: page loads.
- [ ] Android browser: page loads.
- [ ] Download original 1–3.
- [ ] Download strip.
- [ ] WAN/internet disconnected; repeat downloads.
- [ ] Token expiry/invalid link returns 404.
- [ ] Two phones concurrently.

**Evidence:** phone screenshots/video, QR URL, router settings, WAN-off proof.

---

## 6. Test session / print / QR integration

- [ ] 3 approved photos → bridge accepted.
- [ ] Print status observed; physical output confirmed.
- [ ] QR page and GIF/strip/original availability as applicable.
- [ ] Duplicate submit does not create a second print.
- [ ] Reprint after confirmed non-print produces one print.
- [ ] Bridge restart behavior understood; no auto-reprint.
- [ ] 10 sessions / 20 prints rehearsal attempted.

---

## 7. Backup / recovery

- [ ] Windows `TERABOOTH_DATA_DIR` backed up (SQLite DB, job inputs, artefacts/outbox).
- [ ] iPad originals backed up/exported.
- [ ] `session.json`/`orphans.json` retained.
- [ ] Job/reprint log and unknown jobs recorded.
- [ ] Fallback rig tested/present.
- [ ] Operator knows camera/app/bridge/printer/network emergency steps.
- [ ] No secrets/tokens in shared logs/screenshots.

---

## 8. Event-day start

- [ ] Router powered; WAN optional; AP isolation off.
- [ ] Windows booted, bridge started, health green, printer ready.
- [ ] iPad charged, app launched, bridge URL entered.
- [ ] Camera connected (if using Canon) or fallback ready.
- [ ] Test capture/print/QR completed.
- [ ] Paper/media spare; cables/power secured.
- [ ] Operator checklist and runbook at station.

---

## 9. Shutdown / end of event

- [ ] Stop new sessions.
- [ ] Wait for current print; inspect output.
- [ ] Ctrl+C bridge; confirm stopped.
- [ ] Preserve/back up `TERABOOTH_DATA_DIR`.
- [ ] Preserve iPad originals.
- [ ] Record session/print/reprint/unknown counts.
- [ ] Shut down printer, Windows, iPad, camera; pack equipment.
- [ ] Complete sign-off below.

---

## 10. Sign-off

```text
Signing/iPad:        PASS / FAIL / BLOCKED   tester: __________ time: ______
Windows bridge:      PASS / FAIL / BLOCKED   tester: __________ time: ______
DNP printer:         PASS / FAIL / BLOCKED   tester: __________ time: ______
EOS R:               PASS / FAIL / BLOCKED   tester: __________ time: ______
QR/network:          PASS / FAIL / BLOCKED   tester: __________ time: ______
Integrated:          PASS / FAIL / BLOCKED
Event decision:      GO / NO-GO / FALLBACK
Notes:
```

**Stop immediately and use the proven fallback rig if:** camera cannot capture reliable originals, DNP cannot print the correct 2×6 output, QR cannot download with WAN off, or duplicates/false successes occur.
