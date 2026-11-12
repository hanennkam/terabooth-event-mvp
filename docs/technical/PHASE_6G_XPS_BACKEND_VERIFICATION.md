# Phase 6G — XPS Backend Verification & Calibration Readiness

## Overall result

**PASS for XPS package/geometry verification.**
**BLOCKED for physical calibration readiness: the private DNP cutter feature
cannot be verified through the Windows PrintTicket validation API.**

No physical print was submitted. Production remains MockPrinter; spooler is
disabled.

---

## 1. Root cause confirmed

Phase 6E proved that the old `System.Drawing.Printing.PrintDocument` path used
DEVMODE defaults rather than the visible machine/user PrintTicket. The result was
a rotated, split, 2-inch-cut print.

The Phase 6F XPS backend was intended to use an explicit job ticket. Phase 6G
verified it with a no-print XPS package and the installed driver.

---

## 2. Implementation

### Job path

```text
1200×1800 JPEG
  → print_xps.ps1
  → FixedPage 384×576 (4×6 at 96 XPS DPI)
  → Image Stretch=Uniform
  → explicit per-user PrintTicket
  → MergeAndValidatePrintTicket (job scope)
  → XpsDocumentWriter
```

- `PrintQueue.CreateXpsDocumentWriter(queue)` for actual submission.
- `XpsDocument.CreateXpsDocumentWriter(document)` for dry-run package creation.
- `-DryRun` writes an `.xps` file and never calls the print queue.
- Real mode validates the ticket before writing.
- Adapter writes `data/jobs/<job_id>/print_job_config.json`.
- Adapter validates the config sidecar after the script returns.

### Failure behavior

- Missing/invalid ticket → throw.
- Media/orientation/resolution changed by driver → throw.
- **Private cut feature omitted or changed by driver → throw in real mode.**
- Missing XPS support → preflight blocker.
- Spooler acceptance remains `unknown`; never physical completion.

---

## 3. XPS dry-run evidence

Command (Windows, synthetic 1200×1800 image, no print):

```text
.\.venv\Scripts\python.exe .\scripts\xps_dryrun.py
```

Result:

```json
{
  "xps_file": "...\\terabooth-xps-verify-...\\calibration.xps",
  "fixedpage_width": "384",
  "fixedpage_height": "576",
  "page_count": 1,
  "config": {
    "mechanism": "XpsDocumentWriter to XPS file (dry-run)",
    "mode": "dry_run_xps_file",
    "queue": "DS-RX1",
    "page_inches": "4x6",
    "page_px_96dpi": "384x576",
    "orientation": "Portrait",
    "resolution": "300x300",
    "media": "PR_4x6",
    "cut": "CUT_STANDARD",
    "copies": 1,
    "ticket_source": "per-user PrintTicket",
    "ticket_media": "ns0000:PR_4x6",
    "ticket_orientation": "psk:Portrait",
    "ticket_resolution": "ns0000:Option1",
    "ticket_cut": "ns0000:CUT_STANDARD",
    "driver_conflict": "NoConflict",
    "driver_validated": true,
    "driver_accepted_media": "ns0000:PR_4x6",
    "driver_accepted_orientation": "psk:Portrait",
    "driver_accepted_resolution": "ns0000:Option1",
    "driver_accepted_cut": "",
    "private_vendor_cut_confirmed": false,
    "private_vendor_cut_note": "ValidatedPrintTicket omitted private DNP cut namespace; dry-run geometry only.",
    "effective_settings_verified": false,
    "physical_calibrated": false,
    "physical_completion": "unverified",
    "spooler_acceptance": "not_submitted"
  }
}
```

### Confirmed

- Real XPS package created successfully.
- One FixedPage, 384×576 units = 4×6 at 96 DPI.
- Media PR_4x6.
- Orientation Portrait.
- Resolution Option1 / 300×300.
- Cutter requested CUT_STANDARD.
- Driver `ConflictStatus = NoConflict` for the public ticket.
- No spooler job was submitted.

### Remaining unverified

- `driver_accepted_cut` is empty.
- The validated ticket drops the private DNP
  `ns0000:DocumentCUTTERCONTROL` feature.
- Therefore the XPS/PrintTicket path cannot prove or enforce the physical cutter
  setting; the real path fails closed.

Without physical evidence, no claim can be made that the DNP job cut is standard.

---

## 4. Tests

```text
Mac Bridge tests: 74 passed
Windows Bridge tests: 74 passed
Windows XPS dry-run: PASS
```

Coverage includes:

- 4×6 FixedPage geometry and no stretching.
- explicit media/orientation/resolution/cut request.
- malformed/missing ticket concepts.
- unsupported cutter/media/orientation rejected by sidecar validation.
- driver conflict/override handling.
- fail-closed preflight/gate.
- spooler status stays `unknown`.
- XPS package dry-run.

---

## 5. Production safety

| Check | Result |
|---|---|
| Physical print | **NONE** |
| Production mode | **mock** |
| Spooler | **disabled** |
| Queue jobs | **0** |
| Printer defaults/queue | **unchanged** |
| Driver/firmware | **unchanged** |
| Authentication/idempotency | **unchanged** |
| Customer data | **untouched** |
| Camera/Cascable | **untouched** |
| Secrets exposed | **NO** |

Bridge production process was not restarted and remains mock.

---

## 6. Remaining hardware/dependency blocker

The Windows PrintTicket API validates the public media/orientation/resolution but
omits the private DNP cutter option from `ValidatedPrintTicket`. The current XPS
backend therefore **blocks real submission** rather than risking another wrong
cut.

To achieve a hardware-calibrated 4×6 standard-cut path, one of these is required:

1. A vendor-supported DNP job interface/SDK or Hot Folder Print method that
   explicitly controls the cutter; or
2. A driver-validated DEVMODE/job mechanism confirmed by the DNP vendor; or
3. A new explicit calibration after the vendor limitation is resolved.

Do not use guessed DEVMODE offsets or CUT_2INCH.

### Hardware procedure after a supported mechanism exists

1. Keep production mock; use only a temporary Bridge.
2. Submit exactly one synthetic print.
3. Verify one uncut 4×6 sheet, portrait, correct scaling/colour.
4. Verify physical completion separately from spooler acceptance.
5. Restore mock immediately; no retry.

**Stopped before physical printing. Physical calibration NOT PASSED; cutter
verification remains blocked.**
