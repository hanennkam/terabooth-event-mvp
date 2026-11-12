# Phase 4A — Event Management & Booth Session Foundation

## Overall result

**PASS — implemented and verified without hardware changes.**

Terabooth now has a production-minded local event catalogue, explicit event
lifecycle, event details/session history, and an active booth-session lifecycle
on top of the existing Flutter controller and JSON persistence.

No CascableCore, camera-harness, camera-pipeline, ImageIngestor, bridge, QR, GIF
or printer code was changed. `MockCameraService` remains the default.

---

## 1. Initial repository audit

The repository was inspected before implementation:

- Flutter 3.44.1 / Dart 3.12.1, iPad deployment target 14.0.
- No database layer. Persistence is local JSON plus per-session metadata and
  originals under `events/<eventId>/sessions/<sessionId>/`.
- `BoothController` owned a minimal `EventProfile` (`id`, `title`, `date`) and
  the `event_catalog.json` catalogue.
- `EventProfile` was selected through a small dialog. There was no event list,
  search, filter, status lifecycle, event details or event-level configuration.
- Session metadata already recorded `event_id`, `session_id`, captures, crops,
  template and approval state. Complete unsubmitted reviews were restorable.
- There was no active-session end/elapsed/history surface.
- Baseline: **96 Flutter tests passing**, `flutter analyze` clean, **39 Python
  bridge tests passing**.
- Baseline macOS harness was untouched and no camera hardware was used.

This phase retained the working capture/review/print/retake architecture rather
than replacing it with a new state framework.

---

## 2. Existing functionality reused

| Existing capability | Reused as |
|---|---|
| Atomic JSON catalogue (`event_catalog.json`) | Event catalogue persistence |
| Per-session `session.json` | Session history and recovery |
| `BoothController` / `ChangeNotifier` | Operator state and navigation |
| `StorageService` | Repository boundary for catalogue, settings, sessions |
| `BuiltinTemplates` / `TemplateGalleryScreen` | Event photo-layout configuration |
| Existing capture/review/retake/print pipeline | Booth session runtime |
| `MockCameraService` | Default development camera |
| Terabooth `Tb*` widgets/theme | New screens |
| Existing originals and atomic writes | Session photo storage |

The existing event catalogue and session format were extended additively; no
files were rewritten solely to change architecture.

---

## 3. Architecture changes

### Typed domain models (`lib/models.dart`)

- `EventStatus`: draft, scheduled, active, completed, archived.
- `EventConfiguration`: template, version, photo count, countdown, retake/review
  policy, output format and branding label.
- `EventProfile`: client, date ISO, start/end time, venue, description, status,
  configuration, timestamps, archive timestamp.
- `EventValidationException`: explicit validation codes/messages.
- `BoothSessionRecord`: event/session identity, lifecycle status, start/end,
  photo count, approval.

Transition rules live on `EventStatus`:

```text
draft     -> scheduled, archived
scheduled -> draft, active, archived
active    -> scheduled, completed, archived
completed -> archived
archived  -> (terminal)
```

Date changes never change status automatically. Status changes require an
explicit operator action or starting a scheduled event.

### Repository methods (`lib/services/storage_service.dart`)

- `readSessionsForEvent(eventId)` returns typed, sorted session records.
- `hasSessions(eventId)` protects delete rules.
- `latestActiveSession(eventId)` supports recovery.
- `markSessionInterrupted(...)` marks incomplete active sessions without touching
  originals.
- Existing atomic catalogue/settings/session writers remain the only writers.

### Controller (`lib/booth_controller.dart`)

- Event catalogue search/filter is UI-local; lifecycle and persistence live here.
- Added create/update/archive/delete-draft/status-transition methods.
- Added selected-event persistence via the existing `settings.json`.
- Event layout selection is persisted in event configuration and applied when
  the event is selected.
- Session start now persists an active session snapshot before capture; each
  capture updates photo count; approval records `approved`; ending records
  `interrupted` and an end time.
- Incomplete active sessions are marked interrupted on restart; complete
  unapproved sessions use the existing restore-review path.
- `endSession()` safely stops at the next capture boundary; it never cancels an
  in-flight camera write.
- Session photo count and history are exposed to the event detail screen.

No business rules were added to widgets beyond form editing and explicit
confirmations.

---

## 4. Persistence, database changes and migrations

No database or new persistence dependency was introduced.

### Event catalogue (`event_catalog.json`)

Additive fields:

```text
date_iso, client, start_time, end_time, venue, description, status,
configuration, created_at, updated_at, archived_at
```

Old records load with safe defaults: scheduled status, default configuration,
empty optional fields. Writes remain atomic via temp-file + rename.

### Session metadata (`events/<event>/sessions/<session>/session.json`)

Additive fields:

```text
status, started_at, ended_at, photo_count, event_status
```

Existing fields, capture paths, crops, template and approval semantics are
preserved. Old metadata remains readable; missing `status` is treated as an
interrupted/legacy record rather than active.

### Settings (`settings.json`)

Additive `selected_event_id`; existing `bridge_url` writes now merge rather than
replace the settings object.

