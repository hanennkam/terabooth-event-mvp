# Phase 3A-1A — Licence Activation & Dependency Stabilization

**Date:** 2026-11-12  
**Overall:** **PARTIAL — licence and SPM PASS; simulated validation PASS; EOS 60D macOS physical subset later PASSED.**

> **Follow-up (2026-11-12):** Phase 3A-1B validated the physical EOS 60D over USB on macOS for discovery/settings/Live View/shutter request/disconnect-reconnect. iPadOS and image transfer remain unverified. See `PHASE_3A_1B_CANON_60D_MAC_SDK_VALIDATION.md`.

The licence was supplied locally, activated successfully, and the official remote
SPM graph now resolves with a committed-safe `Package.resolved`. The demo app
launches with the licensed demo bundle ID and the simulated camera completes
discovery, connection, Live View, shutter request, preview transfer and
disconnect. No physical EOS 60D was available.

---

## Task 1 — Licence validation: **PASS**

### Supplied artifact

The supplied archive was a zip containing the official:

```text
CascableCoreLicense.swift
CascableCoreLicense.h
CascableCoreLicense.m
Applying Your License.playground
```

The Swift source embedded the issued `[UInt8]` licence bytes. The archive was
extracted only in a private temporary directory. Its numeric byte array was
converted to the ignored binary loader path:

```text
ipad_app/ios/Runner/CascableCoreLicense.licence
```

No licence bytes, key, hash or token were printed, documented or committed.
The archive was moved out of the repository. The derived file is:

- **471 bytes**
- mode **0600**
- loaded by `CascableCoreLicense.swift`
- copied into the demo app by the optional build phase
- excluded by `.gitignore`

`.gitignore` now covers:

```text
CascableCoreLicense.licence
*.cascablelicence
/ios/Runner/CascableCore Demo License*.zip
```

### Exact SDK result

The demo app was launched and produced:

```text
CASCABLE_DEMO_LICENSE_RESULT=0 configured=true
CASCABLE_DEMO_LICENSE=applied
CASCABLE_DEMO_PLUGINS=["se.cascable.CascableCore.plugin.simulated-camera"]
```

`0` is the official `LicenseVerificationResult.success`.

### Bundle ID and bundle contents

```text
bundle=se.cascable.CascableCoreiOSDemo
licence_in_bundle=yes bytes=471
```

The production app was also built and checked:

```text
prod_bundle=com.terabooth.teraboothIpad
prod_licence_absent
```

The licence copy phase is explicitly restricted to
`CONFIGURATION == Debug-CascableDemo`; production does not receive the file.

**Task 1 result: PASS.**

---

## Task 2 — Remote SPM stabilization: **PASS**

### References

Only official remote repository references remain for Cascable:

- `https://github.com/Cascable/cascablecore-distribution` — 18.0.2
- `https://github.com/Cascable/cascablecore-swift` — 18.0.2
- `https://github.com/Cascable/cascablecore-simulated-camera` — 1.0.14

The only local package reference is Flutter's normal generated:
`Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage`.

No temporary local-package path remains.

### Root cause of the Git transport stall

Xcode's package resolver was performing a full `git clone --mirror` of the
large CascableCore repository. That full-history clone stalled in Git transport.

Diagnosis:

- `git ls-remote` and HTTPS to GitHub worked.
- A shallow official clone succeeded in about 43 seconds:

```bash
git clone --bare --depth 1 --branch 18.0.2 \
  https://github.com/Cascable/cascablecore-distribution.git \
  /tmp/cascable-shallow-test
```

The shallow official repositories were used only to seed SwiftPM's local
package cache. They are not linked into the Xcode project and are not a
substitute package. The final project references the official remote URLs.

### Resolution command and result

```bash
cd ipad_app
xcodebuild -resolvePackageDependencies \
  -project ios/Runner.xcodeproj \
  -scheme Runner-CascableDemo
```

Result: **exit 0**, with:

```text
CascableCore:                  https://github.com/Cascable/cascablecore-distribution @ 18.0.2
CascableCoreSwift:             https://github.com/Cascable/cascablecore-swift @ 18.0.2
CascableCoreSimulatedCamera:   https://github.com/Cascable/cascablecore-simulated-camera @ 1.0.14
```

### `Package.resolved`

Generated at:

```text
ipad_app/ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

Pins:

| Package | Version | Revision |
|---|---:|---|
| cascablecore-distribution | 18.0.2 | `4407ce7682e82bb0b152ddcfad4cfd98609941fa` |
| cascablecore-simulated-camera | 1.0.14 | `64620d41f184a8ad5a0933424ba22f94b600d158` |
| cascablecore-swift | 18.0.2 | `69a6c1dfda0cf732d884e5c4984e456ec800fdb0` |

No versions were upgraded beyond the Phase 3A-1 set.

### Optional CascableCoreSwift decision

`CascableCoreSwift` remains resolved but is **not linked to the Runner target**.
The demo probe uses the binary Core and Simulated Camera APIs. Linking the
optional Swift product compiles its Metal shader and requires the separate
Xcode Metal Toolchain, which was unavailable (download stalled). Because the
product is not used in this phase, it was unlinked rather than installing or
altering unrelated tooling.

If Live View Swift publishers/Metal rendering are adopted later, install the
official Metal Toolchain and re-add the product.

**Task 2 result: PASS.**

---

## Task 3 — Demo build: **PASS**

### Commands

```bash
cd ipad_app
xcodebuild -project ios/Runner.xcodeproj \
  -scheme Runner-CascableDemo \
  -configuration Debug-CascableDemo \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=552D64BA-85B9-4DFE-B3EA-10E24FDDCC34' \
  -derivedDataPath /tmp/TeraboothDemoDerived \
  build

