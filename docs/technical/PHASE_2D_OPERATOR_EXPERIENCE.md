# Phase 2D — Operator Experience & UI/UX Refinement

> **Software-only phase.** No physical camera, Windows PC, printer or signing validation.
> **No architecture, print geometry, idempotency or API contract changes.**

---

## 1. Audit findings

The pre-Phase 2D app worked but looked like a functional prototype:

- Welcome screen exposed a raw bridge-URL text field, had no event empty state, and mixed event actions with session start.
- No settings screen or persisted bridge URL.
- Capture screen showed only a countdown and numbered circles; camera/capture states were not explained.
- Review screen had no destructive-action confirmation and no template context.
- Print screen was a single dense column; job ID, acceptance-vs-completion distinction, composition preview and recovery guidance were weak.
- No shared visual system: ad-hoc colours, spacing, typography and buttons.
- Event selection could be overwritten by a late catalog read if the operator created an event immediately after launch.
- QR URL was copyable but the operator experience was unclear about link readiness/printing.

All existing controller safeguards, Retake All-only event scope, bridge API, idempotency, composition dimensions and mock camera behaviour were preserved.

---

## 2. Design system added

- `lib/theme/tb_theme.dart`
  - Ink/surface/raised/line/cream/muted palette with gold, rose, mint and red status colours.
  - Typography scale for operator-distance reading.
  - Consistent button, input, dialog, snackbar and progress styling.
  - Spacing and radius tokens.
- `lib/widgets/tb_ui.dart`
  - `TbBackdrop`, `TbWordmark`, `TbPageHeader`.
  - `TbCard`, `TbEyebrow`, `TbSectionLabel`, `TbPill`.
  - `TbPrimaryButton`, `TbSecondaryButton`, `TbMetric`, `TbEmptyState`.

The design is landscape-first and responsive at iPad widths; narrower layouts stack and scroll rather than clip.

---

## 3. Screens redesigned

### Welcome / event console

- Event-first hero card with title, date, selected status, format and event ID.
- **No event selected** empty state with **Create event** / **Change event**.
- Booth console card with simulated-camera status, bridge address and large **Start Session**.
- **Settings** access via top-right icon.
- Bridge URL no longer edited in the main welcome flow; it lives in Settings.
- Event selection persists via the existing event catalog; changing is only allowed while idle.

### Capture

- Large mock viewfinder with framing grid, countdown and capture state.
- Status pills for camera connection and simulated mode.
- **Photo N of 3**, progress bar, three step rows, thumbnail strip and `N/3 captured`.
- Connection states: finding, connecting, ready, recovering, offline/error.
- Capture states: capturing, transferring, ready.
- Clear instruction not to leave the app during capture.
- No operator controls that could accidentally double-trigger a capture.

### Review

- Three equal-aspect photo cards with slot labels and capture checks.
- Event and **2×6 duo** template context.
- **Retake all** now opens a confirmation before replacing the current review.
- Large **Approve & Print**; disabled while a retake is running.
- Individual Retake 1/2/3 remains absent from the event UI.
- Previous originals remain preserved by the controller/storage layer.

### Print

- Split layout: status/recovery on the left; composition and guest QR on the right.
- Status pill and copy for submission, composing, queue, printing, completed, failed and unknown.
- Job ID, bridge state, completion confidence and attempts are visible.
- Explicit distinction between bridge acceptance and confirmed printer completion.
- Failed/unknown recovery copy warns against automatic resubmission.
- **Retry print (new job)** requires a confirmation dialog.
- **Next guest** resets the booth only after a terminal state.
- Composition preview with loading/empty/error states and large viewer.
- QR card with large code, scan instruction, selectable URL, copy tooltip and download-tracking disclaimer.
- Missing composition/QR states are explicit; a QR link never implies a successful physical print.

### Settings

- Persisted **Bridge URL** with Save and Test connection.
- Bridge health status/error with actionable LAN/firewall hint.
- Event title/date and event ID.
- Camera status and **SIMULATED** label.
- Bridge-reported printer name/mode/state/note; no invented physical connection.
- Diagnostics for service, event, bridge URL and camera.

---

## 4. State and interaction changes

- `hasSelectedEvent` added to distinguish an actual persisted event from default constructor values.
- `loadEvents()` now ignores a stale catalog result if the operator has already created/selected an event.
- `selectEvent()` explicitly sets `hasSelectedEvent = true`.
- Bridge settings loaded from `settings.json` on app start.
- `saveBridgeUrl()` persists only the bridge URL; `checkBridge()` stores health/error/checking state.
- Async bridge checks are disposal-guarded.
- Print screen retains controller idempotency and no auto-resubmit.
- Review confirmation prevents accidental Retake All.
- Settings only accessible from idle/welcome; no navigation away from in-flight capture/print.
- Empty/loading/error/success states added throughout.

---

## 5. Files changed

**New**

- `lib/theme/tb_theme.dart`
- `lib/widgets/tb_ui.dart`
- `lib/screens/settings_screen.dart`
- `test/ui_experience_test.dart`

**Modified**

- `lib/main.dart`
- `lib/booth_controller.dart`
- `lib/services/storage_service.dart`
- `lib/screens/welcome_screen.dart`
- `lib/screens/capture_screen.dart`
- `lib/screens/review_screen.dart`
- `lib/screens/print_screen.dart`
- `test/review_retake_test.dart`
- `integration_test/live_bridge_test.dart`

No Windows Bridge production code, composition geometry, camera topology, CascableCore, Template Engine or GIF code was changed.

---

## 6. Tests and results

```bash
cd /Users/Apple/Dev/terabooth-event-mvp/ipad_app
flutter analyze
flutter test
flutter build ios --simulator
```

| Check | Result |
|---|---|
| `flutter analyze` | **No issues** |
| `flutter test` | **65 passed** |
| `flutter build ios --simulator` | **Success — 145 MB debug simulator app** |
| Live MacBook FastAPI mock-printer integration | **PASS** |
| Windows runtime | **Not tested** |
| Physical hardware | **Not tested** |

Live integration result (mock bridge, local LAN, iPad A16 Simulator):

- Job `job_2c8332dbe3874b20932c38dd9ece9949` — `completed`, `confirmed`.
- New event creation, 3 mock captures, review, approval, HTTP submission, status polling, composition retrieval and QR display all passed.

New tests cover event empty state, event selection, settings persistence, bridge health/printer state, settings navigation, capture progress, print unknown state, retake confirmation and print QR/copy composition.

---

## 7. Known limitations

- No physical iPad, Canon EOS R, Windows PC or DNP printer.
- Bridge connectivity and printer status are only as truthful as the bridge's `/v1/health` response; no direct hardware probing.
- No download-count tracking; the QR card explicitly says counts are not tracked.
- Guest delivery remains local-LAN/QR only; no physical guest device tested.
- No active session restoration after app restart; storage/orphan recovery is unchanged.
- Settings persists the bridge URL only; other operational values remain environment/build configured.
- The app uses system fonts and no new visual dependencies.

---

## 8. Next recommended phase

1. Physical Windows bridge + DNP 4×6/2×6 validation.
2. Apple signing and physical iPad install.
3. CascableCore/EOS R adapter and 10-session validation.
4. Physical iPhone guest QR/AP-isolation validation.
5. Event-day rehearsal with the proven fallback rig available.

Template Engine/GIF remain deferred and out of scope.