No destructive migration is performed. Corrupt session metadata is skipped for
history but cannot delete originals.

---

## 5. Features implemented

### Event management

- Event list with search by name/client/venue.
- Status filter: all, draft, scheduled, active, completed, archived.
- Sorting: active first, then scheduled, then draft, completed, archived; date
  and title tie-breakers.
- Empty, loading and error states.
- Create form: name, client, date, start/end time, venue, description, initial
  status, photo layout.
- Validation: required name, 120-character limit, valid date, valid times,
  end time after start time, duplicate IDs rejected.
- Saving guard prevents double-submit.
- Edit form preserves session data and validates changes.
- Explicit status transitions.
- Archive with confirmation; sessions/photos preserved.
- Draft deletion only when the draft has no sessions; confirmation required.
- Selected event persists across restart.

### Event details

- Information, status, time, venue, client and layout.
- Session count and total photo count.
- Session history with status and start time.
- Edit, start booth, schedule/activate/complete, archive and draft-delete actions.

### Booth session foundation

- Start from a scheduled/active event; starting a scheduled event explicitly
  activates the event.
- Active capture screen shows elapsed session clock, active/ending status,
  progress and existing camera labels.
- End Session with confirmation; stops at the next safe capture boundary and
  records an interrupted session without deleting originals.
- Session history persists locally.
- Restart during a complete unapproved session offers the existing review
  restore.
- Restart during an incomplete active session marks it interrupted and displays
  an operator warning; it is not silently resumed or presented as complete.
- Mock camera output remains clearly labelled; no mock capture is presented as
  a physical Canon capture.

### Event configuration

Implemented and persisted:

- Photo layout/template selection (the existing supported template engine).
- Fixed photo count `3`.
- Fixed countdown `3 seconds`.
- Retake policy `Retake All`.
- Review required.
- JPEG output through the existing bridge.
- Branding boundary: default template branding.

Unsupported per-event changes are shown as fixed/read-only rather than fake
controls. The current capture pipeline genuinely supports three photos and
Retake All only.

---

## 6. Screens and workflows

| Surface | Purpose |
|---|---|
| `EventsScreen` | Search/filter/select/create event; list status |
| `EventFormScreen` | Create/edit event and layout configuration |
| `EventDetailsScreen` | Event overview, status actions, session history |
| `WelcomeScreen` | Selected-event summary, details and manage-events entry |
| `CaptureScreen` | Active session status, elapsed clock and End Session |
| Existing review/print screens | Unchanged session output flow |

Navigation continues to use `Navigator`/`MaterialPageRoute`; no new routing or
state-management dependency was introduced.

---

## 7. Test results

### Flutter

```text
flutter analyze
No issues found!

flutter test --concurrency=1
110 tests passed
```

Phase 4A tests added in `test/phase4a_event_management_test.dart` (14):

- Event name/time validation.
- Explicit lifecycle transitions and archived terminal state.
- Create/edit/persistence with existing sessions retained.
- Selected event persistence across restart.
- Event layout configuration persistence.
- Draft deletion rules and session protection.
- Archive behaviour and start blocking.
- Duplicate event identifier rejection.
- Scheduled event activation and active-session persistence.
- Session end as interrupted with history retention.
- Incomplete active-session interruption on reload.
- Complete unapproved session restore.
- Active-session clock/status/end confirmation UI.
- Event list search, filter and status labels.

Existing camera, capture, retake, storage, recovery, bridge, template, print and
UI tests remain passing.

### Python bridge

```text
cd windows_bridge
.venv/bin/python -m pytest -q
39 passed
```

No bridge behavior was changed.

---

## 8. Build results

```text
flutter build ios --simulator --no-codesign
✓ Built build/ios/iphonesimulator/Runner.app
```

- Bundle ID: `com.terabooth.teraboothIpad`
- Demo licence in production app: **absent**
- Mock camera remains the default
- No hardware discovery, connection, shutter or transfer was performed

---

## 9. Known limitations

- Photo count and countdown are read-only at `3` and `3 seconds`; the capture
  pipeline still owns those semantics.
- Per-event branding is a boundary only: template branding continues to be used
  and custom branding is not applied to output.
- Retake policy/review/output are fixed to the currently supported workflow.
- Ending a session during an in-flight capture waits for that capture to finish.
- Incomplete sessions are marked interrupted, not resumed automatically.
- Only draft events without sessions can be deleted; all other removal is
  archive-only by design.
- Session history currently displays records; export/reporting is not implemented.
- No camera/iPadOS/DNP behavior is claimed by this phase.

---

## 10. Recommended next development phase

**Phase 4B — Event configuration applied to capture/output.**

Recommended scope:

1. Make photo count and countdown genuinely configurable through
   `CameraPipeline` while preserving sequential capture and no-retry semantics.
2. Apply event branding to the template/output boundary, with explicit preview.
3. Add session reporting/export for event close-out.
4. Add a dedicated session-resume decision for incomplete captures.
5. Keep all camera, bridge, QR, GIF and printer behavior isolated and unchanged.

No hardware-dependent work should be bundled into Phase 4B without a separate
authorization.
