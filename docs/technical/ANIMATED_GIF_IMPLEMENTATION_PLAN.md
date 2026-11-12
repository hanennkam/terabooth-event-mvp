# Animated GIF Delivery — Implementation Plan

> **Planning only. Not implemented in Phase 2A.** No GIF endpoint or file exists today.
> No new dependency is required: Pillow is already installed on Windows.

---

## 1. Current bridge audit

| Area | Today |
|---|---|
| Input validation | Pillow-decodable images (not explicitly JPEG-only); client sends JPEG; three images per job |
| Print artefact | `jobs/<job_id>/artefact.jpg` (JPEG) |
| QR page | Lists originals and links `/d/{token}/strip` |
| Strip endpoint | `FileResponse(..., media_type="image/jpeg")` |
| GIF support | **None** |
| Database | No GIF path/column |
| iPad | Uploads JPEG originals; no GIF generation |
| Internet | None required |

`FileResponse` can serve non-JPEG content types, but there is currently no GIF generation, endpoint, page link or content-type handling. The current server accepts any Pillow-decodable input (PNG is used by the mock); Phase 2C should explicitly define whether input is JPEG-only or format-aware. GIF is an **output** artefact, not a camera input.

---

## 2. Proposed ownership

**Windows generates and serves the GIF.**

- Originals already exist on Windows after a job is accepted.
- Pillow is already installed and licensed; GIF encoding adds no dependency.
- QR delivery already lives on Windows; no iPad GIF package or upload round trip.
- iPad remains capture/review/approval only.
- No internet dependency.

---

## 3. Behaviour

- Source: the **three approved original images** for the job, in slot order.
- Sequence: photo 1 → photo 2 → photo 3 → loop.
- 3 frames; continuous loop (`loop=0`).
- Target cycle: **5–6 seconds** total. Proposed per-frame duration: **1800 ms** (5.4 s cycle); configurable.
- Preserve aspect ratio; **Fit/Contain** into a fixed frame (no stretching). Background from template/white.
- Suggested output size: **360×540** (4×6 aspect) for phone-sized delivery; no change to print dimensions.
- Quantize/optimize palette; target practical file size (measure; aim **<2 MB**, lower if possible).
- Genuine `.gif` file; verify frame count/durations/loop before exposing.
- Generate from copies; **never modify originals**.
- If GIF generation fails, originals and JPEG strip remain available; log error; no print failure.
- GIF generation must not block printing; run as a separate post-validation task.

### Why not on iPad

- Would add a GIF encoder dependency to Flutter.
- QR delivery is Windows-hosted; the GIF must be served there anyway.
- Windows already has the approved originals and Pillow.
- Keeps iPad focused on capture/review and avoids another upload.

---

## 4. Generation plan (Windows)

Proposed file: `jobs/<job_id>/animation.gif` (deterministic; no DB migration required initially).

1. After job images are validated and stored, load the three originals with Pillow.
2. Apply EXIF orientation (`ImageOps.exif_transpose`); convert RGB.
3. Fit/contain each into 360×540 (or configured frame), preserving aspect; white/background padding.
4. Save:
   ```python
   frames[0].save(
       path,
       format="GIF",
       save_all=True,
       append_images=frames[1:],
       duration=1800,       # per frame; 3 × 1800 = 5.4 s
       loop=0,              # infinite
       optimize=True,
       disposal=2,
   )
   ```
5. Reopen the GIF with Pillow to verify:
   - `format == "GIF"`
   - `n_frames == 3`
   - total duration ~5.4 s
   - loop metadata
   - non-zero size
6. Expose only after verification. If verification fails, delete partial GIF and log.

Pillow GIF is palette-based; banding is possible. Assess quality/size; if unacceptable, consider alternate frame sizing/quantization, not a new dependency.

---

## 5. QR delivery changes

- Add `GET /d/{token}/gif`:
  - require valid HMAC token + DB binding;
  - find `jobs/<job_id>/animation.gif`;
  - if missing/not ready: `404` with a clear “not ready” status (page should not show a broken link);
  - if present: `FileResponse(media_type="image/gif", filename="terabooth.gif")`.
- Add a page link only when the GIF exists and is verified:
  **“Download animated GIF”**.
- Keep existing original/strip endpoints unchanged.
- `job_json` may include `gif_url`/`gif_ready` as an additive field; not required for compatibility.
- Token expiry (24 h default) applies equally.
- No internet/cloud; all local.

No change to print layout or `artefact.jpg`.

---

## 6. Scheduling / failure handling

- Generate GIF after images are stored, before or alongside printing:
  - `schedule(generate_gif(job_id))` or a dedicated background task.
- Print must not wait for GIF; QR page can show “GIF preparing” until ready.
- If GIF generation fails:
  - log the exception;
  - do not mark the print job failed because of GIF;
  - originals/strip still downloadable;
  - optionally expose `gif_error` for the operator.
- On bridge restart, a job with no GIF can regenerate on demand or at page request; avoid duplicate generation with a lock/deterministic path.
- Do not hold database locks during encoding.

---

## 7. Dependencies / licensing

| Dependency | Purpose | Licence/cost | Status |
|---|---|---|---|
| Pillow | Decode JPEG, fit, GIF encode | PIL/HPND permissive | Already installed |
| FastAPI `FileResponse` | Serve GIF | MIT/BSD-style | Already installed |
| Flutter/iPad | No new dependency | — | No change |
| ffmpeg/ImageMagick | Not needed | — | Do not add |

No large or unreliable dependency is required.

---

## 8. Tests

Python:

- Three-frame GIF from three distinct images; `format == GIF`.
- Frame count 3; durations sum 5.4 s; loop=0.
- Output dimensions 360×540; aspect preserved (no stretch).
- File size practical; record.
- Original bytes unchanged.
- QR endpoint returns `image/gif`, correct bytes.
- Missing GIF returns 404 while page hides link.
- Invalid/missing source image produces explicit error, print unaffected.
- Token expiry/invalid token applies.
- Bridge restart regeneration path.
- Existing JPEG strip/original/print tests unchanged.

Physical/device:

- Guest phone opens GIF over LAN with WAN off.
- iOS/Android animation loop.
- File size/download time on event router.
- Confirm no print layout change.

---

## 9. Implementation sequence (Phase 2C)

1. Add GIF service/function + tests; no endpoint yet.
2. Add endpoint and page link; tests with WAN-local HTTP.
3. Schedule generation; ensure print unaffected.
4. Verify on phones with WAN off.
5. Optional: configurable frame size/duration; do not overbuild.

**Do not start before the retake fix and event-critical print/QR gates are stable.** GIF is an enhancement, not a 14 November blocker.

---

## 10. Event risks

- GIF file size/download time on congested guest Wi-Fi.
- Palette/quality degradation; test visually.
- GIF generation adds CPU during printing; run separately, monitor.
- Guest browser/phone GIF loop support; test both.
- Additional code path must not delay or fail printing.
- No physical phone/router test yet.

---

## 11. Components summary

| Component | Location |
|---|---|
| GIF generation | **Windows** |
| GIF storage | Windows `jobs/<id>/animation.gif` |
| QR GIF endpoint/page | **Windows** |
| GIF download | Guest phone over local LAN |
| iPad changes | **None required** |
| Internet | **None** |
| Print layout | **Unchanged** |
