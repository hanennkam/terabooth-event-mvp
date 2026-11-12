# Phase 8A Continuation — Capture Result & Guest Actions

## Overall result

**PASS for the software guest workflow.** No physical camera, physical print or
spooler operation occurred.

New guest flow:

```text
Welcome
→ Start / Take Picture
→ Capture all configured photos
→ Automatic strip + GIF generation
→ Result: GIF | AirDrop | Print
```

There is no guest approval step, no Retake All button, no intermediate strip
confirmation, and no QR workflow.

---

## 1. Removed guest workflow

Deleted from the app:

- `review_screen.dart`
- `print_screen.dart`
- Approve & Print action
- Retake All UI
- QR card, QR image, copy-link controls and QR navigation
- `qr_flutter` dependency

The Bridge's existing QR/delivery endpoints and stored delivery data were **not**
rewritten or deleted. They are now isolated backend compatibility surfaces with
no guest-facing entry point.

---

## 2. Automatic Result transition

- Capture still uses the existing CameraPipeline and stores every original.
- After the final configured capture, `AutoResultScreen` calls the existing
  approval/submission path automatically.
- The controller retains its internal `review` state for recovery/retake
  internals, but the guest never sees a review screen.
- The Result screen renders the actual Bridge composition (`compositionBytes`),
  not a placeholder.

---

## 3. Result screen

The result screen shows:

1. **GIF**
2. **AirDrop**
3. **Print**

A small top-level **Done** action returns to the event Welcome screen. Starting a
new session creates a new session ID and new original files; previous session
photos are not overwritten.

No QR/approval/retake controls are present.

---

## 4. GIF

- GIF action opens a dedicated `GifPreviewScreen`.
- The screen displays the actual Bridge-generated GIF.
- AirDrop is available only on explicit user action.
- Sharing uses the native iPadOS share sheet via `share_plus`.
- The share sheet is never opened automatically.

---

## 5. AirDrop

- Uses the native iPadOS share sheet (`share_plus`) with the final composed strip.
- No custom AirDrop protocol, recipient discovery or direct recipient selection.
- Sharing is disabled until the composition is available.
- Tested with an injected share service to confirm explicit invocation only.

---

## 6. Print

- Print opens a quantity selector for **1 or 2 copies** (the existing Bridge
  supports this range).
- The automatic Result job is a **preview/composition job** with
  `print_now=false`; it generates the strip and GIF without submitting to the
  printer.
- Selecting Print creates a new job through the existing reprint endpoint with
  the requested `copies` value.
- MockPrinter remains the default.
- No physical print was triggered.

Backend changes are limited to:
- `print_now` job flag/migration;
- preview jobs completing without printer submission;
- reprint accepting `copies=1|2`;
- existing idempotency and delivery data retained.

---

## 7. Verification

Full suites:

```text
Flutter: 152 passed
Bridge:   79 passed
flutter analyze: No issues
iOS simulator build: succeeded
```

Targeted result tests:

```text
result_screen_test.dart: 4 passed
```

Covered:
- review auto-advances without approval;
- exactly GIF, AirDrop, Print and no QR/approval/retake labels;
- strip AirDrop invokes the injected native-share boundary;
- GIF preview opens and shares only after explicit action;
- print quantity submits `copies=2` through reprint;
- Bridge preview job defers print and reprint uses selected copies.

Existing camera, composition, event isolation, storage, Bridge and template tests
remain passing.

---

## 8. Known limitations

- Print quantity is limited to 1–2 by the existing Bridge contract.
- AirDrop is the native share sheet; actual recipient selection is performed by
  iPadOS and cannot be automated in tests.
- No physical camera or printer validation was performed.
- GIF readiness depends on the Bridge's asynchronous GIF job; the preview screen
  shows progress/error state.
- Prior Phase 8A welcome/Canva editor limitations remain unchanged.

---

## 9. Safety

| Check | Result |
|---|---|
| Physical camera/shutter | **NONE** |
| Physical print/spooler | **NONE** |
| MockCamera default | **YES** |
| MockPrinter default | **YES** |
| USE_NATIVE_CAMERA | **NO** |
| Licence/provisioning changed | **NO** |
| Existing events/photos deleted | **NO** |
| Auth/idempotency changed | **NO** |
| QR guest surface | **REMOVED** |
| Secrets exposed | **NO** |
