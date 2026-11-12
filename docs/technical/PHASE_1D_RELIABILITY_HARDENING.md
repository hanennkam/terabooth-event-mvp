# Phase 1D — Reliability Hardening & Physical Device Preparation

> **Scope correction (Phase 1F-R):** later product scope removed individual per-photo retake from the event MVP. References below are historical implementation/test records; event validation uses **Retake All** only.

> **Status:** EXIF, orphan recovery and timeout race protection implemented and tested with synthetic images/mocks.
> **No CascableCore installation. No physical iPad/EOS R test. No signing credentials used.**
> **Event:** Saturday 14 November 2026.

---

## 1. Findings before changes

### EXIF orientation

- `ImageValidator` parsed **raw JPEG SOF dimensions** and did not read EXIF orientation.
- `CapturedImage.width/height` therefore represented raw dimensions, not effective display/print dimensions.
- Original JPEG bytes were already stored unchanged.
- Flutter's image codec was probed with all eight orientations: it **applies orientation for display** and reports swapped dimensions for 5–8. No display wrapper was needed (a wrapper would risk double rotation).
- `windows_bridge/app/compose.py` already calls `ImageOps.exif_transpose` before fitting/cropping. It was already correct; it needed regression tests for all eight values.
- Metadata did not record orientation, and saved-image verification did not compare orientation.

### Orphan originals

- Storage wrote originals atomically and cleaned temp files.
- If the app was interrupted after a complete original was written but before `session.json` was updated, the file remained on disk with no reference.
- No mechanism recorded such files; they were neither deleted nor inspectable.

### Capture timeout

- The 15 s timeout wrapped only `camera.capture(captureId)`.
- It did **not** cover image validation, local storage, or bridge upload.
- A late image after timeout was already ignored by the timeout wrapper, but there was no explicit regression test for that race.

### Signing / deployment

- Bundle identifier: `com.terabooth.teraboothIpad`.
- Deployment target: iOS 13.0.
- `security find-identity -v -p codesigning`: **0 valid identities**.
- `DEVELOPMENT_TEAM`: empty; no provisioning profile.
- No iPad connected.
- Unsigned build succeeds; signed physical deployment has not been tested.

---

## 2. Changes implemented

### 2.1 EXIF orientation correction

Added `lib/services/exif_orientation.dart`:

- Reads JPEG APP1/TIFF IFD0 tag `0x0112` (orientation 1–8).
- Returns 1 when absent/invalid; never modifies bytes.
- `swapsDimensions(5..8)` for effective dimensions.

Updated `ImageValidator`:

- Parses raw SOF dimensions and EXIF orientation.
- Computes **effective** dimensions (swap for 5–8).
- Uses effective dimensions for minimum-edge/pixel validation and small decode targets.
- Returns `ImageValidationResult` with `orientation`, `rawWidth`, `rawHeight`, and effective `width`/`height`.

Updated `CapturedImage`:

- Added `orientation` (default 1).
- Effective `width`/`height` are stored; original bytes are untouched.
- `withPath` / `withCaptureId` preserve orientation.

Updated `ImageIngestor`:

- Saves original bytes unchanged.
- Carries orientation into `CapturedImage`.
- Re-open validation now compares orientation as well as dimensions.

Updated `BoothController` metadata:

- `session.json` captures now include `orientation`.

**No UI rotation wrapper was added.** Flutter's codec already applies EXIF orientation; the automated test confirms effective display dimensions for all eight values. This avoids double-rotation.

**Print compositor:** no code change was required. `_cover` already uses `ImageOps.exif_transpose`; tests now cover all eight orientations.

### 2.2 Orphan recovery

Added to `StorageService`:

- `OrphanRecord` and `recoverOrphans()`.
- Reads `session.json` `captures[].path`/`filename` references.
- Scans complete `original_*` JPEG/PNG files with valid signatures.
- For unreferenced files, records metadata in `orphans.json`:
  - filename, path, byte length,
  - candidate capture ID/slot parsed from filename **for inspection only**,
  - `assigned_to_session: false`,
  - detected timestamp.
