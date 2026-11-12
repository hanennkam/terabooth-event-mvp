# Phase 3A-2K — Clean USB Capability Preflight

## Overall result

**PARTIAL**

The safe orchestration performed one capability-only invocation. USB discovery,
EOS 60D connection, capability/property reads, storage reporting and Live View
frame delivery succeeded, and the SDK disconnected cleanly. However, Live View
terminated with reason `2` and SDK error `1008` during cleanup rather than the
expected normal termination. No shutter, capture or transfer occurred.

The camera remained USB-enumerated after disconnect.

---

## 1. Orchestration

Exact invocation:

```bash
cd macos_cascable_demo
./orchestration/run-safe-test.sh \
  --mode capability \
  --allow-hardware \
  --authorization capability-preflight
```

Log:

```text
macos_cascable_demo/logs/orchestration-20261112T024306+0800-73970.log
```

- Mode: `capability`
- Authorization: `capability-preflight`
- `--allow-hardware`: present
- `--transfer`: absent
- `--single-shot`: absent
- Guard: **PASS**
- Competing camera apps: none detected
- `CAMERA_COMMAND=true` only for the capability harness invocation
- No application termination command was executed.

Source mode and process mode were also run before the hardware invocation:

```text
source  RC=0  CAMERA_COMMAND=false
process RC=0  COMPETING_APPLICATION_DETECTED=false  GUARD=PASS
```

---

## 2. USB evidence

Before discovery:

```text
Canon Digital Camera@02110000
sessionID      = 22335655082079
USBSpeed       = 3
UsbLinkSpeed   = 480000000
idVendor       = 1193
idProduct      = 12821
locationID     = 34668544
USB Address    = 2
```

The same session remained enumerated after the SDK disconnected:

```text
sessionID  = 22335655082079
idVendor   = 1193
idProduct  = 12821
locationID = 34668544
```

No USB reset, PTP service manipulation, or physical reconnect occurred.

---

## 3. CascableCore result

```text
CASCABLE_MAC_LICENSE_RESULT=0
CASCABLE_MAC_BUNDLE=se.cascable.CascableCoreMacDemo
CASCABLE_MAC_DISCOVERY=started mode=usbOnly mode_args transfer=false
CASCABLE_MAC_DISCOVERED vendor=Canon Inc. model=Canon EOS 60D transport=1 state=0
CASCABLE_MAC_CONNECT=connected warnings=1 state=2 model=Canon EOS 60D transport=1
CASCABLE_MAC_WARNING type=0 category=0
```

- Model: **Canon EOS 60D**
- Transport: **USB** (`1`)
- Connection state: **connected** (`2`)
- Warning: **`LowerThanExpectedFunctionality` / `RemoteControl`**
  (type `0`/category `0`), preserved and not suppressed.

---

## 4. Capability

```text
CASCABLE_MAC_CAPABILITY_FUNCTIONALITY_RAW=447936
CASCABLE_MAC_CAPABILITY_FUNCTIONALITY=fileDeletion,depthOfFieldPreview,shutterHalfPress,directFocusManipulation,exposureControl,cameraInitiatedTransfer,videoRecording,pannableLiveView
CASCABLE_MAC_CAPABILITY_COMMAND_CATEGORIES_RAW=3
CASCABLE_MAC_CAPABILITY_COMMAND_CATEGORIES=stillsShooting,filesystemAccess
CASCABLE_MAC_CAPABILITY_KNOWN_PROPERTIES=78
CASCABLE_MAC_STORAGE=devices 1
CASCABLE_MAC_STORAGE=shots_available 3014
```

Selected properties:

```text
Aperture             3.5        valid=17
Shutter Speed        ⅟80        valid=55
ISO                  5000       valid=20
AE Mode              M          valid=0
Battery Power        2/4        valid=0
White Balance        Automatic  valid=9
Shutter Drive        Single Shot valid=5
Exposure Compensation 0         valid=0
```

### Image Quality observation

