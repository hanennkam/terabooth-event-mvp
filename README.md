# Terabooth Event MVP — 14 November 2026

> **Status:** one-time event MVP. Not a commercial SaaS product.
> **Camera gate:** **macOS SDK physical subset PASS** — Canon EOS 60D USB discovery, settings read, Live View, one shutter request and disconnect/reconnect work on this Mac. **iPadOS USB and image transfer remain unverified.** The camera is still absent from Cascable's official compatibility list. See `docs/technical/PHASE_3A_1B_CANON_60D_MAC_SDK_VALIDATION.md`.
> **Physical validation status:** Canon EOS 60D + USB was validated against CascableCore 18.0.2 on this Mac for discovery, settings read, Live View, one shutter request and disconnect/reconnect. No physical iPad, Windows/DNP or guest-phone validation has been performed; image transfer is untested (no SD card).

## What is implemented

| Component | Status |
|---|---|
| Flutter iPad app (welcome, capture, review/Retake All, approve, print status, QR) | Implemented; `flutter analyze` clean; **96 tests pass** |
| Mock camera (clearly labelled SIMULATED) | Implemented; unit test |
| Local original storage (atomic write, per event/session) | Implemented; unit test |
| iPad → bridge HTTP client (multipart, idempotency, status) | Implemented; unit test |
| Python FastAPI bridge (health, submit, status, reprint, QR) | Implemented; 39 pytest tests pass |
| Template engine (Classic 2×6, Editorial Collage, Minimal Stack) | Implemented; gallery/crop/version tests |
| Animated GIF (3 frames, 360×540, 1.8 s, loop) | Implemented; bridge + guest + Flutter preview tests |
| Pillow 2×6 composition (1200×1800, two 600×1800 panels) | Implemented; dimension test; optional template/crop renderer |
| Guest-token log redaction | Implemented; access/application log tests |
| Submitted-job restart reconciliation | Implemented; GET-only, no resubmission tests |
| SQLite job ledger / no duplicate on idempotency | Implemented; API test |
| Mock printer (success/failure/unknown) | Implemented; tests |
| Windows spooler path (PowerShell `System.Drawing.Printing`) | Code path only; **UNVERIFIED on Windows/DNP** |
| DNP Hot Folder Print adapter | Code path only; **UNVERIFIED on Windows/DNP** |
| QR delivery page/original/strip/QR PNG | Implemented; live smoke test on macOS |
| Real Canon EOS 60D capture | **NOT implemented** — SDK linked; licence bytes, simulated functional run and physical EOS 60D validation blocked |
| CascableCore demo build | `Runner-CascableDemo` / `se.cascable.CascableCoreiOSDemo`; **licence PASS**, remote SPM resolved, simulated discovery/connect/Live View/preview/disconnect PASS |
| iOS CascableCore adapter foundation | Native adapter compiles; capture waits for original bytes; **no physical iPad claim** |
| Canon EOS 60D macOS SDK | **PASS subset** — USB discovery/connection, 77 settings readable, Live View 1056×704, one shutter request, disconnect/reconnect; **image transfer untested (no SD)** |
| Simulator build | Production bundle `com.terabooth.teraboothIpad`, **174 MB**; demo bundle verified; production contains no licence |
| Native camera MethodChannel scaffold | Implemented (`NativeCameraService`, Swift stub returns `CAMERA_SDK_MISSING`); **not compiled** |
| Windows deployment scripts + calibration generator | Implemented; Windows execution **unverified** |

## Quick start (macOS development)

### Bridge

```bash
cd windows_bridge
./.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8787
curl http://127.0.0.1:8787/v1/health
./.venv/bin/pytest -q
```

The default printer is `mock`: it writes the composed strip to `windows_bridge/data/outbox/`. It is not a physical printer.

### iPad app

```bash
cd ipad_app
flutter analyze
flutter test
```

The app uses `MockCameraService` and displays **SIMULATED CAMERA**. It does not claim Canon capture.
Set the Windows bridge URL on the welcome screen (e.g. `http://<windows-lan-ip>:8787`).

## What is not verified

- iOS build: simulator builds pass with Xcode 26.6; physical signing is not configured.
- Canon EOS 60D capture: CascableCore linked, but no licence bytes, no successful simulated functional run, and no physical EOS 60D validation.
- Windows/DNP printing: no Windows machine or DS-RX1HS; spooler/HFP paths are unverified.
- Physical 2×6 cut, orientation/crop: unverified.
- Guest-phone QR downloads: unverified (no phones/router in this environment).