- **Does not modify `session.json`**, never assigns a slot, and never deletes the original.
- Existing orphan records are retained while the file exists and is still unreferenced; records for now-referenced or missing files are pruned.
- Repeated recovery is idempotent.
- Distinct orphan files sharing a candidate capture ID are both preserved and recorded; no duplicate session references are created.

`BoothController.startSession()` now runs:

1. `recoverIncompleteWrites()` — remove temp/partial files.
2. `recoverOrphans()` — record complete unreferenced originals.

If recovery fails, the session fails explicitly rather than silently continuing.

### 2.3 Capture timeout race protection

No timeout value was changed.

- Timer starts when the active job invokes `camera.capture(captureId).timeout(captureTimeout)`.
- It covers the native shutter/capture request through delivery of a `CapturedImage`.
- It does **not** cover queue wait, image validation, local storage, bridge upload, or QR.
- On expiry: `CAPTURE_TIMEOUT`; capture state `failed`; active job cleared; the returned future errors.
- The timed-out job cannot be completed by a later image: the timeout future is already settled, the job is no longer active, and the identity guard prevents ingest/save.
- No automatic shutter retry exists.
- Regression test: complete the fake camera **after** timeout; storage remains empty and state stays failed.

### 2.4 Physical deployment preparation

No bundle ID, signing identity, or team was created or changed. See the checklist in §5.

---

## 3. EXIF behaviour after changes

| Orientation | Raw dims | Effective dims | Display codec | Print `_cover` |
|---|---|---|---|---|
| 1 | 120×180 | 120×180 | 120×180 | exif-transposed |
| 2 | 120×180 | 120×180 | 120×180 | exif-transposed |
| 3 | 120×180 | 120×180 | 120×180 | exif-transposed |
| 4 | 120×180 | 120×180 | 120×180 | exif-transposed |
| 5 | 120×180 | 180×120 | 180×120 | exif-transposed |
| 6 | 120×180 | 180×120 | 180×120 | exif-transposed |
| 7 | 120×180 | 180×120 | 180×120 | exif-transposed |
| 8 | 120×180 | 180×120 | 180×120 | exif-transposed |

- Original bytes are preserved in every case.
- The JPEG EXIF APP1 segment remains unchanged.
- `session.json` records the orientation.
- Print composition uses oriented pixels via Pillow.

**Caveat:** synthetic fixtures prove the parser/compositor paths, not Canon EOS R files. Real EOS R EXIF must be tested physically.

---

## 4. Orphan/original guarantees

| Case | Behaviour |
|---|---|
| Complete orphan image | Preserved; recorded in `orphans.json` with `assigned_to_session:false` |
| Incomplete `.part` file | Removed by `recoverIncompleteWrites`; never recorded as orphan |
| Existing referenced original | Not recorded; remains untouched |
| Repeated recovery | No duplicate orphan records; original preserved |
| Duplicate capture ID | Files remain distinct; only unreferenced file is recorded; session metadata unchanged |
| Interruption after write, before metadata | Complete file preserved and recorded for inspection; no fabricated slot assignment |
| Missing/malformed `session.json` | Treated as no references; files preserved/recorded; no deletion |

`orphans.json` is for operator inspection only. It is not read by the print bridge and does not alter the 3-photo session.

---

## 5. Physical iPad deployment checklist

> No signing identity/team exists on this Mac yet. These steps require the user's Apple ID/team. No credentials are invented.

### Signing

1. Open **Xcode → Settings → Accounts** and sign in with the Apple ID.
2. Open `ipad_app/ios/Runner.xcworkspace`.
3. Select **Runner → Signing & Capabilities**.
4. Enable **Automatically manage signing**.
5. Select the correct Team (Personal Team or paid team).
6. Confirm bundle ID remains `com.terabooth.teraboothIpad`; change only if registration conflicts.
7. Let Xcode create the provisioning profile and register the iPad.
8. For a Personal Team, note the **7-day provisioning expiry** and sign close to the event. A paid team is more robust.

### iPad

1. Update iPadOS; charge the iPad.
2. Connect with a data-capable USB cable.
3. Tap **Trust This Computer**.
4. Enable **Settings → Privacy & Security → Developer Mode**, then restart.
5. Keep the iPad unlocked during install.

