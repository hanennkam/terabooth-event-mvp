# Phase 3A-3A — Physical iPad Deployment & Canon EOS 60D Preflight

## Overall result

**BLOCKED — physical iPad deployment and camera preflight could not be performed.**

Three independent blockers prevent a safe physical run:

1. **No iPad is visible to Xcode.** `xcrun devicectl list devices` reports no
   devices; USB inventory contains no iPad.
2. **No code-signing identity/team is installed.** `security find-identity -p
   codesigning -v` reports `0 valid identities found`; the demo target has
   `CODE_SIGNING_REQUIRED=YES` and no `DEVELOPMENT_TEAM`.
3. **The current demo probe is not safe for this phase.** On launch it enables
   the simulated-camera plugin, connects, starts Live View, and then calls the
   shutter API (`invokeOneShotShutterExplicitlyEngagingAutoFocus`). It does not
   perform USB EOS 60D discovery. It was not launched.

No shutter, capture, transfer, camera setting change, USB reset, or camera
application termination was performed. No source was changed.

---

## 1. Deployment audit

### Xcode schemes/configuration

- Demo scheme: **Runner-CascableDemo**
- Demo configuration: **Debug-CascableDemo**
- Demo bundle: **`se.cascable.CascableCoreiOSDemo`**
- Demo compile condition: **`CASCABLE_DEMO`**
- Production bundle: **`com.terabooth.teraboothIpad`**
- Deployment target: **iOS 14.0**
- Device family: **1,2** (iPhone/iPad)
- Supported platforms: `iphoneos iphonesimulator`

### Licence inclusion

- Demo licence exists locally: **471 bytes, mode 600** (contents not read or
  printed).
- Demo build phase copies the licence only for `Debug-CascableDemo`; the
  simulator demo product contains `CascableCoreLicense.licence`.
- Production simulator product:
  - bundle ID **`com.terabooth.teraboothIpad`**
  - licence **absent**
- Demo build (simulator) verification:
  - `BUILD SUCCEEDED`
  - bundle ID **`se.cascable.CascableCoreiOSDemo`**
  - licence present in the demo app bundle
- Runtime licence verification on a physical iPad: **NOT TESTED**.

### CascableCore SPM

Resolved:

- `cascablecore-distribution` **18.0.2** (`4407ce…`)
- `cascablecore-swift` **18.0.2** (`69a6c1…`)
- `cascablecore-simulated-camera` **1.0.14**

### Native plugin registration

Static verification only:

- `CameraPlugin` registers `com.terabooth/camera` and
  `com.terabooth/camera/events` in `AppDelegate.didInitializeImplicitFlutterEngine`.
- `CascableCameraAdapter` is the native method/event handler.
- `NativeCameraService`/`CascableCameraService` exist on the Dart side.
- `MockCameraService` remains the production default; `USE_NATIVE_CAMERA`
  defaults false.
- Wired authorization is requested via
  `attemptToObtainWiredCameraAuthorization`.

Physical launch and channel registration: **NOT TESTED**.

### Signing

- `CODE_SIGNING_REQUIRED = YES`
- `CODE_SIGNING_ALLOWED = YES`
- `CODE_SIGN_IDENTITY = iPhone Developer`
- no `DEVELOPMENT_TEAM` in the audited settings
- `security find-identity -p codesigning -v`: **0 valid identities found**

A physical install is impossible in this state.

---

## 2. Physical deployment

| Requirement | Result |
|---|---|
| iPad appears in Xcode device list | **NO — no devices found** |
| iPad model/OS detected | **NOT TESTED** |
| Demo build for physical device | **BLOCKED — no iPad/signing** |
| Install on iPad | **BLOCKED** |
| Launch app | **NOT TESTED** |
| Plugin registration at runtime | **NOT TESTED** |
| Demo licence runtime result | **NOT TESTED** |
| Production licence exclusion | **PASS** (built product checked) |

The simulator named `iPad (A16) 26.5` exists, but it is not the target physical
iPad and is not evidence of iPadOS 26.6 or USB behavior.

---

## 3. Camera preflight

| Requirement | Result |
|---|---|
| EOS 60D connected to iPad | **NOT TESTED / no iPad** |
| USB enumeration | **NOT TESTED** |
| USB-only discovery | **NOT TESTED** |
| Camera model/transport/state | **NOT TESTED** |
| Connection | **NOT TESTED** |
| Warnings (RemoteControl/LowerThanExpectedFunctionality) | **NOT TESTED** |
| Properties count | **NOT TESTED** |
| Storage count/remaining shots | **NOT TESTED** |
| Live View capability | **NOT TESTED** |
| Live View frame dimensions | **NOT TESTED** |
| Live View termination callback | **NOT TESTED** |
| Disconnect | **NOT TESTED** |
| Shutter requests | **0 — none issued** |
| Capture/transfer | **NONE** |

No conclusions about iPadOS USB compatibility or EOS 60D behavior are drawn.

---

## 4. Demo-probe safety blocker

`ios/Runner/CascableCoreDemoProbe.swift` currently:

1. Enables `SimulatedCameraPluginIdentifier`.
2. Starts discovery.
3. Connects to the discovered (simulated) camera.
4. Starts Live View.
5. Calls `capture(camera)`, which installs a transfer handler and invokes the
   one-shot shutter.
6. Disconnects after 10 seconds.

This build must **not** be launched for this phase. It would issue a shutter
request and would test the simulated camera rather than USB EOS 60D discovery.
No source was modified because physical verification is impossible and any
demo-probe replacement should be reviewed before deployment.

---

## 5. Build evidence

The simulator-only demo build was built without launching it:

```text
xcodebuild -project ios/Runner.xcodeproj \
  -scheme Runner-CascableDemo \
  -configuration Debug-CascableDemo \
  -sdk iphonesimulator \
  -derivedDataPath /tmp/terabooth-ipad-demo-audit build
BUILD SUCCEEDED
```

Evidence:

```text
Demo bundle ID: se.cascable.CascableCoreiOSDemo
Demo licence in product: present (471 bytes)
Production bundle ID: com.terabooth.teraboothIpad
Production licence: absent
```

The temporary demo build artefact was removed after inspection.

---

## 6. Blockers and required next actions

### B1 — connect and pair the iPad

- Connect the target iPad by USB, trust the Mac, enable Developer Mode, and
  confirm it appears in `xcrun devicectl list devices`.

### B2 — install a signing identity/team

- Configure a valid Apple Development identity/team and provisioning for
  `se.cascable.CascableCoreiOSDemo`.
- Do not change the production bundle ID.

### B3 — make the demo preflight safe

Before any physical launch, the demo probe must be replaced or gated to:

- USB-only discovery (no simulated plugin)
- no shutter/capture/transfer
- read properties/storage
- optional Live View only if capability is advertised
- stop Live View, then disconnect once
- no auto-reconnect

This requires explicit review/authorization and is not performed here.

---

## 7. Safety confirmation

- Shutter commands issued: **0**
- Camera captures/transfers: **0**
- Camera settings changed: **NO**
- Camera files changed: **NO**
- USB/PTP reset: **NO**
- Camera applications terminated: **NO**
- Production bundle/licence changed: **NO**
- Source changes: **NONE**

**Stopped at the physical-deployment gate.**
