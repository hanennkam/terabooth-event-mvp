# Phase 2E — Template Engine & Smart Auto-Fit

> **Software-only phase.** No physical iPad, Canon EOS R, Windows PC or DNP printer.
> **Default 2×6 three-photo geometry preserved.** Windows Bridge remains the canonical renderer.

---

## 1. Architecture

### Flutter

- `lib/templates/template_models.dart` — versioned template/slot/text model and validation.
- `lib/templates/builtin_templates.dart` — three data-driven built-ins.
- `lib/crop/crop_models.dart` — crop modes, normalized rectangles and immutable crop decisions.
- `lib/crop/crop_planner.dart` — Smart/Fit/Manual planning and safe fallback.
- `lib/services/face_detection_service.dart` — Vision/Fixture/Noop detector abstraction.
- `lib/widgets/template_preview.dart` — canvas-accurate composition preview.
- `lib/screens/template_gallery_screen.dart` — template selection.
- `lib/screens/crop_editor_screen.dart` — manual crop adjustment.
- `BoothController` now owns the selected template, per-slot crop decisions and metadata persistence.

### Python

- `windows_bridge/app/templates.py` — matching template definitions and versions.
- `windows_bridge/app/template_render.py` — canonical Pillow template renderer.
- `windows_bridge/app/main.py` — optional template/crop metadata, validation and renderer selection.
- `windows_bridge/app/db.py` — persists `template_version` and `crops_json` for restart/reprint.

---

## 2. Template schema

A template defines:

| Field | Meaning |
|---|---|
| `id` | Stable template ID |
| `name`, `description` | Operator-facing metadata |
| `version` | Positive integer; unsupported versions rejected |
| `canvas_width/height` | Design canvas |
| `output_width/height`, `dpi` | Output contract |
| `background_color` | ARGB/hex background |
| `repeat_x`, `panel_width` | Optional repeated panel layout |
| `slots` | Slot ID, source image index, position, size, border |
| `texts` | Event title/date/literal text position and style |

Built-ins:

1. **Classic 2×6 Duo** (`strip_2x6_3up_v1`, v1) — unchanged default geometry: 1200×1800, two 600×1800 panels, slots at y=100/649/1198, 552×531.
2. **Editorial Collage** (`collage_4x6_v1`, v1) — hero + two supporting frames, cream background.
3. **Minimal Stack** (`minimal_4x6_v1`, v1) — three full-width white-space frames.

All output at **1200×1800, 300 dpi**. Template validation rejects duplicate slots, invalid image indices, out-of-canvas slots/text, bad versions and invalid repeat geometry.

---

## 3. Crop modes

### Smart Crop

1. Faces detected locally with Apple Vision.
2. Only confidence ≥ 0.5 is accepted.
3. Union of all faces is expanded with margins + headroom.
4. Crop is expanded to the destination slot pixel aspect.
5. All faces must fit inside the crop with margin.
6. Any boundary condition, no face, low confidence, detection failure or impossible union falls back to **Fit/Contain**.

### Fit / Contain

- Crop rect is `0,0,1,1`.
- Full original preserved; destination may letterbox.
- No re-encode of the original.

### Manual Crop

- Normalized crop rectangle plus zoom/offset.
- Zoom 1–3, horizontal/vertical offsets −1..1.
- Crop is clamped and normalized; invalid aspect/outside values rejected.
- Operator sees a dimmed source with a bright crop boundary.
- Reset to Smart / Reset to Fit actions.
- Apply persists crop metadata separately.

Crop metadata includes original image ID, template ID/version, slot ID, mode, normalized rect, zoom/offset, face count, fallback reason and timestamp.

---

## 4. Vision integration

- Swift `VisionFacePlugin` in `ios/Runner/AppDelegate.swift`.
- Channel `com.terabooth/vision`, method `detectFaces`.
- Uses `VNImageRequestHandler` with `UIImage` orientation mapping.
- Converts Vision bottom-left boxes to normalized **top-left** boxes.
- Local only; no network, cloud or paid SDK.
- Detector abstraction:
  - `VisionFaceDetector`
  - `FixtureFaceDetector` for deterministic tests
  - `NoopFaceDetector` for unsupported platforms

### Actual Vision result

