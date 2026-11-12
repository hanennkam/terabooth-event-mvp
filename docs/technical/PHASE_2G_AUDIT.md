# Phase 2G — Final Software Audit

> Initial audit before QA changes. Hardware remains unavailable; this is a software/simulator audit.

## 1. Current architecture

```
iPad Flutter
  Event catalog + settings (local JSON)
  Template gallery / crop editor / composition preview
  BoothController
    CameraPipeline -> mock or native camera service
    StorageService (originals, metadata, recovery)
    BridgeClient (multipart submit, status, composition, GIF)
  PrintScreen (print/composition/GIF/QR)

Windows Bridge (FastAPI/Python/Pillow/SQLite)
  /v1/print-jobs, status, artefact, GIF, reprint
  template + crop renderer
  independent GIF generator
  guest /d/{token}, originals, strip, GIF, QR
  mock/spooler/hotfolder printer
```

The default template remains `strip_2x6_3up_v1`: 1200×1800 at 300 dpi, two 600×1800 panels.

## 2. Completed features

- Event create/select, template gallery, three built-ins, crop metadata/preview.
- Three-photo capture, Retake All only, review, approve.
- Idempotent print submission, status polling, composition, reprint.
- Print success/failure/unknown distinction; no auto-resubmit.
- QR guest page with originals, strip, QR and animated GIF.
- Independent 3-frame GIF, HMAC guest access, atomic persistence.
- Settings/bridge health/diagnostics, local event/session data.
- Session metadata, originals, crop/template/approved fields.

## 3. Incomplete / deferred

- Windows runtime, DNP printing, physical iPad, Canon EOS R, physical guest phone.
- Real Vision face detection on physical iPad (simulator inference unavailable).
- No automatic print-job status restoration after app termination; operator must inspect bridge/QR.
- No automatic recovery of an **approved but unsubmitted** app session; approved sessions are intentionally not restored as review.
- No download-count analytics.
- FastAPI startup uses deprecated `on_event` (functional; warning only).

## 4. Findings

| ID | Severity | Finding | Resolution |
|---|---|---|---|
| G1 | **Critical** | Mock printer completion was shown as “Printed — take your strip” and header “Complete” for failed/unknown. | **Fixed**: server exposes `printer_mode`; UI shows “Mock print complete — no physical print”; failed/unknown show “Needs attention”. |
| G2 | **Critical** | Restart after GIF `processing` could leave GIF stuck forever. | **Fixed**: startup recovery validates existing artefacts, releases stale processing claims, regenerates only safe jobs, caps attempts, cleans abandoned temp files. |
| G3 | **High** | Metadata write after accepted print could throw and put app into error, hiding the accepted job. | **Fixed**: non-fatal post-submission metadata write; job continues polling. |
| G4 | **High** | Guest DB `expires_at` was not checked; only HMAC expiry. | **Fixed**: both HMAC and persisted expiry enforced. |
| G5 | **High** | No safe local review recovery after app restart. | **Fixed**: explicit opt-in restore of latest complete **unsubmitted** session; approved sessions excluded. |
| G6 | **High** | API token compare was not constant-time. | **Fixed** with `secrets.compare_digest`. |
| G7 | **Medium** | GIF startup recovery uses deprecated FastAPI `on_event`. | Deferred; functional, warning only. |
| G8 | **Medium** | No job-ID persistence/status restoration after app termination. | Deferred; operator must check bridge; no auto-resubmit. |
| G9 | **Medium** | Raw generic error strings can appear in a few operator surfaces. | Partially addressed through typed bridge errors; not fully normalized. |
| G10 | **Medium** | Vision detection cannot run on the available simulator. | Deferred to physical iPad; safe Fit fallback verified. |
| G11 | **Medium** | Identical source frames collapse to fewer GIF frames. | Validator rejects; GIF is marked unavailable rather than publishing a false animation. |
| G12 | **Low** | No guest download counts. | Explicitly disclosed in UI. |
| G13 | **Low** | Restore only offers the latest unsubmitted session for the selected event. | Intentional safety scope. |
| G14 | **Low** | Uvicorn access logs can contain guest token URLs. | Existing log behavior; guest responses do not expose secrets. |

## 5. Recommended fixes

**Implemented in Phase 2G:** G1–G6.

**Deferred:** G7–G10 and hardware-dependent validation. No architecture rewrite, no print geometry change, no camera topology change.

## 6. Deferred hardware-dependent work

- Windows bridge execution, firewall, spooler/HFP.
- DNP 4×6/2×6 physical print and 20-job reliability.
- Apple signing/physical iPad install.
- CascableCore/EOS R capture.
- Physical iPhone/Android guest QR/download.
- Real Apple Vision on physical iPad.
