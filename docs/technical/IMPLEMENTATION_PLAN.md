# Terabooth Event MVP — Implementation Plan

> **Environment update (Phase 1A.1):** Xcode 26.6 and CocoaPods 1.17.0 are installed; iOS 26.5 platform runtime is still missing. See `CAMERA_SPIKE_REPORT.md` §9.

> **Event:** Saturday 14 November 2026. **Today:** Monday 9 November 2026.
> **Mode:** emergency one-time MVP; hardware reliability over architecture.
> **Camera gate:** **NO-GO current / CONDITIONAL GO via CascableCore** — see `CANON_EOS_R_IPAD_FEASIBILITY.md`.

---

## 1. Phase 0 findings (complete)

| Check | Result |
|---|---|
| Fresh workspace | `/Users/Apple/Dev/terabooth-event-mvp` created; empty before creation |
| macOS | 26.5.1 arm64 |
| Flutter | 3.44.1 stable / Dart 3.12.1 |
| Xcode | **Full Xcode absent**; only Command Line Tools; `xcodebuild` fails |
| CocoaPods | **Not installed** |
| iPad/iPhone | **None connected** |
| Canon EOS R | **Not connected/available** |
| DNP DS-RX1HS | **Not connected/available** |
| Python | 3.11.9 |
| Python packages | FastAPI, Uvicorn, Pillow, pytest, multipart available; **qrcode missing** |
| Local IP | 192.168.8.105 (Mac) |

### Consequence

- The iPad app can be **written and unit/widget-tested** but **cannot be built for iOS** until Xcode + CocoaPods are installed.
- G0 (EOS R → iPad cable capture) **cannot be physically tested**; it remains unverified.
- The Windows bridge can be **fully implemented and tested with a mock printer** on macOS.
- Physical DNP printing, 2×6 cut and guest-phone QR are **unverified** until Windows/DNP/phones are available.

---

## 2. Scope

### In scope

- iPad Flutter app: welcome, capture, preview/retake, approve, local originals, upload, print status, QR.
- Windows Python bridge: FastAPI, SQLite, Pillow 2×6 composition, printer abstraction, job ledger, QR delivery.
- Mock camera and mock printer for development/testing.
- Documentation, tests, runbook.

### Out of scope

- Login/accounts/cloud/subscriptions/payments/analytics.
- Complex event management.
- AI, filters, video, GIF, 360.
- Windows camera control.
- Multi-printer/multi-booth.
- Commercial SaaS architecture.

---

## 3. Work breakdown

### Phase 1 — Foundation

| # | Task | Output | Acceptance | Depends |
|---|---|---|---|---|
| 1.1 | Create Flutter iOS project | `ipad_app/` with `pubspec.yaml`, `lib/`, `ios/`, `test/` | `flutter analyze` clean; `flutter test` passes | Flutter |
| 1.2 | Create Python bridge | `windows_bridge/` with FastAPI app, venv, requirements | `pytest` passes | Python |
| 1.3 | Define API contract | `docs/technical/MVP_ARCHITECTURE.md` + OpenAPI | Health/submit/status/reprint/QR documented | — |
| 1.4 | Mock camera | `MockCameraService` | Generates deterministic images; UI labels SIMULATED | 1.1 |
| 1.5 | Mock printer | `MockPrinter` | Simulates success/fail/unknown; no duplicates | 1.2 |

### Phase 2 — iPad camera (gated)

| # | Task | Output | Acceptance | Depends |
|---|---|---|---|---|
| 2.1 | Obtain CascableCore evaluation | Licence + framework | Licence available | Vendor |
| 2.2 | Install Xcode + CocoaPods | iOS build chain | `flutter doctor` iOS ✓ | Mac admin |
| 2.3 | Native Swift plugin | `CameraPlugin.swift` + MethodChannel | Connects to EOS R; live view; capture | 2.1, 2.2, iPad, EOS R |
| 2.4 | Capture/download | Original JPEG saved | 10/10 sessions | 2.3 |
| 2.5 | Reconnect/error handling | State + messages | Unplug/replug; no crash | 2.3 |

