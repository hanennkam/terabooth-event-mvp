# Phase 2A — Individual Retake Fix & Readiness Audit

> **Scope correction (Phase 1F-R):** individual per-photo retake is **removed from the event MVP**. This document is a historical implementation record; do not use its retake steps in event validation. The event workflow uses **Retake All** only.

> **Status:** individual retake fixed and tested with mock/fake cameras. Template Engine and GIF are **plans only**; not implemented.
> **No physical EOS R/DNP test. CascableCore not installed.**

---

## 1. Retake flow traced

Actual path:

1. `ReviewScreen` — `TextButton` for slot `i` calls `c.retakeOne(i)`.
2. `BoothController.retakeOne(index)` — validates `phase == review`, starts a pipeline capture for `slot = index + 1`.
3. `CameraPipeline.capture` — rejects if disconnected or if that slot is already active/queued; generates a new `captureId`; queues; sets `capturing`.
4. `CameraService.capture(captureId)` — mock or future native adapter.
5. `ImageIngestor.ingest` — validates image, rejects duplicate capture ID, atomically saves a unique original, reopens it.
6. `BoothController` — assigns the returned `CapturedImage` to `photos[index]` only after the pipeline future succeeds; writes session metadata; notifies.
7. `ReviewScreen` — rebuilds from `photos`; other list elements are untouched.

### Root cause found

The slot-replacement code was correct. The **simulator’s `MockCameraService` produced byte-identical images for every capture** (same static PNG content), so a successful retake replaced the slot with the same-looking image. A 3-photo session and any individual retake therefore looked unchanged even though the capture ID/path were new.

A second reliability gap existed: a failed retake moved the entire controller to `BoothPhase.error`, hiding the previously approved image instead of allowing recovery.

### Confirmed mock hashes before fix

Two consecutive mock captures had the same SHA-256 and byte length. After the fix, consecutive mock captures include a capture number and varying accent colour, so retakes are visibly distinct.

---

## 2. Fixes implemented

### Mock camera visible variation

`MockCameraService` now renders:

- `SIMULATED CAMERA / NO EOS R`
- a per-capture `CAPTURE #N`
- one of four accent colours

This makes individual retake observable on the simulator. It remains explicitly simulated; no native camera behavior is faked.

### Retake state hardening

`BoothController` now has:

- `retakingSlot` — the selected slot while a retake is in progress.
- `retakeError` — last retake failure message.

Behaviour:

- Only one retake at a time; retake/retake-all/approve are disabled while a retake is active.
- The previous `CapturedImage` is kept until the new capture is validated, saved and reopened.
- The old original file is never overwritten; new capture ID → new unique file.
- On capture/validation/timeout failure: `photos[index]` remains the previous image, phase remains `review`, and `retakeError` is shown.
- On metadata-write failure after a successful image save: the slot is restored to the previous image; the new original remains as an orphan for recovery.
- Retake success clears the error and replaces only `photos[index]`.
- Late images after timeout are ignored by the pipeline and cannot update any slot.

### Review UI

- Linear progress while retaking.
- Inline error text with the previous image still visible.
- Selected retake button shows a small spinner.
- Retake all/approve disabled during retake.

This is functional state feedback, not a UI redesign.

---

## 3. Regression tests added

| Test | Result |
|---|---|
| Successful retake replaces only selected slot; other IDs/paths unchanged; old file retained | PASS |
| Failed retake preserves previous image and recovers on retry | PASS |
| Metadata-write failure restores previous slot | PASS |
| Retake timeout leaves slot unchanged | PASS |
| Late image after timeout cannot overwrite slot | PASS |
| Repeated retakes use new IDs/paths; other slots untouched | PASS |
| Each review button targets its own slot | PASS |
| Mock captures are visually distinct | PASS |

Existing 3-photo, retake-all, mock workflow, review/approve and bridge tests still pass.

---

## 4. Remaining retake risks

- No physical EOS R retake test; mock/fake only.
- Real camera latency/transfer failure may be longer than the mock; the 15 s timeout remains.
- A retake after a bridge print has already been submitted is not supported; retakes occur before approval.
- The metadata-write failure path intentionally leaves the new original as an orphan (recoverable via Phase 1D orphan recovery); no automatic slot assignment.


---

## 5. Final test results (Phase 2A)

| Check | Result |
|---|---|
| `flutter analyze` | **No issues** |
| `flutter test` | **46 passed** |
| `pytest -q` | **9 passed** |
| `flutter build ios --simulator` | **Success** (144 MB debug simulator `Runner.app`) |

No physical camera/print/phone test was performed. Template Engine and GIF were not implemented.
