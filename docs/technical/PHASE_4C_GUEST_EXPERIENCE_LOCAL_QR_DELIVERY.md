# Phase 4C — Guest Experience, Local Gallery & QR Delivery

## Overall result

**PASS for the implemented local guest vertical slice.**

The existing bridge delivery path was extended rather than replaced:

- Session-scoped, short opaque guest tokens
- Revocable/regenerable links with database expiry
- Mobile-first guest gallery with previews and downloads
- Individual originals, branded strip, GIF and ZIP download
- Session asset manifest and persisted manifest file
- GIF generation for 1, 2, 3 and 4 approved photos
- LAN-reachable QR URL resolution and non-loopback binding
- Operator QR card with copy, regenerate and revoke actions

Verification:

- **124 Flutter tests passed**
- `flutter analyze`: **No issues**
- **47 Python bridge tests passed**
- iOS simulator build: **PASS**
- Real non-loopback HTTP smoke test: **PASS**
- No physical camera, iPad, guest phone, Windows laptop or DNP printer used

---

## 1. Architecture and reused components

The existing architecture was retained:

- Flutter -> `BridgeClient` -> local FastAPI bridge -> SQLite jobs/delivery tokens
- Approved session job is the single source of guest assets
- Existing job images, `artefact.jpg` and `guest.gif` are reused
- Existing per-job delivery token table and TTL are reused
- Existing `gif_render.py` pipeline was extended, not replaced
- Existing `PrintScreen` QR card was extended, not duplicated

No second gallery system, asset store or session lifecycle was introduced.

Asset flow:

```text
capture -> approved review -> print job accepted
  -> originals stored in job input
  -> branded strip composed in job directory
  -> GIF generated from approved images in order
  -> asset manifest written atomically
  -> delivery token + QR available
  -> guest opens /d/<token>
  -> gallery/manifest/zip/assets served only for that job
```

---

## 2. Guest gallery

`GET /d/{token}` now renders a mobile-first gallery:

- Event title/date and branding colour/tagline/logo
- Approved photo cards with inline previews
- Full-size photo download links
- Branded strip preview/download
- GIF preview/download only when `gif_state == ready`
- “Download all photos” ZIP
- Pending/failed GIF notices
- No operator controls, filesystem paths or other sessions
- `Cache-Control: no-store`, `nosniff`, `no-referrer`, CSP headers

Download-all ZIP contains only the authorized job's originals, strip and ready
GIF.

---

## 3. API endpoints

### Operator/authenticated

```text
POST /v1/print-jobs
GET  /v1/print-jobs/{id}
GET  /v1/print-jobs/{id}/artefact
GET  /v1/print-jobs/{id}/gif
POST /v1/print-jobs/{id}/delivery/revoke
POST /v1/print-jobs/{id}/delivery/regenerate
```

### Guest/token-scoped

```text
GET /d/{token}
GET /d/{token}/original/{image_id}?inline=1
GET /d/{token}/strip?inline=1
GET /d/{token}/gif?inline=1
GET /d/{token}/download.zip
GET /d/{token}/manifest.json
GET /d/{token}/branding-logo
GET /d/{token}/qr.png
```

All asset lookups compare the requested job/image against the token's job.
Image IDs and paths are server-side; guest URLs never contain filesystem paths.

---

## 4. QR and token security model

- New guest tokens are `secrets.token_urlsafe(24)` opaque secrets (128 bits).
- Tokens are stored hashed in `delivery_tokens`; the raw token is only in the
  job's delivery field for link regeneration.
- HMAC-signed legacy tokens remain accepted for backward compatibility.
- URL is `/d/<token>` (short opaque path).
- Access is one-job/session scoped.
- Expiry is enforced both by token row and request time; default 24 hours.
- Revocation deletes the delivery row and clears the job delivery token.
- Regeneration creates a new random token and invalidates the old one.
- Invalid/revoked/expired tokens return 404.
- Guest paths are redacted in logs by the existing redaction layer.
- QR URLs are generated from a non-loopback LAN root; `localhost`,
  `127.0.0.1`, and `::1` are rejected for QR use.
- `TERABOOTH_PUBLIC_BASE_URL` can pin the LAN URL; otherwise the request Host or
  a discovered LAN IPv4 address is used.
- The bridge runs with `--host 0.0.0.0` in the documented run commands.

---

## 5. LAN and offline behavior

- Guest pages/assets are served entirely by the local bridge.
- No internet, cloud storage, analytics or third-party auth is used.
- A non-loopback HTTP smoke test was run against uvicorn bound to `0.0.0.0`
  using the machine's LAN address; health, gallery, manifest and ZIP returned
  HTTP 200.
