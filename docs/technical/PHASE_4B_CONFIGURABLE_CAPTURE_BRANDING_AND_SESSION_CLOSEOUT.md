# Phase 4B — Configurable Capture, Branding & Session Close-out

## Overall result

**PASS for the implemented software slice.**

Phase 4B connects event configuration to the real capture loop, variable-count
review/retake output, event branding at the template renderer, explicit
interrupted-session recovery, and CSV close-out reporting.

Verification:

- **123 Flutter tests passed**
- `flutter analyze`: **No issues**
- **42 Python bridge tests passed**
- iOS simulator build: **PASS**
- No camera/iPad hardware used
- `MockCameraService` remains the default

The bridge composition was extended additively for count-specific layouts and
branding; QR/GIF generation, DNP/printer communication and the Flutter print
queue contract were not rewritten.

---

## 1. Repository audit

Baseline before changes:

- Phase 4A event catalogue/session foundation present.
- Capture loop hard-coded `i < 3`; review hard-coded three cards; `approve`
  required exactly three photos.
- Bridge rejected anything other than three images and only had three-photo
  templates.
- Branding was a label (`brandingLabel`) and was not rendered.
- Interrupted sessions were detected but only surfaced as a warning; no explicit
  resume/close decision.
- No reporting/export module.
- Baseline: **110 Flutter tests**, **39 bridge tests**, clean analyze.

Audit boundaries:

- `CameraPipeline` remains authoritative for connection/capture state, capture
  IDs, serialization, timeout and duplicate protection.
- `ImageIngestor` remains the only original validation/atomic-storage path.
- The bridge owns template composition and print artefacts.
- Session metadata already provided the correct place for configuration
  snapshots and recovery.

---

## 2. Existing architecture reused

- `BoothController` / `ChangeNotifier`
- `CameraPipeline` and `ImageIngestor` unchanged
- Existing atomic JSON catalogue/settings/session writers
- `TemplatePreview` / `PhotoTemplate` engine
- Existing `BuiltinTemplates` and `TemplateGalleryScreen`
- Existing `BridgeClient` multipart submit and `PrintJob` polling
- `MockCameraService`
- Terabooth `Tb*` UI system
- Existing complete-review restore path

No new database or state-management framework was introduced.

---

## 3. Capture workflow changes

### Photo count

Supported **1, 2, 3 or 4** photos per session.

- Event configuration stores the count.
- The count is snapshotted when the session starts:
  - `photo_count_expected`
  - `configuration`
  - template/layout
- The controller loop uses the snapshot, not later event edits.
- Capture progress, active photo, remaining indicators, review cards, Retake
  All, approval and metadata all use the snapshot count.
- Count-specific 4×6 templates:
  - `solo_4x6_v1` — 1 photo
  - `duo_4x6_v1` — 2 photos
  - `grid_4x6_v1` — 4 photos
  - three-photo layouts remain the existing `strip`/`collage`/`minimal` set.
- Session output uses the snapshot layout.

Existing capture serialization/timeouts/duplicate IDs and ImageIngestor
validation are untouched.

### Countdown

Supported **Off, 3, 5 and 10 seconds**.

- The countdown duration is snapshotted with the session.
- The countdown renders before each capture.
- `cancelCountdown()` sets a cancellation flag.
- The loop checks cancellation before every timer tick, immediately before the
  capture call, and after all delays.
- No async delay is started unless the countdown is non-zero.
- Cancellation ends the session as `interrupted`; no capture is requested.
- Cancellation during an already-started in-flight capture cannot cancel the
  write and is not represented as a cancellation.

---

## 4. Branding implementation

### Model and persistence

`EventBranding` includes:

- enabled
- title
- tagline
- brand colour (`#RRGGBB`)
- placement (`top` / `bottom`)
- local logo path

The logo is validated in the editor for PNG/JPEG, ≤2 MB and decodable image
data, then stored atomically under the event's local `branding/` directory. The
path, not image bytes, is stored in JSON.

Sessions snapshot the branding configuration at start, so later event edits do
not change a historical session's output.

### Editor

`BrandingEditorScreen` provides:

- Logo picker via `image_picker` (photo library permission declared)
- Logo removal/reset
- Title/tagline
- Brand colour with validation
- Top/bottom placement
- Composition preview
- Explicit save/cancel
- Missing-logo validation and cleanup of unsaved new assets

Resetting does not delete the live asset until the reset is saved.

### Output integration

Branding is rendered by the actual bridge template renderer
(`windows_bridge/app/template_render.py`), not only Flutter preview:

- Logo drawn from the uploaded asset
- Title/tagline drawn with brand colour
- Placement top/bottom
- Optional logo
- Works with 1/2/3/4-photo templates
- Original source photos are never modified; branding exists only in the
  derived 1200×1800 4×6 JPEG artefact.
- Existing print dimensions/DPI and print queue contract remain compatible.
- Bridge accepts branding metadata and an optional `branding_logo` multipart
  file; older clients without branding remain valid.
