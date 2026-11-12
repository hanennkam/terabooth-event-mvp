# Phase 6H — DNP Vendor Printing Mechanism Discovery

## Overall result

**BLOCKED at vendor dependency.**

The Windows machine has the DNP DS-RX1 driver and queue, but **DNP Hot Folder
Print (HFP) and any DNP SDK/utility are not installed**. Phase 6G already proved
that the standard Windows PrintTicket path cannot verify the private DNP cutter
feature.

No physical print was submitted. Production remains MockPrinter; spooler is
disabled.

---

## 1. Installed vendor evidence

Read-only discovery of:

- `C:\Program Files*`
- `C:\ProgramData`
- Windows uninstall registry
- Windows services
- Downloads/user vendor paths

Found:

- DS-RX1 printer queue/driver (Dai Nippon Printing)
- USB001, status Normal
- no DNP Hot Folder Print directory
- no HFP executable
- no HFP uninstall entry
- no HFP service
- no DNP SDK or vendor utility directory

The Downloads search was inconclusive/slow and was stopped; it does not change
the installed-software evidence.

---

## 2. Mechanism comparison

| Mechanism | Status | Cutter/media control |
|---|---|---|
| Windows `PrintDocument` DEVMODE | Phase 6E failed physically | Not reliable; private DNP fields unavailable |
| XPS + PrintTicket | Phase 6G verified geometry/public ticket, private cut omitted | **Fail-closed; not usable for cutter** |
| DNP Hot Folder Print | **Not installed** | Official 4×6 / 2×6 folder-based output; recommended dependency |
| DNP SDK/vendor utility | **Not found/installed** | Unavailable |
| Guessed DEVMODE offsets | Prohibited | Not used |

Official DNP documentation confirms Hot Folder Print supports:
- DS-RX1/DS-RX1HS
- 4×6 and 2×6 output
- copies/resolution settings
- printer status logging
- folder monitoring and daily archives

Source: <https://www.dnpphoto.com/hot-folder-print>

---

## 3. Selected architecture

**DNP Hot Folder Print (HFP) using a dedicated 4×6 monitored folder and archive**
is the most reliable supported path, once installed and configured.

Do **not** use a `2x6` folder for the standard 4×6 product. Folder selection is
the explicit media/cut contract; no PrintTicket/DEVMODE guessing is required.

The existing `HotFolderPrinter` adapter is a starting point but is **not yet
certified**:

- it has not run against HFP;
- it currently ignores `copies` when copying one file;
- its archive check expects a direct archive filename, while HFP archives by
  date folders;
- HFP folder naming/configuration must be verified on the actual install.

No HFP adapter code was changed without the vendor software present.

---

## 4. Exact missing dependency

1. Official DNP Hot Folder Print Windows installer (Windows 10/11).
   - .NET 4.5, 2GB RAM, 200MB free plus archive space (per vendor).
2. HFP installed and configured for the attached DS-RX1HS.
3. A monitored **4×6** output folder (not 2×6).
4. A known archive folder/date layout.
5. Confirmation of copy-count behavior for the selected HFP version.
6. License/terms acceptance by the operator if required by the installer.

No driver/firmware change is required.

---

## 5. Shortest path to a verified 4×6 calibration

1. Install DNP HFP on Windows and configure the DS-RX1HS.
2. Create/select the HFP **4×6** folder and archive location.
3. Keep `TERABOOTH_PRINTER=mock` while preparing.
4. Update the Bridge HFP adapter for the actual folder/archive/copies behavior
   and add targeted tests (only after HFP is installed).
5. Start a temporary Bridge with:
   ```dotenv
   TERABOOTH_PRINTER=hotfolder
   TERABOOTH_HOT_FOLDER=<HFP 4x6 folder>
   TERABOOTH_HOT_FOLDER_ARCHIVE=<HFP archive>
   ```
6. Submit exactly one synthetic calibration print.
7. Confirm one uncut 4×6 portrait sheet, then restore mock immediately.

No retry without a new explicit authorization.

---

## 6. Safety / evidence reused

- Phase 6G tests: **74 passed** (Mac/Windows); no code changed in 6H.
- No physical print.
- Production MockPrinter; spooler disabled.
- Queue jobs: 0.
- Printer defaults/queue/driver/firmware unchanged.
- Authentication/idempotency/customer data unchanged.
- Camera/Cascable unchanged.
- No secrets exposed.

**Stopped at the missing HFP/SDK dependency.**
