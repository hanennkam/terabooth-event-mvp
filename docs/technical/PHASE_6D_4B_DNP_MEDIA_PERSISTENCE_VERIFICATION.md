# Phase 6D-4B — DNP 4×6 Media Persistence Verification

## Overall result

**DISCREPANCY — the per-user Printing Preferences did persist as `PR (4x6)`,
but the machine-default PrintTicket and the running Bridge preflight still
report `PC` / 6×4. The per-user ticket also has `CUT_2INCH` enabled, not
`CUT_STANDARD`.**

Read-only verification only. No print job was submitted, no spooler mode was
enabled, no printer preference or queue setting was changed, and the Bridge was
not restarted.

Verification time: **2026-11-12 22:55 +08:00** on `IZZATY` as `izzaty\user`.

---

## 1. Queue state

| Property | Value |
|---|---|
| Queue | `DS-RX1` |
| Exists | Yes |
| Driver | `DS-RX1` |
| Manufacturer | Dai Nippon Printing |
| Port | `USB001` |
| PrinterStatus | `Normal` |
| WorkOffline | False |
| Shared | False |
| Queued jobs | **0** |

`Get-PrintJob -PrinterName DS-RX1` returned **0** jobs before and after the
verification.

---

## 2. Raw driver evidence

### 2.1 Read-only preflight script

