# Phase 3A-2E — EOS 60D Stable USB & SDK Capability Validation

**Date:** 2026-11-12  
**Overall result:** **PASS for the capability-only validation. Original JPEG transfer remains UNVERIFIED.**

The physical Canon EOS 60D was already USB-enumerated and was used without a
physical disconnect/reconnect. CascableCore discovered/connected over USB,
reported 78 properties, one storage device, 724 shots, the expected warning,
and delivered a 1056×704 Live View frame. Live View was stopped and the SDK
session was disconnected cleanly; the USB device remained enumerated on the
same session ID.

**No shutter request, image transfer, settings write, or image-file operation
was performed.**

---

## 1. USB enumeration before testing

Recorded at **2026-11-12 02:12:10 +0800** (UTC 2026-11-11T18:12:10Z):

```text
+-o Canon Digital Camera@02120000  <class IOUSBHostDevice, registered, matched, active ...>
  "sessionID" = 22286902512247
  "USBSpeed" = 3
  "UsbLinkSpeed" = 480000000
  "idProduct" = 12821
  "USB Product Name" = "Canon Digital Camera"
  "locationID" = 34734080
  "USB Address" = 2
  "USB Vendor Name" = "Canon Inc."
  "idVendor" = 1193
```

The supplied stable session ID, location, address and link speed matched the
observed values. The device was active before the harness was launched.

No Cascable Studio, EOS Utility, Image Capture application or Photos
application was running. Only Photos widget extensions and system daemons were
present; these did not own the camera session.

---

## 2. Timestamped test sequence

| Time (+0800) | Event |
|---|---|
| 02:12:10 | USB enumeration recorded; session `22286902512247`, location `34734080` |
| 02:12:50 | Capability-only harness started |
| 02:12:51 | Licence applied, result `0`; bundle verified |
| 02:12:54 | EOS 60D discovered; USB transport |
| 02:12:55 | Connected; warning recorded; capability/properties/storage read |
| 02:12:55 | Live View started |
| 02:12:57 | Live View frame delivered, 1056×704 |
| 02:13:03 | Live View stop/disconnect requested |
| 02:13:03 | Live View terminated normally (`reason 0`, no error) |
| 02:13:06 | Camera lost from discovery as session closed |
| 02:13:09 | Disconnect complete, no error |
| 02:13:10 | Harness exited; final USB enumeration checked |

The run used `--capability-only`, which deliberately disables transfer,
reconnect and the earlier automatic reconnect search.

---

## 3. Exact SDK logs

```text
CASCABLE_MAC_LICENSE_RESULT=0
CASCABLE_MAC_BUNDLE=se.cascable.CascableCoreMacDemo
CASCABLE_MAC_DISCOVERY=started mode=usbOnly mode_args transfer=false
CASCABLE_MAC_DISCOVERED vendor=Canon Inc. model=Canon EOS 60D transport=1 state=0
CASCABLE_MAC_CONNECT=requested
CASCABLE_MAC_CONNECT=connected warnings=1 state=2 model=Canon EOS 60D transport=1
CASCABLE_MAC_WARNING type=0 category=0
CASCABLE_MAC_CAPABILITY_FUNCTIONALITY_RAW=447936
CASCABLE_MAC_CAPABILITY_FUNCTIONALITY=fileDeletion,depthOfFieldPreview,shutterHalfPress,directFocusManipulation,exposureControl,cameraInitiatedTransfer,videoRecording,pannableLiveView
CASCABLE_MAC_CAPABILITY_COMMAND_CATEGORIES_RAW=3
CASCABLE_MAC_CAPABILITY_COMMAND_CATEGORIES=stillsShooting,filesystemAccess
CASCABLE_MAC_CAPABILITY_LIVE_VIEW_ACTIVE=false
CASCABLE_MAC_CAPABILITY_KNOWN_PROPERTIES=78
CASCABLE_MAC_STORAGE=devices 1
CASCABLE_MAC_STORAGE=shots_available 724
CASCABLE_MAC_SETTINGS_WRITE=not_attempted
CASCABLE_MAC_LIVE_VIEW=started
CASCABLE_MAC_TRANSFER=not_requested
CASCABLE_MAC_LIVE_VIEW=frame size=(1056.0, 704.0) format=0
CASCABLE_MAC_DISCONNECT=requested
CASCABLE_MAC_LIVE_VIEW=terminated reason=0 error=none
CASCABLE_MAC_LOST_SIGHT model=Canon EOS 60D
CASCABLE_MAC_DISCONNECT=complete error=none
CASCABLE_MAC_DISCONNECT=capability_only_exit
```

Transport raw `1` is USB; connection state `2` is connected.

---

## 4. Connection warning

```text
CASCABLE_MAC_WARNING type=0 category=0
```

- type `0` = `LowerThanExpectedFunctionality`
- category `0` = `RemoteControl`

The warning is retained and not suppressed. It does not enumerate which features
are affected. The capability mask and property/command data below provide more
specific information, but the warning remains a limitation.

No claim of full EOS 60D compatibility is made.

---

## 5. Capability results

### Supported functionality