```text
CASCABLE_MAC_IMAGE_QUALITY=current nil set_type=1 valid_count=0 known=false
CASCABLE_MAC_PROPERTY id=21 name= current=nil set_type=1 valid_count=0
```

- Current value: **nil**
- Settable values: **0**
- Identifier known according to `knownPropertyIdentifiers`: **false**
- **JPEG-only cannot be independently verified through this SDK property.**
- No camera setting was changed.

---

## 5. Live View

```text
CASCABLE_MAC_LIVE_VIEW=started
CASCABLE_MAC_LIVE_VIEW=frame size=(1056.0, 704.0) format=0
```

A real 1056×704 frame was delivered.

### Live View termination

```text
CASCABLE_MAC_LIVE_VIEW=terminated reason=2 error=The operation couldn’t be completed. (se.cascable error 1008.)
```

`reason=2` is the SDK failure termination reason, not normal termination. The
disconnect request had been issued immediately before this. The camera did
subsequently disconnect cleanly with no error.

**This is a lifecycle partial failure:** Live View did not terminate cleanly
before/at disconnect. It is likely a cleanup-ordering issue (ending the stream
and disconnecting back-to-back), not a camera discovery/connection failure, but
that is an inference. No retry was performed.

---

## 6. Lifecycle and safety

```text
CASCABLE_MAC_DISCONNECT=requested
CASCABLE_MAC_LIVE_VIEW=terminated reason=2 ... error 1008
CASCABLE_MAC_LOST_SIGHT model=Canon EOS 60D
CASCABLE_MAC_DISCONNECT=complete error=none
CASCABLE_MAC_DISCONNECT=no_reconnect_exit
```

| Requirement | Result |
|---|---|
| Shutter requests | **0** |
| Transfer callbacks | **0** |
| Transfer executions | **0** |
| `.original` / `.preview` request | **NONE** |
| Camera settings changed | **NO** |
| Camera files changed | **NO** |
| Cascable Studio terminated/relaunched | **NO** |
| Competing-app guard aborted | **NO — passed** |
| Retry | **NO** |
| Reconnect | **NO** |
| Live View stopped cleanly | **NO — reason 2/error 1008** |
| SDK disconnected | **YES — no error** |
| Camera still USB-enumerated | **YES — same session** |
| Remaining camera/harness processes | **NONE** |
| Production integration changed | **NO** |
| Production Bundle ID | **`com.terabooth.teraboothIpad`** |
| Production licence embedded | **NO** |

No `CASCABLE_MAC_SHUTTER` or `CASCABLE_MAC_TRANSFER_REQUEST` line exists in the
log. The transfer path was never invoked.

---

## 7. Conclusion

| Question | Answer |
|---|---|
| Clean repeatable capability-only discovery/connection? | **YES** |
| Camera properties/storage accessible? | **YES** |
| Live View frame delivered? | **YES — 1056×704** |
| Live View stopped cleanly? | **NO — reason 2/error 1008** |
| SDK disconnected cleanly? | **YES** |
| JPEG-only independently confirmed? | **NO — Image Quality nil/unknown** |
| Shutter/transfer involved? | **NO** |
| JPEG transfer capability proven? | **NO** |
| iPadOS compatibility proven? | **NO** |

The corrected orchestration successfully avoids automatic application
termination and passes its competing-app guard. The capability session is
usable, but the Live View cleanup ordering needs correction before claiming a
fully clean lifecycle baseline.

---

## 8. Recommended next action

1. Do not rerun this capability test automatically.
2. Fix the harness cleanup ordering so Live View is allowed to terminate
   normally before disconnect (or add a dedicated stop-and-wait mode).
3. Keep the safe orchestration; do not add application termination.
4. Re-run a single capability-only validation after the cleanup fix is reviewed.
5. Keep Image Quality as unverified unless the SDK exposes a reliable property.
6. Do not perform any JPEG transfer or iPadOS test from this result.

No further hardware operation was performed.
