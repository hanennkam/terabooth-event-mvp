# CascableCore Test Plan — Terabooth EOS R / iPadOS

> **TARGET CORRECTION (2026-11-12):** The actual camera is a **Canon EOS 60D**, not an EOS R. The EOS 60D is absent from Cascable's official Canon compatibility list and its direct model page returns 404. All EOS R-specific assumptions here are historical and must not be used as EOS 60D compatibility evidence. See `PHASE_3A_1_CASCABLE_SETUP.md`.

> **Documentation-only.** No physical test has been run. This plan is ready for the 11 November hardware session.
> **Passing this plan requires a real iPad, real Canon EOS R, real USB cable and an approved CascableCore licence.**

---

## 1. Test levels

| Level | What | Hardware | Current status |
|---|---|---|---|
| L0 | Static review / API contract | None | Documentation complete |
| L1 | Flutter UI + mock camera | Simulator/Mac | Existing 6 tests pass |
| L2 | Method/EventChannel contract with a fake native adapter | Simulator | Not implemented |
| L3 | SDK build + licence + discovery | iPad, no camera | Blocked |
| L4 | Physical EOS R capture/transfer | iPad + EOS R + cable | **Not tested** |
| L5 | End-to-end capture → print → QR | iPad + EOS R + Windows/DNP + phone | **Not tested** |

**iOS Simulator cannot test USB.** Official demo README: camera USB is not supported in the simulator. L1/L2 can validate UI/channel logic only.

---

## 2. Prerequisites

- CascableCore evaluation/commercial licence valid through 14 November.
- iPad with USB-C, current iPadOS, developer build installed.
- Canon EOS R, charged battery/AC adapter.
- Data-capable USB cable for the EOS R (verify the connector); direct connection; no unpowered hub.
- EOS R settings:
  - **Wi-Fi disabled**.
  - PTP/USB mode (EOS R default; no “Choose USB connection app” setting on this model).
  - JPEG Large/Fine (not RAW/HEIF), unless RAW handling is explicitly added.
  - Auto power-off disabled; card inserted with free space.
- iPad Settings: Camera enabled; Files and Folders enabled; Local Network allowed.
- App built with `USE_NATIVE_CAMERA=true` and a valid licence.
- Bridge/Windows optional for L5; not required for L3/L4.

---

## 3. L0/L1 — static and mock tests

| ID | Test | Expected | Status |
|---|---|---|---|
| S1 | `flutter analyze` | No issues | Existing pass |
| S2 | `flutter test` | 6/6 pass | Existing pass |
| S3 | Mock camera exists and is clearly labelled | No EOS R claim | Existing pass |
| S4 | Native stub without SDK | `CAMERA_SDK_MISSING` | Existing behavior |
| S5 | Channel names match | `com.terabooth/camera` | Inspect |
| S6 | No licence/secret committed | Repository clean | Inspect |

Do not mark camera integration tested based on S1–S6.

---

## 4. L2 — channel contract tests (after implementation, no camera)

Use a fake native adapter or mock method/event handler; never fake a real EOS R.

| ID | Test | Expected |
|---|---|---|
| N1 | `initialize` without licence | `CAMERA_LICENSE_MISSING`, no discovery |
| N2 | `initialize` with fake success | ready; authorization checked |
| N3 | `startDiscovery` emits searching/found | events ordered |
| N4 | `connect` success | connected event with USB transport |
| N5 | `connect` timeout | error within 20s; no connected state |
| N6 | duplicate `capture` | second returns `CAPTURE_IN_PROGRESS`; one capture only |
| N7 | capture event completion | image path/bytes returned once |
| N8 | capture timeout | `CAPTURE_TIMEOUT`; no placeholder |
| N9 | unexpected disconnect | `CAMERA_DISCONNECTED`; pending capture fails |
| N10 | app background/foreground | pending transfer aborted; no background capture |
| N11 | `disconnect` | clean; status disconnected |
| N12 | `dispose` | observers/handlers removed |

These tests verify the channel/state logic; they do **not** verify CascableCore or EOS R.

---

## 5. L3 — SDK/licence build test

| ID | Test | Expected |
|---|---|---|
| B1 | Raise iOS target to 14.0 | Xcode build succeeds |
| B2 | Add CascableCoreSwift/SPM | Package resolves; modules import |
| B3 | Apply valid licence | `LicenseVerificationResult.success` before API |
| B4 | Apply missing/invalid licence | fail closed; no discovery |
| B5 | Launch with no camera | discovery searching, no fake camera |
| B6 | Wired authorization denied | clear `CAMERA_PERMISSION_DENIED`; Settings guidance |
| B7 | Wired authorization granted | discovery can start |
| B8 | Offline launch at venue | licence valid without internet |

**B3/B4:** never log or expose licence data.

---

## 6. L4 — physical camera test matrix

### 6.1 Core capture — 10 sessions

For each session:

1. Launch app; connect EOS R.
2. Confirm model/transport (USB).
3. Trigger 3 captures via the booth flow.
4. Confirm the **physical shutter fires** each time.
5. Confirm each original JPEG is received and saved.
6. Preview each image; retake one if needed.
7. Approve; confirm the 3 files are the ones uploaded.

