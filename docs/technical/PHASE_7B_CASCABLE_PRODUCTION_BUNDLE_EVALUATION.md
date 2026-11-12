# Phase 7B — Cascable Production-Bundle Evaluation Preparation

## Overall result

**BLOCKED at vendor licence.** The existing demo licence is definitively invalid
for the production Bundle ID.

No physical camera action or print occurred. Production remains MockPrinter.

---

## 1. Licence validation test

A simulator-only evaluation artifact was built with:

- production Bundle ID: `com.terabooth.teraboothIpad`
- demo compilation conditions (`CASCABLE_DEMO`)
- existing local demo licence copied into the app
- no code signing, no device install, no camera use

Simulator launch log:

```text
CASCABLE_DEMO_LICENSE_RESULT=2 configured=true
```

CascableCore SDK header:

```objc
typedef NS_ENUM(NSUInteger, CBLLicenseVerificationResult) {
    CBLLicenseVerificationResultSuccess = 0,
    CBLLicenseVerificationResultExpired = 1,
    CBLLicenseVerificationResultInvalidLicense = 2
};
```

Therefore:

- **Result 2 = InvalidLicense**
- The current demo licence does **not** authorize
  `com.terabooth.teraboothIpad`.
- It is intended for the Cascable demo Bundle ID
  `se.cascable.CascableCoreiOSDemo`.
- No build-configuration trick can legitimately change that.

This was a simulator licence check only; the iPad was not modified and no camera
was touched.

---

## 2. Current production configuration

| Setting | Value |
|---|---|
| Production scheme | `Runner` |
| Production Bundle ID | `com.terabooth.teraboothIpad` |
| Production licence | **none / invalid demo** |
| `USE_NATIVE_CAMERA` default | `false` |
| Demo compile flag | `CASCABLE_DEMO` |
| Demo Bundle ID | `se.cascable.CascableCoreiOSDemo` |
| Demo provisioning | **blocked; no wildcard profile** |
| Production signing | existing Personal Team profile |

`AppDelegate` applies the licence only inside `#if CASCABLE_DEMO`. The production
build has no valid licence path.

---

## 3. Minimum vendor requirement

To enable real EOS 60D testing in the production app, Cascable must issue a
CascableCore 18.0.2 evaluation/production licence bound to:

```text
com.terabooth.teraboothIpad
```

The licence must be valid for the Apple team/account used for signing. The demo
licence or demo Bundle ID cannot be substituted.

Once that licence is available, the minimum build configuration is:

1. Production Bundle ID: `com.terabooth.teraboothIpad`.
2. Production signing/profile; no demo Bundle ID.
3. Licence file supplied privately for that exact Bundle ID.
4. Licence applied in the **production** build path (currently only
   `CASCABLE_DEMO` does this).
5. Flutter build with:
   ```text
   --dart-define=USE_NATIVE_CAMERA=true
   ```
6. A dedicated local evaluation build configuration that does not change the
   default production configuration.
7. Install on iPad, verify licence success, then connect EOS 60D.

No such licence is currently present. The evaluation configuration cannot be
made functional by code changes alone.

---

## 4. Ready-to-build recipe after vendor licence arrives

The licence file must remain private and must not be committed.

Suggested local evaluation settings:

```text
Configuration:        Release-Evaluation (local only)
Bundle ID:            com.terabooth.teraboothIpad
Signing:              existing production Personal Team profile
Swift condition:      CASCABLE_LICENSE (new, to decouple licence from demo probe)
Dart define:          USE_NATIVE_CAMERA=true
Licence resource:     production licence for com.terabooth.teraboothIpad
Demo probe:           disabled
```

A small code change is required to apply the licence outside `CASCABLE_DEMO`:
a distinct `CASCABLE_LICENSE` compile condition. This should be added only when
the production licence is available, so a build cannot accidentally ship with
the demo licence or a missing/invalid licence.

Do not:
- install the demo profile on production;
- reuse the demo Bundle ID for shipping;
- copy the demo licence into a production release;
- disable or bypass `CascableCoreLicenseVerification`.

---

## 5. Evidence reused

- Prior production app build/launch/Bridge/upload evidence remains valid.
- Phase 6G/6I print tests remain valid (74/77 passing as previously recorded).
- No code or tests were changed in this phase.
- No full regression rerun was necessary.

---

## 6. Safety

| Check | Result |
|---|---|
| Physical camera action | **NONE** |
| Physical print | **NONE** |
| iPad modified | **NO** |
| Simulator test only | **YES** |
| Licence contents exposed | **NO** |
| Demo Bundle ID changed | **NO** |
| Production Bundle ID changed | **NO** |
| Production default build changed | **NO** |
| Camera architecture changed | **NO** |
| MockPrinter active | **YES** |
| Spooler enabled | **NO** |

**Stopped at the vendor licence dependency.**
