# Phase 3A-2C — Canon EOS 60D USB Recovery & Hardware Preflight

**Date:** 2026-11-12  
**Overall result:** **PASS for USB/diagnostic preflight.** The EOS 60D is enumerated and fully usable when **Cascable Studio is closed**. No shutter, transfer, settings write or file modification was performed.

The earlier successful Phase 3A-1B evidence remains valid. The Phase 3A-2B no-enumeration condition was not a permanent camera failure.

---

## 1. Environment

| Item | Value |
|---|---|
| macOS | 26.5.1 (25F80) |
| Mac | MacBookPro18,1 |
| Xcode | 26.6 (17F113) |
| SDK | CascableCore 18.0.2 |
| Mac demo Bundle ID | `se.cascable.CascableCoreMacDemo` |
| Licence result | `0` |
| Camera | Canon EOS 60D |
| USB vendor/product | `0x1193` / `0x3215` (decimal 1193 / 12821) |
| USB location | `0x02110000` (34668544) |
| Storage reported by SDK | 1 device, 724 shots available |
| Shutter in this phase | **NONE** |

No licence bytes are included in this document.

---

## 2. USB enumeration evidence

### Before launching the harness

`ioreg` contained:

```text
+-o Canon Digital Camera@02110000  <class IOUSBHostDevice ...>
  "idProduct" = 12821
  "USB Product Name" = "Canon Digital Camera"
  "USB Vendor Name" = "Canon Inc."
  "idVendor" = 1193
  "locationID" = 34668544
  "USB Address" = 2
```

`system_profiler SPUSBDataType` returned no content in this environment
(0 lines), so `ioreg` is the authoritative evidence here.

The camera is physically present **before** the demo app starts. Do not equate a
failed CascableCore discovery with a missing USB device.

---

## 3. Competing process findings

### With Cascable Studio running

Processes:

```text
/Applications/Cascable Studio.app/Contents/MacOS/Cascable Studio
/System/Library/ImageCaptureCore.framework/.../mscamerad-xpc
/usr/libexec/ptpcamerad
/System/Library/Image Capture/Support/icdd
```

The SDK still discovered and connected to the EOS 60D, but the session was
degraded:

```text
CASCABLE_MAC_CONNECT=connected warnings=1 state=2 model=Canon EOS 60D transport=1
CASCABLE_MAC_CAPABILITY_KNOWN_PROPERTIES=0
CASCABLE_MAC_STORAGE=devices 1
CASCABLE_MAC_STORAGE=shots_available nil
CASCABLE_MAC_PROPERTY id=2 name=Aperture current=nil set_type=1 valid_count=0
```

All sampled property values were nil and no known properties were reported.
Live View still delivered one 1056×704 frame.

### After quitting Cascable Studio

Cascable Studio was closed gracefully. `ptpcamerad` briefly remained as a system
process; no user camera app remained. The same harness then reported:

```text
CASCABLE_MAC_CONNECT=connected warnings=1 state=2 model=Canon EOS 60D transport=1
CASCABLE_MAC_CAPABILITY_FUNCTIONALITY_RAW=447936
CASCABLE_MAC_CAPABILITY_FUNCTIONALITY=fileDeletion,depthOfFieldPreview,shutterHalfPress,directFocusManipulation,exposureControl,cameraInitiatedTransfer,videoRecording,pannableLiveView
CASCABLE_MAC_CAPABILITY_COMMAND_CATEGORIES_RAW=3
CASCABLE_MAC_CAPABILITY_COMMAND_CATEGORIES=stillsShooting,filesystemAccess
CASCABLE_MAC_CAPABILITY_KNOWN_PROPERTIES=78
CASCABLE_MAC_STORAGE=devices 1
CASCABLE_MAC_STORAGE=shots_available 724
CASCABLE_MAC_LIVE_VIEW=frame size=(1056.0, 704.0) format=0
```

The warning remained:

```text
CASCABLE_MAC_WARNING type=0 category=0
```

This is `LowerThanExpectedFunctionality` / `RemoteControl`; it was not
suppressed.

---

## 4. Full capability data with Studio closed

### Feature flags

Raw `supportedFunctionality`: **447936**.

Decoded:

- fileDeletion
- depthOfFieldPreview
- shutterHalfPress
- directFocusManipulation
- exposureControl
- cameraInitiatedTransfer
- videoRecording
- pannableLiveView

### Command categories

Raw **3**:

- stillsShooting
- filesystemAccess

`liveViewStreamActive` was false before starting the stream; Live View delivered
a real 1056×704 JPEG frame.

### Known properties / storage

- Known property identifiers: **78**
- Storage devices: **1**
- Shots available: **724**

### Sampled settings

```text
Aperture             current=5     settable_count=17   preview=[3.5, 4, 4.5, 5, 5.6]
Shutter Speed        current=⅟80   settable_count=55   preview=[30, 25, 20, 15, 13]
ISO                  current=5000  settable_count=20   preview=[Auto, 100, 125, 160, 200]
AE Mode              current=M     settable_count=0
Battery Power        current=2/4   settable_count=0
White Balance        current=Automatic settable_count=9
Shutter Drive        current=Single Shot settable_count=5
Exposure Compensation current=0    settable_count=0
```

Nine sampled properties reported a non-empty `valueSetType`, but this is a
metadata signal, not proof that every write path is safe. **No setting was
changed.** `CASCABLE_MAC_SETTINGS_WRITE=not_attempted`.

`validValueRange` was nil for all sampled properties; all were enumeration
properties. No writable-range property was exercised.

---

