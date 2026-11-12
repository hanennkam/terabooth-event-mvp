# Hardware Test Checklist — 11 November 2026

> **Purpose:** first real hardware integration session before the 14 November event.
> **Status legend:** ☐ not run · ✅ pass · ❌ fail · ⚠ blocked/conditional
> **No result may be marked ✅ without physical evidence (photo/log/measurement).**

---

## 0. Session prerequisites

| Item | Required | Status |
|---|---|---|
| iPad with USB-C, iPadOS current | Yes | Expected 11 Nov |
| Canon EOS R + charged battery/AC adapter | Yes | Available |
| Data-capable USB-C cable (not charge-only) | Yes | Check |
| CascableCore evaluation/commercial licence | Yes | **Not obtained** |
| Xcode + CocoaPods on Mac | Yes | Xcode 26.6 + CocoaPods 1.17.0 installed; iOS 26.5 runtime installed |
| iOS 26.5 platform runtime | Yes | Installed (iOS 26.5, 23F77) |
| Apple Development signing identity/team | Yes | **Missing** — 0 identities; no team/profile |
| Windows 11 laptop | Yes | Expected 11 Nov |
| DNP DS-RX1HS + USB cable + power | Yes | Available |
| DNP 4×6 media (at least 1 roll / 700 prints) | Yes | Confirm |
| 2×6-capable/perforated media | If available | Confirm |
| Travel router + 2 Ethernet cables | Yes | Confirm |
| Guest phone (iPhone or Android) | Yes | Confirm |
| Printer driver installed; 2-inch cut enabled | Yes | Verify |
| Python bridge installed on Windows | Yes | Run install script |
| Calibration assets generated | Yes | `scripts/make_test_sheet.py` |

**If Apple signing/device setup or the Cascable licence is missing, the camera section cannot start.** Do not substitute a mock camera for the camera test.

---

## 1. Camera — Canon EOS R → iPad

### Setup

- [ ] Camera charged / AC adapter connected.
- [ ] Camera Wi-Fi **disabled** (Canon cameras can disable USB when Wi-Fi is on).
- [ ] Camera in correct USB/PTP mode (EOS R default PTP; verify in menu).
- [ ] USB-C data cable connected **directly** to iPad (no unpowered hub).
- [ ] iPad updated, trusted, unlocked.
- [ ] App built with `--dart-define=USE_NATIVE_CAMERA=true`.
- [ ] CascableCore licence installed in the app.
- [ ] `Info.plist` Local Network/Bonjour permissions present.

### Tests

| # | Test | Expected | Result | Evidence |
|---|---|---|---|---|
| C1 | Launch app, Connect | Camera model/serial shown | ☐ | Screenshot/log |
| C2 | Start live view | Frames update, usable latency | ☐ | Screen recording |
| C3 | Trigger capture | Physical shutter fires | ☐ | Photo/video |
| C4 | Receive original | JPEG saved on iPad | ☐ | File path + file |
| C5 | Preview | Image displays, correct orientation | ☐ | Screenshot |
| C6 | Retake All | Complete 3-photo recapture; all replacements valid; previous originals preserved | ☐ | Log |
| C7 | Approve | Session proceeds to print | ☐ | Log |
| C8 | 10 consecutive sessions | 10/10 captures, 3 photos each | ☐ | Run sheet |
| C9 | Unplug/replug ×5 | Reconnect or clear error; no crash | ☐ | Log |
| C10 | App restart | Originals persist; session list intact | ☐ | Screenshots |
| C11 | Camera off / cable removed | Clear error, no fake capture | ☐ | Screenshot |

**Pass criteria:** C1–C11 pass; 10/10 sessions; original saved; no fake success.

### Measurements

| Metric | Value |
|---|---|
| Connect time | ______ s |
| Live-view latency (p95) | ______ ms |
| Capture → saved file (p95) | ______ s |
| Reconnect time (p95) | ______ s |
| Failures / errors | ______ |

**If camera fails:** record exact error; do **not** claim EOS R works. Fallback: iPad built-in camera or proven LumaBooth rig; notify client.

---

## 2. Printer — DNP DS-RX1HS on Windows

### Setup

- [ ] Windows 11 laptop updated; sleep disabled; high performance.
- [ ] DNP driver installed; printer visible.
- [ ] 4×6 media loaded; ribbon installed correctly.
- [ ] 2-inch cut enabled in driver/HFP.
- [ ] Print a Windows test page outside the bridge.
- [ ] Python bridge installed (`scripts\install_windows.ps1`).
- [ ] Bridge env: `TERABOOTH_PRINTER=spooler`, printer name, token, secret, LAN base URL.
- [ ] Firewall rule (TCP 8787, Private).
- [ ] Bridge health from iPad: 200.
- [ ] Calibration assets generated.

### Tests