flutter analyze
flutter test
```

### Results

| Check | Result |
|---|---|
| Demo build | **BUILD SUCCEEDED** |
| Demo bundle ID | **`se.cascable.CascableCoreiOSDemo`** |
| Demo launch | **PASS** |
| Licence in demo bundle | **PASS — 471 bytes** |
| Production build | **PASS — 174 MB** |
| Production bundle ID | **`com.terabooth.teraboothIpad`** |
| Licence in production bundle | **ABSENT** |
| `flutter analyze` | **No issues** |
| Flutter tests | **87 passed** |
| Python tests | **39 passed** |

**Task 3 result: PASS.**

---

## Task 4 — Simulated Camera: **PASS with explicit limitations**

The official plugin loaded:

```text
CASCABLE_DEMO_PLUGINS=["se.cascable.CascableCore.plugin.simulated-camera"]
```

### Exact events observed

```text
CASCABLE_DEMO_DISCOVERY=started
CASCABLE_DEMO_DISCOVERED=Simulated Camera transport=CBLCameraTransport(rawValue: 0)
CASCABLE_DEMO_LOST_SIGHT=Simulated Camera
CASCABLE_DEMO_CONNECT=connected warnings=0 state=CBLCameraConnectionState(rawValue: 2)
CASCABLE_DEMO_CAPTURE_REQUEST=sent error=none
CASCABLE_DEMO_LIVE_VIEW=frame size=(864.0, 576.0) format=CBLCameraLiveViewFramePixelFormat(rawValue: 0)
CASCABLE_DEMO_TRANSFER=preview_available
CASCABLE_DEMO_TRANSFER=preview_received size=(864.0, 576.0)
CASCABLE_DEMO_DISCONNECT=requested
CASCABLE_DEMO_LIVE_VIEW=terminated reason=CBLCameraLiveViewTerminationReason(rawValue: 0) error=none
CASCABLE_DEMO_DISCONNECT=complete error=none
```

| Test | Result |
|---|---|
| SDK initialization / licence | **PASS — result 0** |
| Simulated discovery | **PASS — `Simulated Camera`** |
| Connection | **PASS — connected, 0 warnings, state 2** |
| Discovery/state events | **PASS — discovery, lost-sight, connected state** |
| Live View availability | **PASS — 864×576 frame** |
| Shutter request | **PASS — request sent, no error** |
| Image transfer | **PASS — preview 864×576** |
| Disconnection | **PASS — requested/complete; Live View terminated normally** |
| Original JPEG transfer | **NOT SUPPORTED / NOT TESTED** |
| Camera-initiated original transfer | **NOT SUPPORTED by official simulated plugin** |
| Physical EOS 60D behavior | **NOT TESTED** |

The shutter API callback means the request was sent; it does not prove a
physical camera fired. Only a preview transfer was validated. No original JPEG
or EOS 60D capture claim is made.

**Task 4 result: PASS for simulated scope; original JPEG remains NOT VALIDATED.**

---

## Reproducible commands

```bash
cd /Users/Apple/Dev/terabooth-event-mvp/ipad_app

# Remote resolution
xcodebuild -resolvePackageDependencies \
  -project ios/Runner.xcodeproj \
  -scheme Runner-CascableDemo

# Demo build
xcodebuild -project ios/Runner.xcodeproj \
  -scheme Runner-CascableDemo \
  -configuration Debug-CascableDemo \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=552D64BA-85B9-4DFE-B3EA-10E24FDDCC34' \
  -derivedDataPath /tmp/TeraboothDemoDerived \
  build

# Install and launch the demo
xcrun simctl install 552D64BA-85B9-4DFE-B3EA-10E24FDDCC34 \
  /tmp/TeraboothDemoDerived/Build/Products/Debug-CascableDemo-iphonesimulator/Runner.app
xcrun simctl launch 552D64BA-85B9-4DFE-B3EA-10E24FDDCC34 \
  se.cascable.CascableCoreiOSDemo

# Flutter/tests
flutter analyze
flutter test
cd ../windows_bridge && ./.venv/bin/pytest -q
```

The licence artifact must be present locally at the ignored path before the
demo build; it is intentionally absent from source control. Do not print its
contents or add it to documentation.

---

## Remaining blockers

1. **EOS 60D compatibility** — still absent from Cascable's official Canon
   compatibility list; no physical USB/PTP/remote shutter/Live View/original
   JPEG validation.
2. **Original JPEG transfer** — not supported by the simulated camera and not
   tested on EOS 60D.
3. **Physical iPad signing/install** — not tested.
4. **Optional CascableCoreSwift** — not linked; requires Apple Metal Toolchain
   if the Swift Live View rendering APIs are adopted later.
5. **No camera pipeline integration** — not started, by constraint.