## 5. SD-card status

- macOS external volumes: only `Macintosh HD`; no SD volume mounted.
- Built-in SD reader: present but link width/speed Off.
- CascableCore camera storage: **1 device**, **724 shots available**.
- No shutter or file operation was performed.

The SDK reports camera storage and remaining shot capacity, which is consistent
with a usable SD card being present in the camera even though it is not mounted
as a macOS volume (normal for PTP camera storage). This phase does **not**
independently verify the physical card identity or files.

Do not remove/modify the card; original-transfer tests can now be attempted in a
separate phase.

---

## 6. Connection lifecycle

A capability-only run (no transfer, no shutter) observed:

```text
CASCABLE_MAC_DISCOVERED vendor=Canon Inc. model=Canon EOS 60D transport=1 state=0
CASCABLE_MAC_CONNECT=connected warnings=1 state=2 model=Canon EOS 60D transport=1
CASCABLE_MAC_DISCONNECT=requested
CASCABLE_MAC_LOST_SIGHT model=Canon EOS 60D
CASCABLE_MAC_DISCONNECT=complete error=none
CASCABLE_MAC_RECONNECT=search_started
CASCABLE_MAC_DISCOVERED vendor=Canon Inc. model=Canon EOS 60D transport=1 state=0
CASCABLE_MAC_CONNECT=connected warnings=1 state=2 model=Canon EOS 60D transport=1
```

The camera rediscovered and reconnected cleanly. No shutter was sent.

---

## 7. Likely cause: evidence vs speculation

### Evidence

1. The camera was enumerated on USB before the harness ran.
2. With Cascable Studio running, the SDK discovered/connected but reported
   **0 known properties**, all sampled values nil, and nil shot count.
3. After quitting Studio, the same camera/harness reported **78 properties**,
   full values/valid settable values, one storage device, 724 shots, and Live
   View.
4. System PTP/ImageCapture services (`ptpcamerad`, `mscamerad`, `icdd`) are
   present; `ptpcamerad` remained briefly after Studio quit but did not prevent
   the full 78-property session.
5. A clean disconnect/reconnect succeeded.

### Speculation / not proven

- The exact reason no Canon device appeared in the specific 3A-2B runs cannot be
  reconstructed now. Possible contributing factors are camera sleep/power state,
  cable/port, or competing camera ownership. In 3A-2B `ioreg` showed no Canon
  device at all, unlike this phase, so a pure SDK failure is not the only
  explanation.
- The 3A-2B failure should not be attributed solely to Studio without a
  reproducible no-enumeration trace.

**Conclusion:** competing camera ownership is proven to degrade an already
discovered SDK session; the earlier no-enumeration event is best treated as a
hardware/power/cable/session preflight issue, not a permanent SDK
incompatibility.

---

## 8. Exact manual action required

Before any further SDK test:

1. **Quit Cascable Studio** and leave it closed.
2. Quit EOS Utility, Image Capture, Photos, or any other app that may claim the
   camera. Do not force-quit unrelated processes.
3. Connect the EOS 60D **directly** to the Mac with a known data-capable USB
   cable; avoid unpowered hubs.
4. Use a direct USB port; if unavailable, try another port/cable.
5. Power the camera on and keep it awake. Battery was **2/4**; use AC or a
   charged battery for longer tests.
6. Confirm USB enumeration:

```bash
ioreg -p IOUSB -l -w 0 | grep -A2 'Canon Digital Camera'
```

Expected: `Canon Inc.` and `idProduct` 12821 / `idVendor` 1193.

7. Keep the SD card inserted; do not format or delete existing files.
8. Run the capability-only harness:

```bash
cd macos_cascable_demo
/tmp/TeraboothMacDemoDerived/Build/Products/Debug/TeraboothCascableMacDemo.app/Contents/MacOS/TeraboothCascableMacDemo
```

9. Only after confirming 78 properties/storage should the separate 3A-2B
   original-transfer phase be attempted. Do not trigger a shutter during
   preflight.

No camera setting was changed speculatively.

---

## 9. Final validation

| Check | Result |
|---|---|
| macOS harness build | **BUILD SUCCEEDED** |
| Mac licence | **PASS — result 0** |
| USB preflight | **PASS** |
| Competing app diagnosis | **PASS — Studio interference demonstrated** |
| Canon discovery/connection | **PASS with Studio closed** |
| Capability audit | **PASS — 78 properties, 1 storage, 724 shots** |
| Warning preserved | **PASS — type 0/category 0** |
| Clean disconnect/reconnect | **PASS** |
| Shutter/transfer | **NOT RUN by design** |
| SD storage detected | **YES via SDK; no macOS mount** |
| Settings write | **NOT ATTEMPTED** |
| iOS production build | **PASS — 175 MB** |
| Production Bundle ID | `com.terabooth.teraboothIpad` |
| Production licence | **ABSENT** |
| Flutter tests | **96 passed** |
| Python tests | **39 passed** |

No production iOS files, CameraPipeline, ImageIngestor, MockCameraService,
printing, GIF, QR or Windows Bridge were changed in this phase.

---

## 10. Recommended next phase

1. Keep Studio closed and camera awake with SD inserted.
2. Re-run the 3A-2B `--transfer` harness once: inspect `isValid`,
   `canProvide(.original)`, predicted size, execute result, generated data.
3. Validate one original JPEG (signature, decode, dimensions, size, EXIF).
4. Perform one non-destructive settings write/restore only after capability
   review.
5. Then plan physical iPad USB testing.

Do not begin iPad integration from this preflight alone.