A public-domain Abraham Lincoln portrait fixture was added under `assets/fixtures/face_lincoln.jpg` (Wikimedia Commons, public domain). The real Vision integration test was executed on the iPad A16 Simulator and returned:

```text
Could not create inference context
```

The test now explicitly skips with that actual error. **No face-detection success is claimed on this simulator.** The app catches the error and falls back to Fit; the live integration job recorded all three crops as `fit`. Physical iPad Vision remains unverified.

---

## 5. Bridge contract changes (backward compatible)

`POST /v1/print-jobs` accepts optional metadata:

```json
{
  "template": "strip_2x6_3up_v1",
  "template_version": 1,
  "crops": [
    {
      "image_id": "img0",
      "slot_id": "photo_1",
      "mode": "smart|fit|manual",
      "rect": {"x": 0.1, "y": 0.1, "w": 0.7, "h": 0.7},
      "zoom": 1.0,
      "offset_x": 0.0,
      "offset_y": 0.0,
      "face_count": 2
    }
  ]
}
```

Compatibility rules:

- Existing clients with no `template_version`/`crops` use the legacy `strip_2x6_3up_v1` path.
- Default template with no crops still uses existing `compose_strip()` geometry.
- Default template with crops uses the template renderer; dimensions/geometry remain 1200×1800 / two 600×1800 panels.
- Non-default templates require `template_version`.
- Unknown template, unsupported version, unknown slot, duplicate slot, mismatched image/slot, invalid mode or out-of-bounds crop → **422**.
- Images are resolved from stored job image IDs/paths; no client-supplied paths.
- `template_version` and `crops_json` persist in SQLite for restart/reprint.
- Idempotency and QR/original delivery are unchanged.
- Unknown jobs are never auto-resubmitted.

---

## 6. Rendering consistency

- Flutter preview and Pillow renderer use the same slot coordinates, repeat panels, backgrounds, text positions, crop rect semantics and fit/contain rule.
- Default slot geometry asserted in both Flutter and Python tests:
  - 1200×1800 canvas, 300 dpi
  - two 600×1800 panels
  - slots `(24,100,552,531)`, `(24,649,552,531)`, `(24,1198,552,531)`.
- Live macOS bridge job:
  - `job_97516cda64eb47638ffa1d3522b8dea1`
  - default template v1, `fit` crops
  - completed/confirmed with mock printer
  - JPEG 1200×1800 at 300 dpi.

---

## 7. Tests and results

| Check | Result |
|---|---|
| `flutter analyze` | **No issues** |
| `flutter test` | **75 passed** |
| `pytest -q` | **20 passed** |
| `flutter build ios --simulator` | **Success — 145 MB** |
| Live MacBook FastAPI mock integration | **PASS** |
| Real Apple Vision fixture | **SKIPPED — simulator inference context unavailable** |
| Windows runtime | **Not tested** |
| Physical printer | **Not tested** |

Coverage added:

- Template validation, geometry, versioning and three built-ins.
- Gallery selection and session lock after capture.
- Smart crop multiple faces, boundaries, low confidence/no faces/failure, fit fallback.
- Manual crop normalization, bounds validation.
- Crop metadata persistence and original-byte immutability.
- Crop editor UI controls.
- Bridge legacy requests, crop requests, new templates, unsupported versions, invalid crops.
- Live HTTP workflow with template/crop metadata.
- Existing three-photo/default workflow regression.

---

## 8. Known limitations

- Real Vision detection is **not verified** on simulator; native physical iPad test remains.
- Face detection is heuristic; no perfect-face guarantee.
- No manual drag/pinch on the source image yet; sliders provide zoom/position and crop boundary.
- Manual crop editor updates one photo at a time; no multi-slot advanced editor.
- New templates are not physically printed or cut.
- No Windows execution of the new renderer.
- No Template Engine image overlays/assets beyond text/background/borders yet; the data model is extensible.
- The public-domain Lincoln fixture is test-only.

---

## 9. Next work

1. Physical iPad Vision fixture and face-crop validation.
2. Windows/Pillow rendering + DNP physical validation for all templates.
3. Template overlay assets/Smart Crop refinement if required.
4. Physical client sign-off on template visual design.
5. Keep GIF and CascableCore out of scope.