Raw mask: **447936**

Decoded by the harness:

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

### Known properties and storage

```text
knownPropertyIdentifiers count: 78
storageDevices count: 1
shots available: 724
```

The count changed from 77 in 3A-1B to 78 in 3A-2C/2E. No claim is made that a
specific new property is the difference; the SDK enumeration is authoritative.

### Selected properties

```text
Aperture             current=3.5     set_type=1  valid=17  preview=[3.5, 4, 4.5, 5, 5.6]
Shutter Speed        current=⅟80     set_type=1  valid=55  preview=[30, 25, 20, 15, 13]
ISO                  current=5000    set_type=1  valid=20  preview=[Auto, 100, 125, 160, 200]
AE Mode              current=M       set_type=1  valid=0
Battery Power        current=2/4     set_type=1  valid=0
Image Quality        current=nil     set_type=1  valid=0
White Balance        current=Automatic set_type=1 valid=9
Shutter Drive        current=Single Shot set_type=1 valid=5
Exposure Compensation current=0      set_type=1  valid=0
```

`validValueRange` was nil for all sampled properties; all sampled writable
properties used the enumeration set type. No setting was changed.

Aperture was already 3.5 at this run; no write was performed.

### Original-transfer-related capability

`cameraInitiatedTransfer` is present in the supported-functionality mask, and
`filesystemAccess` is an active command category. This is **not** proof that
`.original` representation is available for a given transfer request. No
shutter was triggered, so no `CameraInitiatedTransferRequest` was produced and
`.original` availability was not tested.

---

## 6. Live View

```text
CASCABLE_MAC_LIVE_VIEW=started
CASCABLE_MAC_LIVE_VIEW=frame size=(1056.0, 704.0) format=0
CASCABLE_MAC_LIVE_VIEW=terminated reason=0 error=none
```

- Real frame from the physical EOS 60D.
- 1056×704.
- RAF/JPEG format raw `0` (JPEG live view frame).
- Stopped cleanly before disconnect.
- No renderer/UI was involved in this harness.

---

## 7. Disconnect and final USB state

The SDK disconnected cleanly:

```text
CASCABLE_MAC_DISCONNECT=requested
CASCABLE_MAC_DISCONNECT=complete error=none
CASCABLE_MAC_DISCONNECT=capability_only_exit
```

The camera was **not physically disconnected or reconnected**.

Final USB enumeration, same session:

```text
Canon Digital Camera@02120000
sessionID = 22286902512247
USBSpeed = 3, UsbLinkSpeed = 480000000
idVendor = 1193, idProduct = 12821
locationID = 34734080
USB Address = 2
```

No discrepancy was observed between physical USB enumeration and SDK discovery
after Studio was closed.

---

## 8. What remains unverified

- Camera-initiated **`.original`** representation availability.
- Original JPEG transfer execution.
- Original JPEG signature/decode/dimensions/EXIF.
- Exact byte comparison with the SD-card file.
- Settings write/restore behavior.
- Shutter request timing/behavior in this phase.
- Storage file identity and physical SD-card contents.
- iPadOS USB behavior.
- Full EOS 60D remote-control compatibility despite the warning.

**A successful capability connection does not prove original JPEG transfer.**

---

## 9. Build and validation

| Check | Result |
|---|---|
| macOS harness build | **BUILD SUCCEEDED** |
| Mac licence | **PASS — result 0** |
| USB preflight | **PASS** |
| SDK discovery/connection | **PASS** |
| Capability/property/storage read | **PASS** |
| Warning preserved | **PASS** |
| Live View | **PASS — 1056×704** |
| Live View stop | **PASS — reason 0** |
| Clean SDK disconnect | **PASS** |
| Physical reconnect | **NOT PERFORMED (by instruction)** |
| Shutter | **NOT RUN** |
| Transfer/settings write | **NOT RUN** |
| iOS production build | **PASS — 175 MB** |
| Production Bundle ID | **`com.terabooth.teraboothIpad`** |
| Production licence | **ABSENT** |
| Flutter tests | **96 passed** |
| Python tests | **39 passed** |

No production iOS files, CameraPipeline, ImageIngestor, MockCameraService,
printing, GIF, QR or Windows Bridge were changed.

---

## 10. Implications for the iOS adapter

The conservative iOS adapter remains appropriate:

- It requires camera-offered `.original` bytes.
- It does not substitute preview data.
- It does not report shutter request as success.
- It has no filesystem fallback.
- It remains disabled by default.

3A-2E confirms the core SDK can operate a stable USB session and expose
settings/storage/Live View on macOS. It does **not** prove `.original`
availability, original transfer, or iPadOS compatibility.

---

## 11. Recommended next phase

1. Keep Cascable Studio closed and camera awake.
2. Run the single-shutter original-transfer harness once.
3. Inspect request `isValid`, `availableRepresentations`,
   `canProvide(.original)`, predicted size and result.
4. Validate one original JPEG and save under a unique `/tmp` directory.
5. If `.original` is unavailable, stop and document; do not substitute preview.
6. Do not proceed to iPad integration until original transfer is demonstrated.
