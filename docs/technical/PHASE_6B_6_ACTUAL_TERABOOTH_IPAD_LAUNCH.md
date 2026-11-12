# Phase 6B-6 — Install & Launch Actual Terabooth on Physical iPad

## Overall result

**PASS for signed Release installation and confirmed launch.**  
**PARTIAL UI smoke test** — Home and Settings confirmed; Events opens; Events
back navigation was not tested. A local test event was created by the operator.

No camera, shutter, Live View, Bridge, QR, printer or Cascable demo operation was
performed.

---

## 1. Preflight findings

| Item | Finding |
|---|---|
| Repository | `/Users/Apple/Dev/terabooth-event-mvp` |
| Production scheme | `Runner` |
| Production target | `Runner` |
| Production configuration used | `Release` for final launch |
| Production Bundle ID | `com.terabooth.teraboothIpad` |
| Team | Ahmad Suhaib Personal Team (`P2LJT7F45Y`) |
| Signing identity | Apple Development (`77NVN3L7DW`) |
| Entitlements | None |
| Device | iPad (A16), iPadOS 26.6 |
| Developer Mode | Enabled |
| Mock camera default | **Yes** |
| `USE_NATIVE_CAMERA` | **false** |
| Cascable demo scheme selected | **No** |
| Windows Bridge/printer changes | **None** |

The production target had no development team configured; the team and automatic
signing were supplied only as temporary `xcodebuild` overrides.

---

## 2. Signing and provisioning

Xcode automatic signing created new development assets for the existing
production bundle ID:

| Property | Value |
|---|---|
| App ID / application identifier | `P2LJT7F45Y.com.terabooth.teraboothIpad` |
| Profile name | `iOS Team Provisioning Profile: com.terabooth.teraboothIpad` |
| Profile UUID | `0a12cb09-dbbd-4c11-856d-3b44a94b80c3` |
| Type | **Explicit App ID** (not wildcard) |
| Created | 2026-11-12 12:51:52 UTC |
| Expiration | 2026-11-19 12:51:52 UTC |
| Provisioned device | `00008120-0016705822220032` |
| Certificate | Current Apple Development identity; hash matched |
| `get-task-allow` | true |
| Demo licence in app | **Absent** |
| `CASCABLE_DEMO` in build | **Absent** |

No project signing setting, Bundle ID, certificate, entitlement or demo target
was permanently changed.

---

## 3. Build results

### Debug build

- Build: **PASS**
- Signing: **PASS**
- Installation: **PASS**
- Standalone launch: **FAIL**

Console evidence:

```text
Cannot create a FlutterEngine instance in debug mode without Flutter tooling or Xcode.
To launch in debug mode in iOS 14+, run flutter run from Flutter tools, run from
an IDE with a Flutter IDE plugin or run the iOS project from Xcode.
Alternatively profile and release mode apps can be launched from the home screen.
```

The debug app installed but displayed no UI when launched outside Flutter
tooling/Xcode. This is a known Flutter debug-launch constraint, not a signing or
provisioning failure.

### Release build

- Build: **PASS**
- Signing: **PASS**
- Correct bundle ID: **PASS**
- Correct team: **PASS**
- Provisioning profile matches app/certificate/iPad: **PASS**
- Demo licence absent: **PASS**
- Installation over the debug build: **PASS**

The Release build was used for the successful physical launch.

---

## 4. Installation and trust

| Step | Result |
|---|---|
| Release installation | **PASS** |
| `devicectl` app listing | `com.terabooth.teraboothIpad` — **Terabooth Ipad** |
| Trust prompt | **None** — existing Apple Development identity already trusted |
| Operator-confirmed launch | **PASS** |
| Running process | **PASS — PID 837** |

The disposable **Personal Signing Probe 6b5** remains installed and untouched.

---

## 5. UI smoke test

| Check | Status | Evidence |
|---|---|---|
| Home/welcome screen renders | **PASS** | Operator-confirmed |
| Events screen opens | **PASS** | Operator-confirmed |
| Events back navigation | **NOT TESTED** | Operator did not use the top-left back control |
| Settings screen opens | **PASS** | Operator-confirmed |
| Navigation between Home/Settings | **PASS** | Operator-confirmed |
| No immediate crash/blank after Release launch | **PASS** | Operator-confirmed; process running |
| Capture screen safe rendering | **NOT TESTED** | Not opened to avoid session/camera actions |
| Session creation | **NOT PERFORMED** | — |
| QR/Bridge/print | **NOT TESTED** | Out of scope |

### Local data side effect

The operator created a test event in the app on the iPad. This is local app data,
not repo or Windows Bridge data. It was **not deleted** because no destructive
cleanup was authorized.

---

## 6. Device logs

- No Runner/Terabooth crash report was present in the device crash-log listing
  after launch.
- Debug launch console produced the exact Flutter debug-engine message above.
- Release process remained alive (PID 837) after UI checks.
- Sysdiagnose collection was attempted read-only but failed with
  `CoreDeviceCLISupport.DiagnoseError`; no device reset or setting change was
  made.

No startup exception was observed in Release.

---

## 7. Files changed

This phase changed **no application source, Xcode project, Bundle ID, signing
configuration, entitlements, Cascable configuration or Windows Bridge files**.

Documentation only:

- `docs/technical/PHASE_6B_6_ACTUAL_TERABOOTH_IPAD_LAUNCH.md`
- `README.md`
- `docs/IMPLEMENTATION_LOG.md`

Build artifacts are in `/tmp/terabooth-production-6b6`.

---

## 8. Explicitly NOT tested

- CascableCore initialization/discovery/connection
- Native USB camera
- Live View
- Shutter/capture/original transfer
- Capture screen interaction/session workflow
- Bridge connectivity
- QR delivery
- Printing/physical printer
- Production event data migration/cleanup
- Wildcard provisioning
- Demo Bundle ID signing

---

## 9. Status summary

| Area | Status |
|---|---|
| Preflight | **PASS** |
| Production signing | **PASS** |
| Debug standalone launch | **FAIL** (Flutter debug-only limitation) |
| Release build | **PASS** |
| Installation | **PASS** |
| Developer trust | **PASS** (existing trust, no prompt) |
| Launch | **PASS** |
| Home | **PASS** |
| Events opens | **PASS** |
| Events back | **NOT TESTED** |
| Settings | **PASS** |
| Camera/printer/Bridge | **NOT TESTED** |

**Stopped after the physical UI smoke test.**