Command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File windows_bridge\scripts\printer_preflight.ps1 -QueueName DS-RX1
```

Exact output:

```json
{
  "available": true,
  "queue_exists": true,
  "queue_name": "DS-RX1",
  "driver_name": "DS-RX1",
  "driver_manufacturer": "Dai Nippon Printing",
  "driver_version": "281479271874560",
  "port_name": "USB001",
  "printer_status": "Normal",
  "work_offline": false,
  "shared": false,
  "paper_size": "",
  "media": "ns0000:PC",
  "orientation": "psk:Portrait",
  "resolution": "ns0000:Option1",
  "cut": "ns0000:CUT_STANDARD",
  "queued_jobs": 0,
  "query_error": ""
}
```

### 2.2 Machine-default PrintTicket (`Get-PrintConfiguration`)

`Get-PrintConfiguration -PrinterName DS-RX1` returned a ticket that matches the
queue's `DefaultPrintTicket` (machine default), not the per-user ticket.

| Feature | Selected value |
|---|---|
| `psk:PageMediaSize` | **`ns0000:PC`** |
| `psk:MediaSizeWidth` | `156125` |
| `psk:MediaSizeHeight` | `104987` |
| `psk:PageOrientation` | `psk:Portrait` |
| `psk:PageResolution` | `ns0000:Option1`, X=`300`, Y=`300` |
| `ns0000:DocumentCUTTERCONTROL` | **`ns0000:CUT_STANDARD`** |
| `ns0000:Borders` | `ns0000:On` |
| `psk:JobCopiesAllDocuments` | `1` |

The `PC` dimensions are 156.125 × 104.987 mm (≈6.15 × 4.13 in), i.e. the
6×4 media, not the intended 4×6 portrait media.

### 2.3 Per-user PrintTicket (`System.Printing.PrintQueue.UserPrintTicket`)

This is the ticket affected by the **Printing Preferences** dialog that the
operator confirmed.

| Feature | Selected value |
|---|---|
| `psk:PageMediaSize` | **`ns0000:PR_4x6`** |
| `psk:MediaSizeWidth` | `104987` |
| `psk:MediaSizeHeight` | `156125` |
| `psk:PageOrientation` | `psk:Portrait` |
| `psk:PageResolution` | `ns0000:Option1`, X=`300`, Y=`300` |
| `ns0000:DocumentCUTTERCONTROL` | **`ns0000:CUT_2INCH`** |
| `ns0000:Borders` | Not selected in this ticket |

The `PR_4x6` dimensions are 104.987 × 156.125 mm (≈4.13 × 6.15 in), i.e. the
intended 4×6 portrait media.

**The 2-inch cut is enabled in the per-user ticket.** This does not match the
required `CUT_STANDARD` / disabled state.

### 2.4 Queue DefaultPrintTicket (`System.Printing.PrintQueue.DefaultPrintTicket`)

| Feature | Selected value |
|---|---|
| `psk:PageMediaSize` | **`ns0000:PC`** |
| `psk:MediaSizeWidth` | `156125` |
| `psk:MediaSizeHeight` | `104987` |
| `psk:PageOrientation` | `psk:Portrait` |
| `psk:PageResolution` | `ns0000:Option1`, X=`300`, Y=`300` |
| `ns0000:DocumentCUTTERCONTROL` | `ns0000:CUT_STANDARD` |

This matches `Get-PrintConfiguration` exactly.

### 2.5 Per-user DEVMODE (`HKCU\Printers\DevModePerUser` → `DS-RX1`)

Decoded read-only from the binary value (length 1260 bytes):

```text
dmSpecVersion   = 1025
dmDriverVersion = 1539
dmSize          = 220
dmDriverExtra   = 1040
dmFields        = 0x0781EF43
dmOrientation   = 1        (portrait)
dmPaperSize     = 235
dmPaperLength   = 1561     (156.1 mm)
dmPaperWidth    = 1049     (104.9 mm)
dmFormName      = "PR (4x6)"
dmPrintQuality  = 300
dmYResolution   = 300
dmColor         = 2
dmDuplex        = 1
dmMediaType     = 1
```

This independently confirms that the operator's Printing Preferences persisted
`PR (4x6)`, portrait, 300×300 in the per-user DEVMODE.

### 2.6 Driver PrintCapabilities

From `PrintQueue.GetPrintCapabilitiesAsXml()` (read-only):

| Feature | Supported options |
|---|---|
| `psk:PageMediaSize` | `PR_L`, **`PR_4x6`**, `PR_4x6x2`, `L`, **`PC`**, `_2L`, `A5STD`, `_6x4x2`, `_5x5`, `_6x6` |
| `psk:PageOrientation` | `psk:Portrait`, `psk:Landscape` |
| `psk:PageResolution` | `Option1`, `Option2`, `Option3` |
| `ns0000:DocumentCUTTERCONTROL` | `CUT_STANDARD`, `CUT_2INCH` |

Both `PR_4x6` and `PC` are supported by the driver; the active selection is
what differs between the per-user and machine tickets.

---

## 3. Running Bridge API

Authenticated `GET /v1/printers` returned **HTTP 200**:

```json
{
  "printers": [
    {
      "name": "Mock Printer",
      "state": "ready",
      "mode": "mock",
      "note": "NOT a physical printer"
    }
  ],
  "preflight": {
    "available": true,
    "queue_exists": true,
    "configured_queue_name": "DS-RX1",
    "spooler_mode_enabled": false,
    "queue_name": "DS-RX1",
    "driver_name": "DS-RX1",
    "driver_manufacturer": "Dai Nippon Printing",
    "driver_version": "281479271874560",
    "port_name": "USB001",
    "printer_status": "Normal",
    "work_offline": false,
    "shared": false,
    "paper_size": "",
    "media": "ns0000:PC",
    "orientation": "psk:Portrait",
    "resolution": "ns0000:Option1",
    "cut": "ns0000:CUT_STANDARD",
    "queued_jobs": 0,
    "query_error": ""
  }
}
```

Bridge diagnostics: PID `3920`, uptime 504 s, `queue_depth=0`,
`active_print=0`, `active_tasks=0`.

---

## 4. Requirement comparison

| Requirement | Per-user ticket | Machine default / `Get-PrintConfiguration` | Bridge API preflight | Result |
|---|---|---|---|---|
| Queue `DS-RX1` | n/a | `DS-RX1` | `DS-RX1`, exists | **PASS** |
| Media `PR_4x6` | **`ns0000:PR_4x6`** | **`ns0000:PC`** | **`ns0000:PC`** | **FAIL for Bridge / machine ticket** |
| Orientation Portrait | `psk:Portrait` | `psk:Portrait` | `psk:Portrait` | **PASS** |
| Resolution 300×300 | `Option1`, 300×300 | `Option1`, 300×300 | `Option1` (no DPI in API) | **PASS**, API is token-only |
| 2-inch cut disabled | **`CUT_2INCH`** | `CUT_STANDARD` | `CUT_STANDARD` | **FAIL for per-user ticket** |
| Queue jobs 0 | n/a | 0 | 0 | **PASS** |
| Spooler disabled | n/a | n/a | `false` | **PASS** |
| MockPrinter active | n/a | n/a | `mode=mock` | **PASS** |

---

## 5. Discrepancy analysis

1. **The operator's persistence claim is confirmed for the per-user ticket.**
   `UserPrintTicket`, the `HKCU\Printers\DevModePerUser` DEVMODE, and
   `System.Drawing.Printing.PrinterSettings` all report `PR (4x6)`, portrait,
   300×300.

2. **`Get-PrintConfiguration` and the Bridge preflight read the machine-default
   ticket, not the per-user ticket.** The machine default remains
   `ns0000:PC` (6×4). The Bridge preflight therefore still reports
   `media=ns0000:PC`, even though the current user's Printing Preferences are
   `PR (4x6)`.

3. **The per-user ticket has `CUT_2INCH` enabled.** The required safe state is
   `CUT_STANDARD` / disabled. This must be corrected by the operator before any
   physical print is considered. The machine ticket currently reports
   `CUT_STANDARD`, so the Bridge preflight does not reveal this discrepancy.

4. **The Bridge preflight resolution field is an option token**
   (`ns0000:Option1`), not a numeric DPI value. The raw tickets confirm that
   this option is 300×300.

No code, `.env`, printer preference, queue, driver or Bridge state was changed
in this phase.

---

## 6. Safety attestations

- No print job was submitted.
- `scripts/test_print.ps1` was **not** executed.
- `scripts/submit_dnp_e2e.py` was **not** executed.
- Spooler mode was **not** enabled and remains `false`.
- No Windows printer preference, queue, driver, media or cut setting was
  changed.
- The Bridge was **not** restarted; the existing process (PID `3920`) was left
  running.
- Authentication was not disabled or modified.
- No token, delivery secret, customer data or job content was printed in this
  report or in command output.
- All printer queries were read-only.

---

## 7. Required operator action before re-verification

1. **Disable the 2-inch cut** in the DS-RX1 Printing Preferences so the
   per-user ticket reports `CUT_STANDARD`.
2. If the Bridge preflight must report `PR (4x6)`, set the **machine default**
   via *Printer Properties → Advanced → Printing Defaults* to:
   - media `PR (4x6)`
   - portrait
   - 300×300 dpi
   - 2-inch cut disabled
3. Alternatively, authorize a separate code change so the Bridge preflight
   reads the per-user `UserPrintTicket` / DEVMODE instead of
   `Get-PrintConfiguration`. That change was **not** made in this phase.
4. Re-run this read-only verification after the operator-side changes.
5. Keep `TERABOOTH_PRINTER=mock` until the media and cut discrepancies are
   resolved and a physical print is explicitly authorized.

**Stopped after read-only verification. No print job was submitted. The media
still reports `PC` / 6×4 in the machine ticket and Bridge API.**