- Reprint copies the original branding JSON.

Preview and output use the same geometry/fields; final rasterization may differ
slightly because Flutter and Pillow use different font backends. This is
documented as a visual-match limitation, not claimed as pixel-identical.

---

## 5. Interrupted-session recovery

Phase 4A detected incomplete active sessions. Phase 4B adds an explicit
operator decision screen:

- **Resume session**
- **Close & recover**
- **Cancel**

### Resume

- Restores event/session context
- Loads valid originals and original capture IDs
- Preserves crops
- Uses the session's original photo count, countdown, template and branding
- Captures only the remaining trailing slots
- Never recaptures existing valid slots
- Complete sessions go directly to review
- Missing/invalid/out-of-order slots disable resume

### Close & recover

- Never deletes valid originals
- Marks the session `recovered`
- Records an end timestamp
- Preserves session history
- Does not claim the session completed or approved

### Missing originals

`readSessionRecovery` reports missing slots. Resume is disabled if valid photos
are empty, a middle slot is missing, or required files are missing/unreadable.
The UI explains the limitation; the operator can close and recover valid files.

No interrupted session is auto-resumed.

---

## 6. Reporting and export

`EventReport`/CSV supports:

- Event name/date
- Client/venue
- Session IDs
- Start/end timestamps
- Duration seconds
- Photo count
- Approved state
- Session status and interruption flag
- Event totals: sessions, photos, approved sessions/photos
- Empty event: explicit “No sessions to export”

CSV is written atomically under the app's local `exports/` folder. The UI shows
the export filename, not an internal absolute path. No cloud analytics or
external reporting service was added.

---

## 7. Persistence changes

Additive and backward-compatible:

### Event configuration

```text
photo_count, countdown_seconds, branding
```

Older events default to three photos, three seconds, no custom branding.

### Session metadata

```text
photo_count_expected
countdown_seconds
configuration (snapshot)
branding (snapshot)
status
```

Older sessions default to three expected photos.

### Branding assets

```text
events/<event>/branding/logo.<png|jpg>
```

Stored outside JSON; atomic temp+rename; reset/replacement cleanup handled.

### Bridge database

```text
jobs.branding_json
```

Added via safe `ALTER TABLE` migration; old jobs remain readable.

---

## 8. Screens and workflows

| Surface | Change |
|---|---|
| Event form | Photo count 1–4, countdown Off/3/5/10, automatic layout for 1/2/4 |
| Event details | Branding editor entry, export CSV |
| Branding editor | Logo, title, tagline, colour, placement, preview, reset |
| Capture | Dynamic count, large countdown, cancel countdown, end-session |
| Review | Dynamic photo cards and Retake All copy/count |
| Interrupted recovery | Resume / Close & recover / Cancel |
| Print/composite | Existing bridge output now branded and count-aware |

---

## 9. Tests and build results

### Flutter

```text
flutter analyze
No issues found!

flutter test --concurrency=1
123 tests passed
```

Phase 4B tests cover:

- Count 1/2/3/4 and template slots
- Countdown Off/3/5/10
- Countdown cancellation before shutter
- Retake All with variable count
- Session configuration snapshot
- Branding/log persistence
- Branding validation and empty report
- Session branding snapshot
- Report after restart
- Partial interrupted resume with only remaining captures
- Existing capture ID preservation / no recapture
- Missing original disables resume; close marks recovered
- CSV content and local export

### Bridge

```text
.venv/bin/python -m pytest -q
42 passed
```

New bridge tests cover 1/2/4-photo templates, branded composition, and invalid
logo rejection. Existing print/QR/GIF/template tests remain passing.

### Build

```text
flutter build ios --simulator --no-codesign
✓ Built build/ios/iphonesimulator/Runner.app
```

- Bundle: `com.terabooth.teraboothIpad`
- Production demo licence: absent
- MockCameraService default: yes

---

## 10. Known limitations

- The bridge GIF generator remains a three-frame consumer; **1/2/4-photo
  sessions do not produce a guest GIF**. GIF code was intentionally not changed
  per the phase boundary.
- The 1/2/4-photo layouts are automatic; the existing template gallery remains
  the three-photo layout chooser.
- Preview and final output share geometry/fields but font rasterization is not
  pixel-identical between Flutter and Pillow.
- Resume supports contiguous trailing photo gaps only. A missing middle original
  or zero valid originals requires Close & recover.
- CSV is saved locally; no share-sheet integration was added.
- Branding assets use local paths; no cloud asset sync.
- No physical camera, iPadOS USB or printer/DNP behavior is claimed.

---

## 11. Recommended next phase

1. Add count-aware guest GIF generation as a separately reviewed bridge change.
2. Add share-sheet/file-card export for CSV and branded output.
3. Add session-detail reporting UI with per-session timing/photos.
4. Add explicit per-slot resume for non-trailing gaps once original-integrity
   policy is agreed.
5. Keep all hardware validation separate and explicitly authorized.

No further hardware operation was performed.
