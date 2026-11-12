# Phase 3A-3C — Safe Physical iPad Camera Preflight Probe

## Overall result

**PASS for source-level preparation and static verification.**  
**Physical iPad camera preflight remains NOT TESTED** because signing is still
blocked by the unavailable demo bundle identifier.

No app was installed or launched. No camera was discovered or connected. No
shutter, capture, transfer or settings operation occurred.

---

## 1. Changes

### `ios/Runner/CascableCoreDemoProbe.swift`

Replaced the unsafe automatic probe with an explicit, no-shutter preflight:

- Removed all shutter, capture and transfer code.
- Removed `CascableCoreSimulatedCamera` import and all simulated-camera setup.
- No transfer handler is registered.
- No automatic discovery, connection or Live View at launch.
- `prepare(licenseApplied:)` only records licence state and installs a floating
  "Camera preflight" button.
- Operator actions in a native preflight panel:
  - USB-only discovery
  - Connect
  - Read-only properties and storage
  - Optional Live View start
  - Live View stop
  - Disconnect
  - Close
- Explicitly disables the simulated plugin before searching:
  `discovery.setEnabled(false, ...)`.
- Discovery uses `.usbOnly`.
- Connection authentication requests are not guessed; the probe submits
  cancellation, and reports failure.
- Read-only logging includes known property count, shots available, storage
  device count, capacity and available space.
- Live View is optional and user-started; its termination callback is logged.
- Stop Live View and disconnect are separate explicit actions.

### `ios/Runner/AppDelegate.swift`

Demo launch path changed from:

```swift
CascableCoreDemoProbe.shared.start(licenseApplied: licenseApplied)
```

to:

```swift
CascableCoreDemoProbe.shared.prepare(licenseApplied: licenseApplied)
```

This call is inside `#if CASCABLE_DEMO`; production behavior is unchanged.

### Static safety tests

Added `test/demo_probe_safety_test.dart`:

1. No shutter/capture/transfer API names.
2. No simulated-camera import/configuration/enable.
3. USB-only discovery and explicit simulated-plugin disable.
4. Launch path only calls `prepare`, not discovery/connect/Live View.
5. All preflight actions are explicit functions/UI buttons.

### Test hygiene

`test/software_workflow_test.dart` GIF temp cleanup is now idempotent around a
pre-existing asynchronous cleanup race. No product behavior changed.

---

## 2. Safety properties

| Requirement | Result |
|---|---|
| Shutter/capture API | **ABSENT** |
| Transfer handler | **ABSENT** |
| Simulated camera enabled | **NO — explicitly disabled** |
| Auto discovery at launch | **NO** |
| Auto connection at launch | **NO** |
| Auto Live View at launch | **NO** |
| Camera settings writes | **NONE** |
| USB/PTP reset | **NONE** |
| Camera app termination | **NONE** |
| Production MockCameraService | **UNCHANGED / default** |
| Flutter camera channels | **UNCHANGED** |
| Licence contents | **NOT read/printed/modified** |

---

## 3. Verification

### Flutter

```text
flutter analyze
No issues found!

flutter test --concurrency=1
128 tests passed
```

### Demo simulator build (no launch)

```text
xcodebuild ... -scheme Runner-CascableDemo \
  -configuration Debug-CascableDemo \
  -sdk iphonesimulator ... build
BUILD SUCCEEDED
demo bundle: se.cascable.CascableCoreiOSDemo
demo licence present: yes (471 bytes; contents not read)
```

The simulator build was not installed or launched.

### Production simulator build

```text
flutter build ios --simulator --no-codesign
✓ Built build/ios/iphonesimulator/Runner.app
production bundle: com.terabooth.teraboothIpad
production licence: absent
```

Production configuration and bundle remain unchanged.

### Device build

Not attempted in this phase; Phase 3A-3B established that
`se.cascable.CascableCoreiOSDemo` cannot be registered to the Personal Team and
no matching profile exists. No workaround was applied.

---

## 4. Physical limitations

- No physical iPad app launch or UI inspection.
- No USB enumeration/discovery on iPadOS.
- No EOS 60D identification/connection.
- No property/storage readback.
- No Live View start/frame/termination test.
- No disconnect test.
- Native UI layout and logging are compile-verified only.
- The demo probe is not wired into BoothController and cannot be used as a
  production camera path.
- Physical signing/provisioning remains blocked by the demo bundle ID.

---

## 5. Required next action

1. Resolve demo bundle-ID provisioning without changing the licence-bound ID
   (Cascable/team ownership or an approved demo licence for a registrable ID).
2. Install a signed demo build on the iPad.
3. From the floating "Camera preflight" button, explicitly run USB discovery,
   connect, read properties/storage, optionally start/stop Live View, and
   disconnect.
4. Capture the probe logs and verify the EOS 60D. Do not add shutter/capture.

**Stopped after source-level verification. No install, launch or camera action.**
