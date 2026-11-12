# Phase 6I — Native Windows Driver Printing Compatibility

## Overall result

**PASS for driver-managed backend implementation and software preflight.**
**Physical print remains NOT TESTED and NOT AUTHORIZED.**

The new backend follows the classic LumaBooth Assistant model: submit a normal
Windows print job and let the installed DNP driver/printer own media, orientation
and cut behaviour. No private DEVMODE/PrintTicket cutter control is used.

---

## 1. Root cause review

Old Phase 6E path:

```text
PrintDocument
  → custom PaperSize("4x6", 400×600)
  → forced Landscape=false
  → zero margins
```

But the actual Windows driver default is:

```json
{
  "paper_name": "PR (4x6)",
  "width": 413,
  "height": 615,
  "landscape": false
}
```

The old script replaced the driver’s `PR (4x6)` page with a custom 400×600 page.
That override is the most likely cause of the driver falling back to a different
DNP media/cut path, though the physical cut itself cannot be isolated without a
new calibration.

LumaBooth’s classic-printer workflow simply uses the manufacturer driver via
LumaBooth Assistant; it does not implement private cutter control in the app.

Sources:

- <https://support.lumasoft.co/en/articles/12831740-printing-with-lumabooth>
- <https://support.lumasoft.co/en/articles/12831741>

---

## 2. New driver-managed backend

Added `WindowsDriverPrinter` and `scripts/print_driver.ps1`.

Behavior:

- Opens the configured `DS-RX1` queue.
- Reads `DefaultPageSettings` from the Windows driver.
- Requires default paper name matching **PR (4x6)** and portrait.
- Does **not** set:
  - PaperSize
  - Landscape
  - margins
  - private DNP features
- Fits the 1200×1800 image uniformly and centres it on the page.
- Sets `PrinterSettings.Copies` directly.
- Writes `driver_job_config.json` with:
  - mechanism `driver_managed_PrintDocument`
  - default paper name/dimensions
  - no paper/orientation/margin overrides
  - `private_vendor_features_set=false`
  - cut source `Windows DNP driver preferences`
  - `physical_completion=unverified`

Printer modes now include:

```text
mock (default) | driver | spooler (legacy XPS) | hotfolder
```

Production remains `mock`; spooler is disabled.

---

## 3. Live Windows preflight evidence

```json
{
  "driver_managed": {
    "available": true,
    "ready": true,
    "physical_ready": false,
    "mechanism": "Windows PrintDocument default page (driver preferences)",
    "paper_name": "PR (4x6)",
    "paper_width": 413,
    "paper_height": 615,
    "landscape": false,
    "paper_overridden": false,
    "orientation_overridden": false,
    "margins_overridden": false,
    "private_vendor_features_set": false,
    "cut_policy": "Windows DNP driver preferences",
    "cut_software_verified": false,
    "physical_calibrated": false
  },
  "default_page": {
    "available": true,
    "paper_name": "PR (4x6)",
    "width": 413,
    "height": 615,
    "landscape": false,
    "is_4x6": true
  }
}
```

The generic `blockers=["driver_cut_override"]` and `configuration_ready=false`
belong to the **legacy XPS explicit-ticket path**, which cannot validate the
private DNP cutter. They do not block `driver_managed.ready=true`.

---

## 4. Orientation, scaling and copies

- Orientation: inherited from the driver; default is portrait.
- Page: `PR (4x6)` 413×615 hundredths of an inch.
- Scaling: uniform, centered, no stretch/crop beyond the default page.
- Copies: set through `PrinterSettings.Copies`.
- Cutter: operator/driver preference, not app-controlled.
- No `CUT_STANDARD` or `CUT_2INCH` private field is written.

The driver-managed config validator rejects any attempt to override paper,
orientation, margins or private vendor features, or to claim physical
completion.

---

## 5. Tests

Targeted printer suite after changes:

```text
22 passed
```

Coverage added:

- driver backend selects `print_driver.ps1`;
- wrong default page fails closed before subprocess;
- driver-managed readiness is separate from XPS cut validation;
- config sidecar rejects paper/orientation/margin/private overrides;
- physical completion must remain unverified.

Previous full-suite evidence (Phase 6G): 74/74. Earlier full run after adding
the driver backend: 77/77. No unrelated suite was rerun for this report.

---

## 6. Shortest path to verified physical 4×6

1. Keep production `TERABOOTH_PRINTER=mock`.
2. With explicit authorization, set:
   ```dotenv
   TERABOOTH_PRINTER=driver
   TERABOOTH_PRINTER_NAME=DS-RX1
   ```
3. Ensure Windows DNP preferences still show PR (4x6), portrait, 300×300,
   standard cut (no 2-inch cut).
4. Submit exactly one synthetic calibration job through the driver-managed
   backend.
5. Verify one uncut 4×6 portrait sheet, centered and correctly scaled.
6. Restore `TERABOOTH_PRINTER=mock` immediately.
7. No retry without new authorization.

No HFP installation is required for this path. HFP remains an alternative if the
driver path is physically unreliable.

---

## 7. Safety

| Check | Result |
|---|---|
| Physical print | **NONE** |
| Production mode | **mock** |
| Spooler | **disabled** |
| Printer defaults/queue | **unchanged** |
| Driver/firmware | **unchanged** |
| Private DEVMODE writes | **NONE** |
| Authentication/idempotency | **unchanged** |
| Customer data | **untouched** |
| Camera/Cascable | **untouched** |
| Secrets exposed | **NO** |

**Stopped before physical printing. Driver-managed software readiness is true;
physical cutter/orientation remains unverified.**