**Gate G0:** 10/10 captures, original saved, reconnect, by **Tue 10 Nov 12:00**. If not, fallback (iPad camera or proven rig) and do not claim Canon.

### Phase 3 — Print bridge

| # | Task | Output | Acceptance | Depends |
|---|---|---|---|---|
| 3.1 | Health/submit/status API | FastAPI routes | pytest: 200/202/409 | 1.2 |
| 3.2 | Image validation | hash/dimensions/count | Bad inputs 422 | 3.1 |
| 3.3 | SQLite ledger | sessions/images/jobs/attempts | Restart preserves jobs | 3.1 |
| 3.4 | 2×6 composition | Pillow 1200×1800, two 600×1800 panels | Dimensions/crop/text tests | 3.2 |
| 3.5 | Printer abstraction | Mock + Windows adapter | Mock test; Windows unverified | 3.4 |
| 3.6 | Idempotency/reprint | unique key + new reprint job | Duplicate → one job | 3.3 |
| 3.7 | QR delivery | tokens, page, downloads | curl/browser test; phone unverified | 3.1 |

### Phase 4 — Integration

| # | Task | Output | Acceptance | Depends |
|---|---|---|---|---|
| 4.1 | iPad bridge client | submit/status/reprint | Mock bridge integration test | 1.1, 3.1 |
| 4.2 | End-to-end mock | iPad mock capture → bridge mock print → QR | 10 sessions on Mac | 4.1 |
| 4.3 | Network config | bridge URL/token; firewall docs | Health from iPad (when available) | 4.1 |
| 4.4 | Failure tests | duplicate, offline, unknown | No duplicate/lost | 4.2 |

### Phase 5 — Event readiness

| # | Task | Output | Acceptance | Depends |
|---|---|---|---|---|
| 5.1 | Windows/DNP test | 20 prints, 2×6 cut | 20/20 correct | Windows, DNP, bridge |
| 5.2 | QR phone test | iPhone + Android | 10/10 downloads, no internet | phones, router |
| 5.3 | Dress rehearsal | 20 sessions | targets in §5 | all |
| 5.4 | Runbook | setup/failure scripts | printed at booth | 5.3 |

---

## 4. Five-day schedule

| Day | Date | Work | Gate |
|---|---|---|---|
| **Phase 0** | Mon 9 (remaining) | Environment + feasibility + architecture; create projects | Docs done |
| **Day 1** | Tue 10 | Flutter project, Python bridge skeleton, mock camera/printer; Cascable/Xcode setup | **G0 by 12:00** |
| **Day 2** | Wed 11 | Bridge API/SQLite/composition; iPad UI + storage + upload | Bridge tests green |
| **Day 3** | Thu 12 | Print adapter, idempotency, QR delivery; mock end-to-end | Mock E2E 10/10 |
| **Day 4** | Fri 13 | Hardware integration: iPad camera (if GO), Windows/DNP, phones; dress rehearsal | **G5 go/no-go 18:00** |
| **Day 5** | Sat 14 | Event; warm-up 5 sessions; runbook | Doors |

**Reality check:** if Xcode/CocoaPods, iPad/EOS R, CascableCore licence, Windows/DNP or phones are unavailable, the corresponding gate cannot pass. Do not mark it passed.

---

## 5. Acceptance targets

| # | Target | Verification |
|---|---|---|
| A1 | 10/10 camera capture sessions | Actual EOS R + iPad |
| A2 | 10/10 image transfers | iPad → Windows, hash match |
| A3 | 20/20 correct physical prints | DNP DS-RX1HS, 2×6 cut |
| A4 | Correct 2×6 dimensions/cut | Ruler + photos |
| A5 | QR downloads on guest phones | iPhone + Android, no internet |
| A6 | Restart preserves sessions/jobs | Kill/restart |
| A7 | Network disconnect/reconnect safe | Unplug/replug router |
| A8 | No duplicate prints | Repeated requests/idempotency |