- This is **not** a physical-phone validation. Router client isolation, Windows
  Firewall inbound rules and AP isolation can still block real phones.
- On multi-NIC machines automatic LAN discovery can pick the wrong interface;
  set `TERABOOTH_PUBLIC_BASE_URL` explicitly.

---

## 6. GIF generation

`gif_render.py` now supports **1–4 frames**:

- Frame order follows the job's approved image order.
- 1 photo produces a valid single-frame GIF still (downloadable; not a
  multi-frame animation).
- 2–4 photos produce an animated GIF.
- 360×540 consistent frames, 1800 ms, loop=0, adaptive palette, optimized.
- Missing/invalid source images raise explicit errors.
- Generators write a temp file, validate, then atomically replace.
- Regeneration validates/reuses existing output; original images are read-only.
- Recovery validates existing processing/ready GIFs using the job's actual image
  count rather than hard-coded three.
- GIF state remains persisted (`pending/processing/ready/failed`) and is
  recoverable after restart.

**Known limit:** one-photo sessions produce a still GIF; the UI's existing
“Download animated GIF” wording may be read broadly, but no fake multi-frame
animation is created.

---

## 7. Asset manifest

`GET /d/{token}/manifest.json` and persisted
`data/jobs/<job>/manifest.json` include:

- schema, session ID, event ID, job ID
- event title/date and public branding metadata
- approved originals with ID/order, MIME, bytes, download URL (response only)
- strip availability/MIME/bytes
- GIF state, error and asset when ready
- creation/update timestamps

Manifest disk writes use a temp file + atomic replace. No absolute paths or
logo paths are exposed. Old jobs without branding remain compatible.

---

## 8. Operator workflow

`PrintScreen` now provides:

- QR and guest URL once the job/approval exists
- Event/session context
- Guest access status
- Copy link
- Regenerate link (confirmation; old link stops working)
- Revoke access (confirmation)
- Asset readiness text for photos/strip/GIF
- Regenerate action when access was revoked
- No QR for an incomplete/unapproved session because no job exists yet

BridgeClient/controller support revoke and regenerate and persist the resulting
delivery URL state.

---

## 9. Tests and build

### Flutter

```text
flutter analyze
No issues found!

flutter test --concurrency=1
124 tests passed
```

Existing Phase 4B tests remain green. New guest-delivery client test covers
revoked link clearing and regenerated non-loopback URL parsing.

### Bridge

```text
.venv/bin/python -m pytest -q
47 passed
```

New Phase 4C tests cover:

- Guest manifest and ZIP contents
- Cross-session image denial
- Path traversal/directory-listing attempts
- Token revocation, regeneration and expiry
- Non-loopback QR URL
- 1/2/3/4-frame GIF generation
- Frame ordering
- Missing/invalid sources
- Regeneration and original INTEGRITY
- Existing gallery/GIF/recovery tests

### Real LAN smoke

A temporary uvicorn bridge bound to `0.0.0.0` was reached through the machine's
LAN address:

```text
LAN_IP 192.168.8.190
HEALTH 200
URL_NON_LOOPBACK True
PAGE 200
MANIFEST 200
ZIP 200
ORIGINALS 2
GIF ready
```

This validates non-loopback service/API access; it is not a physical guest-phone
test.

### Build

```text
flutter build ios --simulator --no-codesign
✓ Built build/ios/iphonesimulator/Runner.app
bundle com.terabooth.teraboothIpad
demo licence absent
MockCameraService default
```

---

## 10. Known limitations

- No physical iPhone/Android guest test, no Windows laptop, no DNP/printer test.
- LAN success can still be blocked by router AP/client isolation or firewall.
- Automatic LAN IP selection is best-effort; pin
  `TERABOOTH_PUBLIC_BASE_URL` for events.
- Guest links are bearer URLs; anyone with the link can access that session
  until expiry/revocation. Tokens are not logged by the bridge redaction layer.
- One-photo GIF is a still GIF.
- ZIP is assembled in memory; appropriate for current image-size limits.
- Manifest is regenerated on request and persisted during composition/GIF work.
- No cloud/analytics; no physical hardware validation claimed.

---

## 11. Recommended next work

1. Test the gallery from a real iPhone and Android phone on the event VLAN.
2. Add Windows Firewall/AP-isolation checks to preflight.
3. Add share-sheet export for operator-side QR links.
4. Consider per-guest (not only per-session) tokens if multiple guests per
   session need separate revocation.
5. Keep printer/DNP work isolated from guest delivery.
