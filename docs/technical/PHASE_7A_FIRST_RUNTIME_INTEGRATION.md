# Phase 7A — First Complete Runtime Integration

## Overall result

**BLOCKED before physical camera testing.**

The production app, Bridge and synthetic JPEG upload path are already implemented
and previously verified. The missing blocker is native Cascable licensing/signing
for the physical EOS 60D path, not a camera-pipeline code defect.

No physical camera action or print was performed.

---

## 1. Existing verified evidence reused

| Component | Evidence |
|---|---|
| Production iPad app | Release build installed/launched; Home/Events/Settings verified |
| CascableCore integration source | Camera adapter, Live View, original-only capture, JPEG validation implemented |
| Bridge LAN health | Authenticated health previously verified from iPad |
| Synthetic iPad JPEG upload | Physical iPad upload completed; Bridge completed; original hash MATCHED; 1200×1800 artefact retrieved |
| Printing | Driver-managed backend implemented; physical 4×6 calibration still blocked |
| Tests | 77 Bridge tests passed (Phase 6I full run); targeted printer tests 22 passed |

No need was found to repeat those completed checks.

---

## 2. Current physical/runtime state

- Installed apps:
  - `com.terabooth.teraboothIpad` — Terabooth Ipad
  - `com.terabooth.personalsigningprobe6b3` — Personal Signing Probe
- Bridge: `192.168.8.192:8787` reachable; unauthenticated `/v1/health` returns 401.
- Production app launches (previous evidence).
- Production camera setting: `USE_NATIVE_CAMERA` default **false**.
- Production build contains no Cascable demo licence.
- Demo target has `CASCABLE_DEMO` and the demo licence, but its bundle ID
  `se.cascable.CascableCoreiOSDemo` still has no provisioning profile; only two
  explicit Personal Team profiles exist (production and probe).
- Xcode has only Ahmad Suhaib Personal Team; no paid team.

---

## 3. Exact blocker

To use the real EOS 60D, the app needs:

```text
USE_NATIVE_CAMERA=true
+ a valid CascableCore licence for the selected bundle ID
```

Current combinations:

| Build | Bundle ID | Licence | Signing | Camera |
|---|---|---|---|---|
| Production | `com.terabooth.teraboothIpad` | **none** | production profile | licence missing |
| Cascable demo | `se.cascable.CascableCoreiOSDemo` | demo | **no profile** | not installable |
| Safe probe | probe ID | none | probe profile | no camera |

The demo licence is applied only in `#if CASCABLE_DEMO`. The demo bundle cannot
be provisioned because the Personal Team cannot register that vendor ID and no
wildcard profile is available.

No code change can bypass this without changing the bundle ID, licence, or
authentication/provisioning — all prohibited.

---

## 4. Not tested

- Canon EOS 60D USB connection through the production app
- Camera detection in production
- Live View in production
- One real JPEG capture / original transfer
- Camera → ImageIngestor → Storage → Bridge with a real image
- Windows receipt of the real captured image
- QR guest delivery of that real capture
- Full event/session capture-to-delivery workflow
- Physical print (not authorized)

The existing synthetic-import upload evidence validates the app/Bridge/ingestion
path, but **not the physical camera**.

---

## 5. Shortest unblock path

1. Obtain a valid native camera licence for the production bundle **or** make the
   demo bundle provisionable:
   - preferred: production Cascable licence for
     `com.terabooth.teraboothIpad`;
   - alternatively: an available wildcard provisioning profile covering
     `se.cascable.CascableCoreiOSDemo`.
2. Build one test Release with `USE_NATIVE_CAMERA=true` and the matching licence.
3. Install, connect the EOS 60D USB, verify detection and Live View.
4. Capture **one** real JPEG and verify hash/validation.
5. Approve/upload the real capture to the Windows Bridge.
6. Verify Windows receipt, artefact/QR delivery, then stop.
7. Keep MockPrinter; no physical print without separate authorization.

Do not change the production Bundle ID, demo Bundle ID, certificate, or licence
to work around provisioning.

---

## 6. Safety

| Check | Result |
|---|---|
| Physical camera action | **NONE** |
| Physical print | **NONE** |
| Code/architecture changes this phase | **NONE** |
| Bundle IDs/licences/signing changed | **NO** |
| Customer data changed | **NO** |
| Camera architecture changed | **NO** |
| Production remains MockPrinter | **YES** |
| Spooler | **disabled** |

**Stopped at the native Cascable licence/provisioning gate.**
