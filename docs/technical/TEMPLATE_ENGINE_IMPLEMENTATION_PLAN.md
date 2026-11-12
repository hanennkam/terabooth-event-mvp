# Template Engine — Implementation Plan

> **Planning only. Not implemented in Phase 2A.** No new dependencies were added.
> Current event print layout remains the fixed `strip_2x6_3up_v1` template.

---

## 1. Current architecture (audited)

| Component | Today |
|---|---|
| iPad | Captures 3 originals, review/retake, approve, uploads JPEGs + metadata |
| Windows bridge | Validates JPEGs, composes fixed 1200×1800 strip, prints, serves QR |
| `windows_bridge/app/compose.py` | Hard-coded 2×6 strip, 3 slots, 4×6 canvas |
| Template selection | None; bridge metadata has a fixed `template` string |
| Face detection | None |
| Manual crop | None |
| Originals | Never modified; stored on iPad and uploaded to Windows |

The existing default template must remain available and byte-compatible for the event.

---

## 2. Proposed component split

| Responsibility | iPad | Windows |
|---|---|---|
| Camera control / originals | **Yes** | No |
| Template selection (operator) | **Yes** | No |
| Face detection | **Yes — Apple Vision** | No |
| Smart-crop computation | **Yes** | No |
| Manual crop adjustment | **Yes** | No |
| Preview rendering | **Yes (local)** | Optional |
| Final print rendering | No | **Yes (Pillow, canonical)** |
| Print / DNP | No | **Yes** |
| QR delivery | No | **Yes** |
| GIF generation | No | **Yes** |

**Decision:** iPad decides the template and crop intent; Windows is the canonical final renderer. This preserves the fixed topology and the existing print authority.

### Why iPad face detection

- Offline, no model download, no internet.
- Apple **Vision** is built into iPadOS; no third-party runtime/licence.
- Multiple face observations are available, satisfying “all faces” better than a single largest-face heuristic.
- Crop rectangles can be computed once on iPad and sent as normalized metadata; Windows does not need a Python CV dependency.

### Why Windows final rendering

- The print compositor and DNP path already live on Windows.
- One canonical renderer avoids two different print results.
- Pillow is already installed; no new print dependency.
- iPad preview can use the same template JSON and a lightweight Flutter canvas; final output remains authoritative.

---

## 3. Template definition

Initial templates: 3-photo layouts only; 2×6 strip and 4×6 print canvas.

Proposed JSON (versioned; backward compatible with the existing template string):

```json
{
  "template_id": "strip_2x6_3up_v1",
  "version": 1,
  "canvas": {"width": 1200, "height": 1800, "dpi": 300},
  "strips": [
    {"x": 0, "width": 600, "height": 1800},
    {"x": 600, "width": 600, "height": 1800}
  ],
  "slots": [
    {"photo": 0, "x": 24, "y": 100, "width": 552, "height": 500},
    {"photo": 1, "x": 24, "y": 618, "width": 552, "height": 500},
    {"photo": 2, "x": 24, "y": 1136, "width": 552, "height": 500}
  ],
  "fit": {"default": "smart_crop", "background": "#ffffff"},
  "text": {"header": true, "footer": "TERABOOTH"}
}
```

The existing `strip_2x6_3up_v1` values are illustrative; the implementation must preserve the current exact geometry.

Per-photo overrides from iPad:

```json
{
  "photo_index": 1,
  "fit_mode": "manual_crop",
  "crop": {"x": 0.12, "y": 0.05, "width": 0.70, "height": 0.85},
  "source_orientation": 6
}
```

`crop` is normalized to the **oriented** source image and is metadata only. Originals are not changed.

---

## 4. Fitting modes

| Mode | Behaviour |
|---|---|
| **Smart Crop** | Detect faces, choose a safe crop containing all detected faces/heads, otherwise fallback to Fit/Contain. |
| **Fit / Contain** | Preserve full image aspect inside the slot; letterbox with template background; no distortion. |
| **Manual Crop** | Operator pans/zooms a normalized crop rectangle; preview updates; clamp to image bounds. |

All modes use the original bytes; no destructive edits or recompression of originals.

### Smart Crop algorithm (iPad)

1. Decode the original at display resolution (not full print size) with EXIF orientation applied.
2. Run Vision face detection (`.accurate` if practical; multiple observations).
3. Expand each face box:
   - add headroom above the face (hair/forehead),
   - add side/chin margin,
   - keep within image bounds.