## Phase 1A readiness

- Camera spike report: `docs/technical/CAMERA_SPIKE_REPORT.md`
- Windows/DNP readiness: `docs/technical/WINDOWS_DNP_READINESS.md`
- Hardware test checklist (11 Nov): `docs/technical/HARDWARE_TEST_CHECKLIST.md`
- Phase 1A log: `docs/IMPLEMENTATION_LOG.md`
- iPad deployment readiness audit: `docs/technical/IPAD_DEPLOYMENT_READINESS.md`
- CascableCore SDK research: `docs/technical/CASCABLECORE_SDK_RESEARCH.md`
- CascableCore integration plan: `docs/technical/CASCABLECORE_INTEGRATION_PLAN.md`
- CascableCore API mapping: `docs/technical/CASCABLECORE_API_MAPPING.md`
- CascableCore test plan: `docs/technical/CASCABLECORE_TEST_PLAN.md`
- Phase 3A-1 setup/report: `docs/technical/PHASE_3A_1_CASCABLE_SETUP.md`
- Phase 3A-1A licence/SPM: `docs/technical/PHASE_3A_1A_LICENCE_AND_SPM.md`
- Phase 3A-1B EOS 60D macOS SDK: `docs/technical/PHASE_3A_1B_CANON_60D_MAC_SDK_VALIDATION.md`
- Phase 3A-2A iOS adapter foundation: `docs/technical/PHASE_3A_2A_IOS_CAMERA_ADAPTER_FOUNDATION.md`
- Phase 3A-2B EOS 60D original-transfer validation: `docs/technical/PHASE_3A_2B_CANON_60D_ORIGINAL_TRANSFER_VALIDATION.md`
- Phase 3A-2C USB preflight: `docs/technical/PHASE_3A_2C_CANON_60D_USB_PREFLIGHT.md`
- Phase 3A-2D original JPEG transfer: `docs/technical/PHASE_3A_2D_CANON_60D_ORIGINAL_JPEG_TRANSFER.md`
- Phase 3A-2E stable USB/capability validation: `docs/technical/PHASE_3A_2E_EOS60D_STABLE_USB_CAPABILITY_VALIDATION.md`
- Phase 3A-2F single-shot original transfer: `docs/technical/PHASE_3A_2F_EOS60D_SINGLE_SHOT_ORIGINAL_TRANSFER.md`
- Phase 3A-2G authorized single-shot result: `docs/technical/PHASE_3A_2G_AUTHORIZED_SINGLE_SHOT_ORIGINAL_TRANSFER.md`
- Phase 3A-2H JPEG-only single shot: `docs/technical/PHASE_3A_2H_SINGLE_SHOT_ORIGINAL_JPEG_VALIDATION.md`
- Phase 3A-2J orchestration safety: `docs/technical/PHASE_3A_2J_TEST_ORCHESTRATION_SAFETY.md`
- Phase 3A-2K capability preflight: `docs/technical/PHASE_3A_2K_CLEAN_USB_CAPABILITY_PREFLIGHT.md`
- Phase 3A-2L Live View cleanup correction: `docs/technical/PHASE_3A_2L_LIVE_VIEW_LIFECYCLE_CLEANUP_CORRECTION.md`
- Phase 3A-2M Live View hardware verification: `docs/technical/PHASE_3A_2M_LIVE_VIEW_LIFECYCLE_HARDWARE_VERIFICATION.md`
- Phase 3A-3A iPad deployment/EOS 60D preflight: `docs/technical/PHASE_3A_3A_IPAD_DEPLOYMENT_EOS60D_PREFLIGHT.md`
- Phase 3A-3B iPad Personal Team signing: `docs/technical/PHASE_3A_3B_IPAD_PERSONAL_TEAM_SIGNING.md`
- Phase 3A-3C safe iPad preflight probe: `docs/technical/PHASE_3A_3C_SAFE_IPAD_CAMERA_PREFLIGHT.md`
- Phase 3A-3D JPEG-only camera contract: `docs/technical/PHASE_3A_3D_JPEG_ONLY_CAMERA_CONTRACT.md`
- Phase 6A CascableCore integration: `docs/technical/PHASE_6A_CASCABLECORE_INTEGRATION.md`
- Phase 6B-1 Cascable demo signing/provisioning: `docs/technical/PHASE_6B_1_CASCABLE_DEMO_SIGNING_PROVISIONING.md`
- Phase 6B-2 Personal Team wildcard investigation: `docs/technical/PHASE_6B_2_PERSONAL_TEAM_WILDCARD_INVESTIGATION.md`
- Phase 6B-3 Personal Team signing capability: `docs/technical/PHASE_6B_3_PERSONAL_TEAM_SIGNING_CAPABILITY.md`
- Phase 6B-4 iPad developer trust diagnosis: `docs/technical/PHASE_6B_4_IPAD_DEVELOPER_TRUST_DIAGNOSIS.md`
- Phase 6B-5 Personal Team trust/first launch: `docs/technical/PHASE_6B_5_PERSONAL_TEAM_TRUST_FIRST_LAUNCH.md`
- Phase 6B-6 actual Terabooth iPad launch: `docs/technical/PHASE_6B_6_ACTUAL_TERABOOTH_IPAD_LAUNCH.md`
- Phase 6C-1 Cascable demo signing/install: `docs/technical/PHASE_6C_1_CASCABLE_DEMO_SIGNING_AND_INSTALL.md`
- Phase 6C iPad/Windows LAN integration: `docs/technical/PHASE_6C_IPAD_WINDOWS_BRIDGE_LAN_INTEGRATION.md`
- Phase 6C-2 iPad upload/template audit: `docs/technical/PHASE_6C_2_IPAD_PHOTO_UPLOAD_AND_TEMPLATE_RENDERING.md`
- Phase 6C-3 iPad JPEG import/upload: `docs/technical/PHASE_6C_3_IPAD_JPEG_IMPORT_AND_BRIDGE_UPLOAD.md`
- Phase 6D-1 DNP printer readiness: `docs/technical/PHASE_6D_1_DNP_PRINTER_INTEGRATION_READINESS.md`
- Phase 6D-2 DNP configuration alignment: `docs/technical/PHASE_6D_2_DNP_CONFIGURATION_ALIGNMENT.md`
- Phase 6D-3 Windows DNP preflight: `docs/technical/PHASE_6D_3_WINDOWS_RUNTIME_PREFLIGHT.md`
- Phase 6D-5 DNP pipeline readiness: `docs/technical/PHASE_6D_5_DNP_PRINT_PIPELINE_READINESS.md`
- Phase 6D-6 Windows DNP deployment: `docs/technical/PHASE_6D_6_WINDOWS_DNP_DEPLOYMENT.md`
- Phase 6E physical DNP calibration: `docs/technical/PHASE_6E_PHYSICAL_CALIBRATION_AND_PRINT_VERIFICATION.md`
- Phase 6F DNP job-level print control: `docs/technical/PHASE_6F_DNP_JOB_LEVEL_PRINT_CONTROL.md`
- Phase 6G XPS backend verification: `docs/technical/PHASE_6G_XPS_BACKEND_VERIFICATION.md`
- Phase 6H DNP vendor mechanism discovery: `docs/technical/PHASE_6H_DNP_VENDOR_MECHANISM_DISCOVERY.md`
- Phase 6I native Windows driver printing: `docs/technical/PHASE_6I_NATIVE_WINDOWS_DRIVER_PRINTING.md`
- Phase 7A first runtime integration: `docs/technical/PHASE_7A_FIRST_RUNTIME_INTEGRATION.md`
- Phase 7B Cascable production-bundle evaluation: `docs/technical/PHASE_7B_CASCABLE_PRODUCTION_BUNDLE_EVALUATION.md`
- Phase 7C runtime workflow readiness: `docs/technical/PHASE_7C_RUNTIME_WORKFLOW_READINESS.md`
- Phase 4A event management/session foundation: `docs/technical/PHASE_4A_EVENT_MANAGEMENT_AND_SESSION_FOUNDATION.md`
- Phase 4B configurable capture/branding/close-out: `docs/technical/PHASE_4B_CONFIGURABLE_CAPTURE_BRANDING_AND_SESSION_CLOSEOUT.md`
- Phase 4C guest gallery/local QR delivery: `docs/technical/PHASE_4C_GUEST_EXPERIENCE_LOCAL_QR_DELIVERY.md`
- Phase 5A-1 Windows portability/low-resource foundation: `docs/technical/PHASE_5A_1_WINDOWS_BRIDGE_PORTABILITY_AND_LOW_RESOURCE_FOUNDATION.md`
- Phase 5A-2 Windows runtime validation: `docs/technical/PHASE_5A_2_ACTUAL_WINDOWS_RUNTIME_VALIDATION.md`
- Phase 5A-2 disposable guest phone smoke: `docs/technical/PHASE_5A_2_DISPOSABLE_GUEST_PHONE_SMOKE.md`
- Phase 5B-1 DNP printing readiness: `docs/technical/PHASE_5B_1_DNP_PRINTING_READINESS.md`
- Camera pipeline reliability: `docs/technical/CAMERA_PIPELINE_RELIABILITY.md`
- Phase 1D reliability hardening / iPad checklist: `docs/technical/PHASE_1D_RELIABILITY_HARDENING.md`
- Phase 1E deployment readiness: `docs/technical/PHASE_1E_DEPLOYMENT_READINESS.md`
- Event-day runbook: `docs/EVENT_DAY_RUNBOOK.md`
- Phase 2A historical retake fix: `docs/technical/PHASE_2A_RETAKE_FIX.md`
- Phase 1F-R scope note: event MVP uses **Retake All only**; individual retake remains software-only
- Template Engine plan: `docs/technical/TEMPLATE_ENGINE_IMPLEMENTATION_PLAN.md`
- Animated GIF plan: `docs/technical/ANIMATED_GIF_IMPLEMENTATION_PLAN.md`
- Phase 1F physical validation: `docs/technical/PHASE_1F_PHYSICAL_VALIDATION.md`
- Phase 1G Windows bridge audit: `docs/technical/PHASE_1G_WINDOWS_BRIDGE_AUDIT.md`
- Phase 2 software integration: `docs/technical/PHASE_2_SOFTWARE_INTEGRATION.md`
- Phase 2B live local integration: `docs/technical/PHASE_2B_LIVE_LOCAL_INTEGRATION.md`
- Phase 2C Windows/DNP validation (blocked): `docs/technical/PHASE_2C_WINDOWS_DNP_VALIDATION.md`
- Phase 2D operator experience: `docs/technical/PHASE_2D_OPERATOR_EXPERIENCE.md`
- Phase 2E template engine: `docs/technical/PHASE_2E_TEMPLATE_ENGINE.md`
- Phase 2F animated GIF: `docs/technical/PHASE_2F_ANIMATED_GIF.md`
- Phase 2G initial audit: `docs/technical/PHASE_2G_AUDIT.md`
- Phase 2H audit: `docs/technical/PHASE_2H_AUDIT.md`
- Phase 2H final report: `docs/technical/PHASE_2H_FINAL_REPORT.md`
- Phase 2G final software QA: `docs/technical/PHASE_2G_FINAL_SOFTWARE_QA.md`
- Physical validation checklist: `docs/PHYSICAL_VALIDATION_CHECKLIST.md`