| ID | Session | Result | Evidence |
|---|---|---|---|
| C1 | Session 1 | ☐ | Log/screenshot |
| C2 | Session 2 | ☐ | |
| C3 | Session 3 | ☐ | |
| C4 | Session 4 | ☐ | |
| C5 | Session 5 | ☐ | |
| C6 | Session 6 | ☐ | |
| C7 | Session 7 | ☐ | |
| C8 | Session 8 | ☐ | |
| C9 | Session 9 | ☐ | |
| C10 | Session 10 | ☐ | |

**Pass:** 10/10 sessions × 3 images = 30 valid originals; no fake success; no crash.

### 6.2 Per-image checks

For each saved original:

- [ ] File exists, non-zero, opens as JPEG.
- [ ] Dimensions are the camera's expected JPEG size.
- [ ] Orientation is correct (no rotation/mirroring).
- [ ] EXIF/capture time is plausible.
- [ ] The image matches the shot just taken (not a stale file).
- [ ] No duplicate/old file is reused.

### 6.3 Fault injection

| ID | Fault | Expected | Result |
|---|---|---|---|
| F1 | Unplug USB during capture | capture fails; saved prior images remain; clear error | ☐ |
| F2 | Unplug during transfer | partial temp deleted; `TRANSFER_FAILED`; no corrupt JPEG | ☐ |
| F3 | Camera power-off during capture | unexpected disconnect; no fake image | ☐ |
| F4 | Camera power-off while idle | disconnected state; reconnect available | ☐ |
| F5 | Reconnect after unplug ×5 | 5/5 reconnect or clear failure; no crash | ☐ |
| F6 | Capture twice quickly | one capture; `CAPTURE_IN_PROGRESS` for second | ☐ |
| F7 | App background during capture | transfer aborted/handled; no capture in background | ☐ |
| F8 | App background/foreground idle | connection checked; no crash | ☐ |
| F9 | App restart after capture | originals persist; camera rediscovered | ☐ |
| F10 | Capture with camera off | `CAMERA_NOT_FOUND`/`NOT_CONNECTED`; no fake success | ☐ |
| F11 | Card full / no card | clear transfer/capture error; no fake | ☐ |
| F12 | Wrong image format (RAW/HEIF) | `INVALID_IMAGE_FORMAT`; actionable message | ☐ |

### 6.4 Timing targets (measure, do not promise)

| Metric | Target | Measured |
|---|---|---|
| Connect time | ≤ 15 s | ______ |
| First live view frame (if used) | ≤ 10 s | ______ |
| Shutter request → original saved (p95) | ≤ 10 s | ______ |
| 3-photo session capture time | ≤ 45 s | ______ |
| Reconnect time (p95) | ≤ 15 s | ______ |
| Failures / 30 images | 0 | ______ |

If EOS R transfer is slower, record actual values; do not hide them.

---

## 7. L5 — end-to-end with print and QR

After L4 passes:

| ID | Test | Expected |
|---|---|---|
| E1 | 10 sessions → bridge upload | 10/10 uploaded |
| E2 | 20 prints | 20/20 physical; no duplicates |
| E3 | 2×6 cut/orientation | correct per `HARDWARE_TEST_CHECKLIST.md` |
| E4 | QR on iPhone + Android, WAN off | downloads original/strip |
| E5 | Restart app/bridge mid-run | safe recovery |
| E6 | Duplicate print request | one physical print |
| E7 | Full event rehearsal | 10 sessions in 30 min |

Camera-specific failures stop L5; do not compensate with mock images.

---

## 8. 11 November session order

1. **08:30** — build/licence check on iPad; no camera.
2. **09:00** — connect EOS R; discovery/authorization; model check.
3. **09:15** — first capture; verify physical shutter + saved JPEG.
4. **09:30** — 10 sessions (C1–C10).
5. **11:00** — fault injection (F1–F12).
6. **12:00** — decision: camera GO/NO-GO.
7. **13:00** — printer/QR sessions if camera green.
8. **16:00** — end-to-end rehearsal.
9. **17:00** — sign-off / fallback decision.

If camera fails by 12:00, do not spend the afternoon on camera debugging at the expense of the printer/QR checks; switch to fallback.

---

## 9. Evidence to capture

- Screenshots: discovery, connected model/transport, capture, saved path, review.
- Video: physical shutter firing and app capture.
- Photos: iPad + cable + EOS R setup.
- Files: 30 originals with names/timestamps; verify on Mac.
- Bridge logs for L5.
- Fault logs for each F test.
- Timing measurements.
- Signed checklist.

**No result may be marked PASS without evidence.**

---

## 10. Acceptance / stop conditions

**Camera GO only if:**

- B1–B8 pass.
- C1–C10 pass: 30/30 valid originals.
- F1–F12 pass without data loss/duplicate/corruption.
- No fake success, no silent fallback to mock.
- Licence valid offline through 14 November.

**Stop and fall back if:**

- SDK/licence cannot be made valid offline.
- EOS R cannot be discovered/connected via USB.
- Original JPEG transfer cannot be made reliable.
- Any capture falsely reports success without an image.
- 10/10 cannot be achieved by 11 November.

**Fallback:** proven LumaBooth rig or iPad built-in camera, explicitly disclosed to the client. Do not claim EOS R support.

---

## 11. Open questions to resolve during testing

- Does EOS R provide original via camera-initiated transfer, or is filesystem required?
- Does filesystem switching stop live view; how long to recover?
- Actual JPEG dimensions and transfer times.
- Does EOS R USB remain stable through 10 sessions without replug?
- Does app background/foreground preserve the USB session?
- Does the licence work with WAN disabled after pre-activation?

Record answers in the hardware checklist and update the research doc; do not guess.
