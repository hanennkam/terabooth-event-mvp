# Phase 2F — Animated GIF Generation & Guest Delivery

> **Software-only phase.** No Windows, DNP, physical iPad or camera validation.
> **GIF is independent of printing.** Print geometry and print status are unchanged.

---

## 1. Architecture

### Bridge

- `windows_bridge/app/gif_render.py` — Pillow GIF generator and validator.
- `windows_bridge/app/main.py` — independent background generation, authenticated API and guest endpoints.
- `windows_bridge/app/db.py` — persisted GIF state/path/error/bytes.

### Flutter

- `PrintJob.gifState` parsing.
- `BridgeClient.gif(jobId)` authenticated fetch.
- `BoothController` independent GIF loading after print status (never awaited by print flow).
- `PrintScreen` GIF status card and animated preview.
- Guest page remains the same QR URL, with an additional GIF link.

---

## 2. GIF specification

| Property | Value |
|---|---|
| Source | Exactly the 3 approved originals from the same job/session |
| Frames | 3, in capture order |
| Frame size | **360×540** portrait (2:3) |
| Frame duration | **1,800 ms** |
| Cycle | **5.4 s** |
| Loop | **Infinite (`loop=0`)** |
| Format | **GIF89a** |
| Fit | Fit/Contain; full photo preserved; consistent dark background |
| Original files | Never modified or re-encoded |

Pillow workflow:

1. Open each original.
2. `ImageOps.exif_transpose` for orientation.
3. Convert RGB.
4. `ImageOps.contain(360×540)`.
5. Center on a consistent `#101114` frame.
6. Convert to a 256-colour adaptive palette.
7. Save with `save_all`, `duration=1800`, `loop=0`, `optimize=True`, `disposal=2`.
8. Reopen and validate before publishing.

The generated file is written to a temporary `.part` file and atomically renamed.

---

## 3. Storage and database

Jobs gained:

- `gif_state` (`pending|processing|ready|failed`)
- `gif_path`
- `gif_error`
- `gif_bytes`
- `gif_updated_at`

The GIF is stored under the job directory as `guest.gif`. The database stores only server-generated paths, never client-supplied paths. Ready GIFs survive bridge restarts.

Generation is claimed atomically with:

```sql
UPDATE jobs SET gif_state='processing'
WHERE id=? AND gif_state='pending'
```

Only one generator can proceed. A completed ready GIF is never regenerated.

---

## 4. API contract

### Authenticated

`GET /v1/print-jobs/{job_id}/gif`

- `200 image/gif` when ready.
- `409` while pending/processing.
- `404` when unavailable/failed/unknown job.
- Existing bearer auth when configured.

### Guest

`GET /d/{token}/gif`

- Same HMAC delivery token as photos/strip/QR.
- `200 image/gif` when ready.
- `409` while pending.
- `404` invalid/expired/unavailable.
- No new unauthenticated file access.

`job_json` includes `gif_state` and `gif_bytes`; existing fields are unchanged.

### Failure isolation

- GIF generation is scheduled separately from print composition/submission.
- Exceptions set only `gif_state=failed`; the print job continues independently.
- Original/photo/strip/QR routes remain available.
- No automatic GIF retry and no print resubmission.
- Print submission/completion never waits for GIF.

---

## 5. Guest page

The existing `/d/{token}` page now shows:

- Photo 1
- Photo 2
- Photo 3
- **Download your photostrip**
- **Download animated GIF** when ready

When pending: “Your animated GIF is still being prepared. Photos and the photostrip are ready now.”

When failed: “The animated GIF could not be prepared. Your photos and photostrip are still available.”

The GIF has its own download link and does not replace the strip or originals.

---

## 6. Flutter operator experience

- GIF status card shows Preparing / Ready / Unavailable.
- Animated preview uses `Image.memory` (real GIF playback, no extra controls).
- **View animated GIF** opens a larger playback dialog.
- GIF fetch is independent of composition fetch and print state.
- `_maybeLoadGif()` runs after job updates using the authenticated endpoint; it never blocks approval, print submission or terminal print state.
- GIF bytes are kept separate from JPEG composition bytes.
- Resetting the booth clears GIF state.

---

## 7. Actual test evidence

Live macOS FastAPI mock job:

| Field | Value |
|---|---|
| Job | `job_38d1e31bd10642fc81ac0f2189d9b9e2` |
| Print | `completed` / `confirmed` |
| GIF state | `ready` |
| GIF format | GIF89a |
| Size | **360×540** |
| Frames | **3** |
| Durations | **1800 / 1800 / 1800 ms** |
| Loop | **0 (infinite)** |
| File size | **281,515 bytes** |
| Authenticated `/v1/.../gif` | **200** |
| Guest `/d/<token>/gif` | **200** |
| Guest page | contains **Download animated GIF** |
| Original/strip downloads | still available |

Pillow reopened the file and inspected frame count, size, durations, loop metadata and GIF89a header. The test also samples frame centre colours to verify source order (red, green, blue fixtures).

---

## 8. Tests

| Check | Result |
|---|---|
| `flutter analyze` | **No issues** |
| `flutter test` | **78 passed** |
| `pytest -q` | **28 passed** |
| `flutter build ios --simulator` | **Success — 145 MB** |
| Live MacBook FastAPI GIF integration | **PASS** |
| Windows runtime | **Not tested** |
| Physical printer | **Not tested** |

Coverage includes:

- exactly 3 frames and source order
- 1,800 ms durations
- loop=0
- 360×540
- GIF89a
- real Pillow reopen/inspection
- EXIF-oriented source handling
- missing/corrupt source failure
- print failure does not block GIF
- claim/duplicate protection
- atomic output
- authenticated API
- guest HMAC access
- expired token
- restart persistence
- backward-compatible jobs without GIF use

---

## 9. Known limitations

- No Windows execution or DNP physical validation.
- No physical iPad/iPhone download test.
- The guest page and GIF were validated over HTTP on macOS; no physical phone.
- GIF generation is per print job, not a separate cross-job cache; duplicate/idempotent submissions still return the same job.
- If a pending GIF generation is interrupted by a bridge crash, its state may remain `processing`; ready GIFs persist. No automatic recovery is claimed.
- Identical source frames can be collapsed by the GIF encoder; such a file fails the exactly-3-frame validation and is reported unavailable rather than silently published.
- GIF is Fit/Contain only; it does not use face-aware cropping.
- No video, cloud processing or paid SDK.

---

## 10. Remaining physical validation

- Windows Bridge GIF generation and guest delivery.
- Physical iPad operator preview/playback.
- Physical iPhone/Android guest download and file open.
- DNP print workflow regression alongside GIF.
- LAN/firewall and guest token expiry under real conditions.

**No Windows, camera, printer or physical-device readiness is claimed.**