Current blockers: EOS 60D Live View end-stream lifecycle (reason 2/error 1008) and original-JPEG validation; physical camera/iPad signing, Windows/DNP and guest phone. CascableCore licence and remote SPM are resolved. Xcode 26.6 and the iOS 26.5 simulator runtime are installed; simulator production/demo builds pass. Physical signing was not tested. Phase 4A event/session foundation, Phase 4B configurable capture/branding/recovery/reporting, and Phase 4C local guest gallery/QR/GIF delivery are implemented and verified with MockCameraService. Guest delivery is local-network only; no physical guest phone, Windows/DNP or camera hardware has been validated. The Windows bridge now has a portable launcher, single-instance/port guards, runtime-only dependencies for deployment, disk-backed ZIPs, bounded work and lightweight diagnostics; actual Windows 4GB validation is **BLOCKED/NOT TESTED** in Phase 5A-2 because no Windows host was accessible; a runtime-only validation package is prepared for the laptop.

## Documentation

- `docs/technical/CANON_EOS_R_IPAD_FEASIBILITY.md` — G0 feasibility and GO/NO-GO.
- `docs/technical/MVP_ARCHITECTURE.md` — topology, API, state, QR, testing.
- `docs/technical/IMPLEMENTATION_PLAN.md` — five-day plan, gates, blockers.
- `docs/technical/IMPLEMENTATION_LOG.md` — what was done/tested.

## Event fallback

If G0 (camera) or G5 (dress rehearsal) cannot pass, use the proven LumaBooth iPad + Windows print rig. Do not run a paid event on an unverified camera/print path.