**Current status:** A1–A8 **unverified**; only mock/test coverage exists.

---

## 6. Gates and stop conditions

| Gate | When | Pass | Fail action |
|---|---|---|---|
| **G0 Camera** | Tue 10, 12:00 | EOS R capture + save on iPad | Use iPad camera fallback or proven rig; no Canon claim |
| **G1 Foundation** | Tue 10, 18:00 | Flutter tests + bridge tests green | Fix; do not proceed to hardware |
| **G2 Transfer** | Wed 11, 18:00 | 10/10 uploads, hashes match | Fix bridge/network |
| **G3 Print (mock)** | Thu 12, 18:00 | Mock E2E 10/10; no duplicates | Fix ledger/composition |
| **G4 QR (LAN)** | Fri 13, 12:00 | Desktop browser + phone (if available) | Fix network/token |
| **G5 Dress** | Fri 13, 18:00 | A1–A8 | **No-go:** use proven rig |

**Stop rule:** any lost original, duplicate print, or unverified camera claim stops feature work and triggers fallback.

---

## 7. Blockers and dependencies

| Blocker | Needed for | Action |
|---|---|---|
| **Full Xcode absent** | Any iOS build | Install Xcode from App Store; select with `xcode-select`; run first launch |
| **CocoaPods absent** | Flutter iOS plugins | Install CocoaPods after Xcode |
| **No iPad/EOS R** | G0, A1 | Provide hardware; otherwise G0 unverified |
| **CascableCore licence** | EOS R USB capture | Request evaluation; accept commercial terms |
| **No Windows/DNP** | A3/A4 | Provide Windows machine + printer + media |
| **No guest phones/router** | A5 | Provide phones + travel router |
| **qrcode Python package missing** | QR generation | Install in bridge venv |

---

## 8. Fallbacks

1. **Camera:** if Cascable/Xcode/hardware cannot pass by Tue noon:
   - use iPad built-in camera (`camera` plugin) — disclosed degradation, or
   - use the proven LumaBooth rig for the event.
   Do not move camera control to Windows; do not silently use Wi-Fi.
2. **Print:** if Windows/DNP cannot be verified:
   - use the proven rig for printing, or
   - deliver digital-only with client approval (not the agreed product).
3. **QR:** if LAN delivery fails:
   - use the proven LumaShare/rig delivery; do not claim QR works.
4. **Event:** if any core gate fails Friday 18:00, run the proven rig; the MVP is not used for a paid event.

---

## 9. Exact first implementation tasks

1. **Create the Flutter iOS project** at `ipad_app/` with iOS platform; run `flutter analyze` and `flutter test`.
2. **Create the Python bridge** at `windows_bridge/`; venv; install FastAPI/Uvicorn/Pillow/qrcode/pytest/httpx; implement `/v1/health` + `/v1/print-jobs` + SQLite.
3. **Implement `MockCameraService`** and the welcome/capture/review UI with a visible **SIMULATED CAMERA** banner.
4. **Implement `MockPrinter`** and composition tests (1200×1800; two 600×1800 panels).
5. **Run tests** after each step; record in `IMPLEMENTATION_LOG.md`.

No camera plugin will be written until CascableCore, Xcode and hardware are available. No DNP compatibility will be claimed until a physical print is produced.

---

## 10. Deliverables

- `docs/technical/CANON_EOS_R_IPAD_FEASIBILITY.md`
- `docs/technical/MVP_ARCHITECTURE.md`
- `docs/technical/IMPLEMENTATION_PLAN.md`
- `docs/technical/IMPLEMENTATION_LOG.md`
- `ipad_app/` Flutter app (iOS target; mock camera + UI + storage + bridge client)
- `windows_bridge/` FastAPI + SQLite + Pillow + mock printer + QR delivery
- Tests and runbook
