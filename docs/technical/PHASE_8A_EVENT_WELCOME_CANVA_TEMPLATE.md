# Phase 8A — Event Welcome Screen & Canva Photo Strip Editor

## Overall result

**PASS for the software workflow.** No physical camera or printer was used.

Implemented end-to-end:
- event-specific guest welcome configuration and preview;
- persistent Canva PNG import;
- iPad touch slot editor;
- overlay/background layering;
- local 1200×1800 composition;
- preservation of original captures;
- Bridge upload of composed + original images;
- existing review, delivery URL/QR and MockPrinter handling.

---

## 1. Event welcome screen

Each `EventConfiguration` now stores an `EventWelcomeConfig`:

- event title;
- welcome subtitle;
- primary button label;
- background colour;
- optional background photo;
- optional event logo.

The welcome editor provides a live 3:4 preview and writes only the selected
event's configuration. Existing events receive backward-compatible defaults.

The booth event screen shows the customized welcome banner and uses the custom
button label for the existing Start Session action.

Entry point: **Event Details → Welcome**.

Known limitation: basic typography currently uses the app's existing type scale
and configurable colour; there is no separate font-family or font-size picker.

---

## 2. Canva template import

Entry point: **Event Details → Photo layout**.

- PNG-only import, signature checked.
- Imported bytes are copied into an event-scoped asset; the source file is never
  edited.
- Original artwork dimensions and path are stored.
- Transparent PNGs are preserved and composited normally.
- The artwork is fitted (not distorted) into the 2:3 output canvas.

---

## 3. Visual photo-slot editor

Implemented:

- Add slot (maximum 4, matching the existing capture range).
- Remove selected slot.
- Drag slot position.
- Resize with a touch handle.
- Assign capture order.
- Zoom 1×–3×.
- Horizontal/vertical photo position.
- Cover / Contain.
- Transparent overlay or background-artwork mode.
- Sample slot preview rendered on the actual 2:3 canvas.

All slot geometry is stored normalized (`x/y/width/height` 0..1) in template
coordinate space, not screen pixels.

Resizing a slot changes only its output rectangle; zoom/pan/crop values are stored
independently and are not recalculated when the slot is resized.

Known limitation: the editor's in-slot sample is a labelled placeholder; real
captured photos are used in the automatic composition.

---

## 4. Automatic composition

A new `CustomTemplateComposer`:

- decodes the imported Canva artwork and captured JPEGs;
- draws photos in capture order into the configured slots;
- applies cover/contain, zoom and normalized pan;
- draws artwork according to overlay/background mode;
- preserves artwork aspect ratio;
- outputs a separate 1200×1800 PNG.

Original captures remain untouched. The composed PNG is stored as a separate
session asset.

The session template switches to the custom layout when an event has one, so
capture count follows the configured slots.

---

## 5. Bridge and delivery integration

Added `precomposed_4x6_v1` to the Bridge:

- full-bleed 1200×1800 slot;
- accepts the composed image plus extra original images;
- no server text/branding is added to a custom composition.

On approval the app uploads:

```text
composed PNG first
+ all original captured JPEGs
```

The existing job, idempotency, status, MockPrinter, composition retrieval and
delivery URL/QR paths are used unchanged. Guest delivery includes the composed
asset and originals.

---

## 6. Persistence and isolation

- Welcome and custom layout are stored inside each `EventConfiguration`.
- Artwork paths are event-scoped.
- Tests verify welcome and layout isolation across events and restart.
- Existing events/customer data remain readable through defaults.

---

## 7. Verification

### Flutter

Full suite:

```text
152 passed
```

Targeted Phase 8A tests:
- welcome persistence and event isolation;
- custom Canva layout persistence;
- overlay and background composition;
- original JPEG hash preservation;
- composed output is 1200×1800;
- custom end-to-end session → local composition → Bridge submit → QR URL;
- precomposed Bridge client accepts composed + originals.

Final targeted run after artwork aspect-ratio correction:

```text
custom_template_composer_test: 2 passed
software_workflow_test: 11 passed
```

`flutter analyze`: **No issues found.**

### Windows Bridge

```text
78 passed
```

Includes precomposed template accepting four files, composition to 1200×1800,
and all existing API/template tests.

---

## 8. Screenshots

No screenshots are committed. A widget-golden capture was attempted, but the
headless run hung during the capture step and was terminated. The feature was
therefore verified through widget/controller tests rather than screenshots.

---

## 9. Known limitations

- Welcome typography has colour but no font-family/size controls yet.
- Editor sample slots are placeholders, not real cached photos.
- Maximum four photo slots.
- No rotation, borders, shadows or multi-layer graphic editing.
- Custom composition is local; the Bridge receives the rendered result plus
  originals rather than the editable design.
- Canva artwork is fitted to 2:3; a non-2:3 export can have transparent/blank
  margins.
- Native camera remains blocked by the production Cascable licence.
- Physical print remains unauthorized and unverified.

---

## 10. Safety

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
| Secrets exposed | **NO** |
