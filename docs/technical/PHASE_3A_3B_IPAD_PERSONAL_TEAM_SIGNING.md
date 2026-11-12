# Phase 3A-3B — iPad Personal Team Signing Audit & Setup

## Overall result

**BLOCKED — signing configuration applied, but the physical device build cannot
provision the required demo bundle ID with the Personal Team.**

A valid Apple Development identity and the Personal Team are now visible, and
the demo target has automatic signing configured. Xcode's provisioning request
failed because `se.cascable.CascableCoreiOSDemo` is not available for
registration to this Personal Team.

No app was installed or launched. No camera or shutter operation occurred.

---

## 1. Initial audit

### Device

```text
Ahmad’s iPad
iPad (A16) (iPad15,7)
iPadOS 26.6
connected
```

`xcrun devicectl list devices` and `xcrun xctrace list devices` both show the
physical iPad. The simulator list is separate and was not used for the device
build.

### Signing at audit start

```text
security find-identity -p codesigning -v
0 valid identities found
```

Xcode did have a configured Personal Team, but there was no usable signing
identity in the keychain at the start. A later provisioning attempt created an
Apple Development identity; see below.

### Demo configuration

- Scheme: `Runner-CascableDemo`
- Configuration: `Debug-CascableDemo`
- Bundle ID: `se.cascable.CascableCoreiOSDemo`
- Swift condition: `CASCABLE_DEMO`
- iOS deployment target: `14.0`
- Device family: iPhone/iPad
- Licence copy phase: only for `Debug-CascableDemo`

### Production configuration

- Scheme: `Runner`
- Bundle ID: `com.terabooth.teraboothIpad`
- Licence copy phase: skipped
- No production signing settings were changed.

---

## 2. Changes made

File: `ipad_app/ios/Runner.xcodeproj/project.pbxproj`

Only the target-level `Debug-CascableDemo` configuration was changed:

```text
CODE_SIGN_STYLE = Automatic
DEVELOPMENT_TEAM = <existing Personal Team ID>
```

The existing Personal Team was read from Xcode's configured team data. No Team
ID was invented. The demo bundle ID was preserved.

The production `Debug`, `Release`, and `Profile` target configurations were not
changed.

No source code, licence file, SDK integration, bundle ID or camera service was
changed.

---

## 3. Demo build command

```bash
cd /Users/Apple/Dev/terabooth-event-mvp/ipad_app

xcodebuild \
  -project ios/Runner.xcodeproj \
  -scheme Runner-CascableDemo \
  -configuration Debug-CascableDemo \
  -destination 'id=00008120-0016705822220032' \
  -allowProvisioningUpdates \
  -derivedDataPath /tmp/terabooth-ipad-device-build \
  build
```

This is a build-only command. It does not install or launch the app.

---

## 4. Actual build result

**BUILD FAILED (exit 65).**

Exact provisioning errors:

```text
Failed Registering Bundle Identifier: The app identifier
"se.cascable.CascableCoreiOSDemo" cannot be registered to your development team
because it is not available. Change your bundle identifier to a unique string
to try again.

No profiles for 'se.cascable.CascableCoreiOSDemo' were found: Xcode couldn't
find any iOS App Development provisioning profiles matching
'se.cascable.CascableCoreiOSDemo'.
```

The bundle ID error is not bypassed or hidden. The demo identifier cannot be
changed because the Cascable demo licence is bundle-ID-specific.

### Signing status after the attempt

```text
security find-identity -p codesigning -v
1) Apple Development: ... (redacted)
1 valid identities found
```

A signing identity now exists, but it does not make the unavailable demo
identifier registrable.

---

## 5. Demo vs production verification

| Item | Demo | Production |
|---|---|---|
| Build configuration | `Debug-CascableDemo` | `Release` / `Debug` |
| Bundle ID | `se.cascable.CascableCoreiOSDemo` | `com.terabooth.teraboothIpad` |
| `CASCABLE_DEMO` | Yes | No |
| Licence copy phase | Copies for demo only | Skipped |
| Licence in built product | Present in simulator demo build | **Absent** |
| Signing team | Existing Personal Team configured | Unchanged |
| Physical build | **FAILED — bundle ID unavailable** | Not used |

Production simulator build independently passed:

```text
flutter build ios --simulator --no-codesign
✓ Built build/ios/iphonesimulator/Runner.app
bundle: com.terabooth.teraboothIpad
licence: absent
```

No production bundle ID or licence behavior was changed.

---

## 6. Safety and scope

- App installed: **NO**
- App launched: **NO**
- Camera discovery/connection: **NONE**
- Shutter/capture/transfer: **NONE**
- Camera settings changed: **NO**
- USB/PTP reset: **NO**
- Camera applications terminated: **NO**
- Licence contents read/printed: **NO**
- Production bundle ID changed: **NO**
- Production licence embedded: **NO**
- Flutter/camera architecture changed: **NO**

The existing demo probe still automatically enables the simulated camera and
issues a shutter after connection. It was not launched; it must be gated to a
USB-only, no-shutter preflight before any physical run.

---

## 7. Remaining blockers

1. **Demo bundle ID ownership/registration**
   - `se.cascable.CascableCoreiOSDemo` is unavailable to the Personal Team.
   - It cannot be changed without invalidating the Cascable licence.
   - Requires a team/account that can register that identifier, or
     Cascable-provided provisioning/ownership, or a licensing arrangement that
     supports a different bundle ID.
2. **Demo preflight safety**
   - Current `CascableCoreDemoProbe` automates simulated-camera capture.
   - Must be replaced/gated for USB-only, no-shutter diagnostics before launch.
3. **Physical camera preflight**
   - Not performed. No EOS 60D discovery, connection, properties or Live View
     validation on iPadOS exists.

Do not work around the bundle-ID restriction by changing identifiers or
bypassing signing.

**Stopped after the failed signed-device build.**