| # | Test | Expected | Result | Evidence |
|---|---|---|---|---|
| P1 | Windows test page | Prints | ☐ | Photo |
| P2 | Print 4×6 calibration sheet | Correct size/orientation | ☐ | Ruler photo |
| P3 | Measure sheet | 4×6 in (101.6×152.4 mm) ±1 mm | ☐ | Measurement |
| P4 | Verify two 2×6 strips | 2×6 in each; centre cut | ☐ | Ruler photo |
| P5 | Orientation | TOP arrow up; no rotation | ☐ | Photo |
| P6 | Colour/text | Legible; no severe cast | ☐ | Photo |
| P7 | 20 consecutive prints | 20/20, no jams/duplicates | ☐ | Log/photos |
| P8 | Job states | received→...→completed or honest unknown | ☐ | API log |
| P9 | Duplicate submit | One physical print | ☐ | Log/photo count |
| P10 | Reprint | New job; one extra print | ☐ | Log |
| P11 | Printer offline | Job failed/unknown; no auto-retry | ☐ | Screenshot |
| P12 | Bridge restart | Jobs persist; no duplicate | ☐ | Log |

**Pass criteria:** P1–P12 pass; 20/20 prints; correct 2×6 cut; no duplicate prints.

### Measurements

| Metric | Value |
|---|---|
| Submit → physical print (p95) | ______ s |
| Prints succeeded / attempted | ___ / ___ |
| Duplicates | ______ |
| Cut alignment error | ______ mm |
| Media used | ______ |

**If P2–P6 fail:** do not use the bridge for the event; fix driver/cut or use HFP/proven rig.

---

## 3. QR — guest delivery over local LAN

### Setup

- [ ] Windows bridge reachable at `http://<windows-lan-ip>:8787`.
- [ ] `TERABOOTH_PUBLIC_BASE_URL` set to LAN IP (not localhost).
- [ ] iPad and Windows on the same router; no AP isolation.
- [ ] Guest phone on the same SSID.
- [ ] WAN/internet disconnected for the no-internet test.

### Tests

| # | Test | Expected | Result | Evidence |
|---|---|---|---|---|
| Q1 | Submit one job | `delivery_url` returned | ☐ | API response |
| Q2 | Display QR | QR shown on iPad | ☐ | Screenshot |
| Q3 | Scan with phone | Page loads over LAN | ☐ | Screen recording |
| Q4 | Download original | File saves, opens | ☐ | Phone screenshot |
| Q5 | Download strip | File saves, correct image | ☐ | Phone screenshot |
| Q6 | WAN disconnected | Q3–Q5 still pass | ☐ | Video |
| Q7 | Second phone | Concurrent download | ☐ | Log |
| Q8 | Expired/tampered token | 404, no data leak | ☐ | Browser |
| Q9 | Cross-job image ID | 404 | ☐ | Browser |
| Q10 | Bridge restart | QR still valid if token persisted | ☐ | Test |

**Pass criteria:** Q1–Q9 pass with WAN disconnected; no localhost in QR; no cross-job access.

**If Q3–Q6 fail:** check firewall, AP isolation, IP, base URL, router client-to-client setting. Do not claim QR works.

---

## 4. Integrated dress rehearsal

| # | Test | Target | Result |
|---|---|---|---|
| I1 | 10 full sessions: capture → review → print → QR | 10/10 | ☐ |
| I2 | 20 physical prints | 20/20 | ☐ |
| I3 | QR downloads (iPhone + Android) | 10/10 | ☐ |
| I4 | Restart app/bridge mid-run | No lost originals/jobs | ☐ |
| I5 | Network disconnect/reconnect | Safe; status resumes | ☐ |
| I6 | Duplicate request | 1 print | ☐ |
| I7 | Operator diagnosis | Fault identified in ≤2 min | ☐ |

**Event go/no-go:** all I1–I7 pass by **Friday 13 November 18:00**. Otherwise use the proven LumaBooth rig.

---

## 5. Evidence to capture

- Photos of the camera/iPad/cable setup.
- Screenshots: camera connected, live view, captured image, print status, QR.
- Video: scan → download with WAN off.
- Photos: calibration sheet with ruler, 2×6 cut, 20-print stack.
- Logs: bridge job states, error messages, timings.
- Measurements: print size, cut alignment, timings.
- Signed checklist with model/firmware/serial/media lot.

---

## 6. Stop conditions

Stop and fall back if any of these occur:

- Camera adapter cannot compile or capture a real image.
- Any app claims success without a saved original.
- DNP output is wrong size/orientation/cut after two fix attempts.
- Duplicate physical prints occur on repeated requests.
- QR cannot download with WAN off on either phone.
- Any lost original or unrecoverable job during the rehearsal.

**Fallback:** use the proven LumaBooth iPad + Windows print rig for 14 November. Do not run a paid event on unverified hardware.

---

## 7. Sign-off

```
Camera: PASS / FAIL / BLOCKED   tester: __________  time: ______
Printer: PASS / FAIL / BLOCKED  tester: __________  time: ______
QR: PASS / FAIL / BLOCKED       tester: __________  time: ______
Integrated: PASS / FAIL / BLOCKED
Event decision: GO / NO-GO
Notes:
```

> **Event scope:** individual per-photo retake is out of event scope; C6 validates Retake All only.