4. Compute the union of all expanded boxes.
5. Add a safety margin (target 8–12% of the union).
6. Fit the union into the target slot aspect:
   - if the union + margin fits at a reasonable zoom, choose the crop centered on the union,
   - if any face/head would be cut, union is too large, confidence is low, or boxes touch an edge, **fallback to Fit/Contain**.
7. Never use only the largest face; all qualifying faces contribute.
8. Store normalized crop rectangles and a `mode`; do not alter original files.
9. If no faces: Fit/Contain.

### Manual crop

- Operator drags/pinches the image within the slot.
- UI clamps the crop to image bounds and target aspect.
- “Reset to Smart”, “Fit”, and “Reset” actions.
- Metadata is saved per photo; final Windows renderer applies it.

---

## 5. Dependencies / licensing

| Dependency | Purpose | Licence/cost | Decision |
|---|---|---|---|
| **Apple Vision** | Face observations on iPad | Built into iOS/iPadOS; Apple SDK terms; no third-party fee | **Preferred** |
| Flutter `dart:ui`/Canvas | Preview rendering | Flutter SDK | Use |
| Pillow | Windows final composition/crop | PIL/HPND permissive; already installed | Use |
| Google ML Kit face detection | Alternative face detection | Apache 2.0; larger app/model footprint; extra dependency | Not preferred |
| OpenCV / MediaPipe | Alternative face/crop | BSD/Apache; large binary/model; extra deployment | Not preferred |
| TensorFlow Lite face model | Custom detection | Model/licence + size + training risk | Not preferred |

Native Vision requires a small Swift platform-channel plugin; no large Flutter package. It must be tested on the actual iPad; Vision behaviour on real EOS R JPEGs is unverified.

---

## 6. Rendering and data flow

```text
iPad:
  originals + template selection + Vision faces + crop overrides
      -> local preview (Flutter canvas)
      -> upload metadata (template id/version + per-photo crop/mode)
Windows:
  validate JPEGs -> canonical Pillow render using template spec
      -> print + QR artefact + optional GIF
```

- Existing `template` string remains accepted.
- New metadata is additive; old iPad clients still work.
- Windows must reject unknown template IDs with a clear error; fallback to `strip_2x6_3up_v1` only if explicitly configured.
- No print dimension change; existing template geometry is preserved.
- QR/original delivery unchanged; preview is not a print artefact.

### Preview/final consistency risk

Two renderers (Flutter preview, Pillow final) can diverge. Mitigations:

- Share the same JSON spec.
- Keep slot geometry simple rectangles.
- Golden-image/geometry tests on Windows; screenshot/visual checks on iPad.
- Treat Windows output as authoritative; operator reviews the print result.
- Do not claim pixel-identical preview until tested physically.

---

## 7. Files / changes expected (Phase 2B)

**iPad**

- `lib/models.dart` — template/crop metadata.
- new template model/selector + crop editor.
- new native Vision plugin (`ios/Runner/...` + MethodChannel) — no third-party package.
- preview renderer using Flutter canvas.
- metadata sent via `BridgeClient`.

**Windows**

- `app/templates.py` — versioned template specs/validation.
- `app/compose.py` — render from template spec; preserve default geometry.
- `app/main.py` — accept additive metadata, validate.
- tests for geometry, aspect, all fit modes.

No camera pipeline change; originals remain immutable.

---

## 8. Implementation sequence / gates

1. Define template JSON + preserve existing geometry; tests.
2. Windows renderer supports default template from spec (no visual change).
3. iPad template selection + local preview.
4. Native Vision face detection plugin; multiple faces; unit/synthetic tests.
5. Smart Crop + safe Fit fallback.
6. Manual crop editor + metadata round-trip.
7. Windows final render of smart/manual crops; golden tests.
8. Physical iPad/EOS R/print tests.

**Do not start Phase 2B before the retake fix and event-critical print/QR gates are stable.** Template Engine is not required for the 14 November MVP and must not delay camera/printing readiness.

---

## 9. Tests

- Template geometry: 1200×1800, two 600×1800 panels, 3 slots.
- Aspect ratio preserved; no stretching in fit/contain.
- Smart crop union contains all synthetic face boxes; headroom included.
- No-face and low-confidence fallback to contain.
- Faces at edge/too-large fallback.
- Manual crop clamping and reset.
- Original bytes/hash unchanged before/after.
- Windows final render matches spec; default template unchanged.
- Physical: Vision on EOS R JPEGs, multiple faces, portrait/landscape/EXIF, print output.

---

## 10. Event risk

- High scope risk; not required for the core 14 Nov MVP.
- Vision accuracy/lighting/faces, preview/render mismatch, native plugin build/signing.
- Any template work must be behind a feature gate; default event keeps existing strip.