### Detect and install

```bash
cd /Users/Apple/Dev/terabooth-event-mvp/ipad_app
flutter devices
flutter run -d <ipad-device-id>
```

- The iPad must appear in `flutter devices`.
- Use Xcode's **Run** button if Flutter cannot detect it.
- Install the signed build; do not use the `--no-codesign` artifact.

### Permissions on first launch

- Allow **Camera**.
- Allow **Files and Folders**.
- Allow **Local Network**.
- Confirm both in iPad Settings → Privacy & Security and the app's own Settings page.

### Logs

- Xcode → **Window → Devices and Simulators** → select iPad → **Open Console**.
- Flutter logs:

```bash
flutter logs -d <ipad-device-id>
```

- For a signed run from Xcode, use the Xcode console/Filters for `Runner`.
- Capture the exact error text/code from `CameraPipelineException` and any native `FlutterError`.

### Current signing status

- `security find-identity -v -p codesigning` → **0 valid identities**.
- `DEVELOPMENT_TEAM` → empty.
- Provisioning profile → none.
- No physical deployment has been performed.

---

## 6. Tests and exact results

Run:

```bash
cd /Users/Apple/Dev/terabooth-event-mvp/ipad_app
flutter analyze
flutter test

cd ../windows_bridge
./.venv/bin/pytest -q

cd ../ipad_app
flutter build ios --no-codesign
```

| Check | Result |
|---|---|
| `flutter analyze` | **No issues** |
| `flutter test` | **38 passed** |
| `pytest -q` | **9 passed** |
| iOS unsigned build | **Success — 16.5 MB** |
| Physical deployment | **Not performed** |
| Physical EOS R capture | **Not performed** |

### New Phase 1D tests

- EXIF parser/orientation 1–8; effective dimensions.
- Flutter display codec orientation 1–8.
- Ingestion preserves original bytes and stores orientation/effective dims.
- Print `_cover` handles all eight orientations (Python).
- Orphan: complete, referenced, incomplete temp, repeated, duplicate capture ID, simulated interruption.
- Timeout: late image after expiry cannot complete/save.

Existing regression tests still pass: 3-photo workflow, individual retake, retake all, mock camera, review/approve, storage, bridge, QR-adjacent bridge tests.

---

## 7. Remaining risks / physical-test requirements

1. **Real EOS R EXIF**: confirm actual JPEG orientation tags and effective dimensions; synthetic 120×180 fixtures are not EOS R files.
2. **Print orientation/cut**: confirm the DNP output on real 4×6 media and 2-inch cut; `exif_transpose` is tested synthetically only.
3. **30 MP performance**: validate real image decode/preview/storage timing on iPad; the validator now avoids full-size decode, but the UI preview still decodes for display.
4. **Timeout coverage**: the 15 s timeout covers shutter-to-image delivery only; measure real validation/storage time. No transfer timer was added.
5. **Native disconnect event**: future CascableCore adapter must call `notifyDisconnected`; not wired yet.
6. **Signing/deployment**: no Apple identity/team/profile; no iPad.
7. **Permissions**: confirm Camera, Files and Folders, and Local Network prompts on iPadOS.
8. **Orphan recovery**: signature-only completeness check; it does not decode every orphan. Real interrupted-session behavior must be tested.
9. **No CascableCore** or real camera integration exists; mock remains default.

---

## 8. Files changed in Phase 1D

- `lib/services/exif_orientation.dart` (new)
- `lib/models.dart`
- `lib/services/camera_pipeline.dart`
- `lib/services/storage_service.dart`
- `lib/booth_controller.dart`
- `test/exif_orientation_test.dart` (new)
- `test/orphan_recovery_test.dart` (new)
- `test/camera_pipeline_test.dart`
- `test/fixtures/exif_o1.jpg` … `exif_o8.jpg` (new)
- `windows_bridge/tests/test_compose.py`
- `docs/technical/PHASE_1D_RELIABILITY_HARDENING.md`
- `docs/IMPLEMENTATION_LOG.md`
- `README.md`

**No CascableCore package/dependency/API was added. No Windows bridge production code was changed. No UI redesign.**
