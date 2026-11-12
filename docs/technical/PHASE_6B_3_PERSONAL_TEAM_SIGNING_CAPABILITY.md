# Phase 6B-3 — Isolated Personal Team Signing Capability Test

## Overall result

**CAPABILITY TEST PASS for build, signing and installation.**  
**Launch was blocked by iOS developer-profile trust**, not by signing.  
**Wildcard provisioning was NOT demonstrated.**

A disposable minimal iOS app with a unique explicit Bundle ID was built,
codesigned, and installed successfully on the connected iPad using the existing
free Personal Team. It was then uninstalled. No Terabooth target, Bundle ID,
certificate, entitlement, Cascable dependency or licence was modified.

No camera or printer command was executed.

---

## 1. Test environment

| Item | Value |
|---|---|
| iPad | iPad (A16), iPadOS 26.6 |
| Team | Ahmad Suhaib Personal Team |
| Signing | Automatic |
| Existing identity | Apple Development identity |
| Test app | Disposable Flutter iOS template under `/tmp` |
| Test Bundle ID | `com.terabooth.personalsigningprobe6b3` |
| Capabilities/entitlements | None |
| Existing Terabooth targets | Untouched |

---

## 2. Build and signing result

```text
** BUILD SUCCEEDED **
```

The Xcode log reported:

```text
Provisioning Profile: "iOS Team Provisioning Profile:
  com.terabooth.personalsigningprobe6b3"
  (bd3db3a4-1d92-463d-83ae-27cb45a39f85)

Signing Identity: Apple Development
```

This is a code-signing success for an **explicit** App ID.

### Generated profile

| Property | Result |
|---|---|
| Name | `iOS Team Provisioning Profile: com.terabooth.personalsigningprobe6b3` |
| UUID | `bd3db3a4-1d92-463d-83ae-27cb45a39f85` |
| App ID name | `XC com terabooth personalsigningprobe6b3` |
| Application identifier | `P2LJT7F45Y.com.terabooth.personalsigningprobe6b3` |
| Wildcard | **No — explicit App ID** |
| Xcode-managed | Yes |
| Current Apple Development certificate | **Included** (certificate hash matched the local identity) |
| Connected iPad UDID | **Included** |
| Provisioned devices | 1 |
| Created | 2026-11-12 |
| Expires | 2026-11-19 (7 days) |

The generated profile is **explicit**, not `*`. Therefore this test does **not**
prove Personal Team wildcard provisioning.

---

## 3. Installation result

```text
App installed:
bundleID: com.terabooth.personalsigningprobe6b3
```

**Installation succeeded on the physical iPad.**

---

## 4. Launch result

`devicectl` launch failed with:

```text
The request was denied by service delegate (SBMainWorkspace) for reason:
Security ("Unable to launch com.terabooth.personalsigningprobe6b3 because it has
an invalid code signature, inadequate entitlements or its profile has not been
explicitly trusted by the user").
```

This is the normal iOS **untrusted development profile** state. The app was
installed and signed, but iPadOS requires an operator to trust the developer
profile before first launch:

1. Settings → General → VPN & Device Management
2. Select the developer app/profile
3. Trust it
4. Re-launch

That trust action was **not** performed. Therefore:

- **Build success: YES**
- **Signing success: YES**
- **Installation success: YES**
- **Actual launch success: NO**
- **Wildcard profile: NOT DEMONSTRATED**

The launch failure is not a Personal Team restriction, App ID registration
failure, device registration failure, certificate/keychain failure or profile
generation failure.

---

## 5. What this proves — and what it does not

### Proved

- The Personal Team can register a new unique explicit App ID.
- It can generate an Xcode-managed provisioning profile for the connected iPad.
- The current Apple Development certificate and iPad UDID are valid.
- Automatic signing, codesigning and physical installation work.
- No paid membership was required for this explicit-ID test.

### Not proved

- That a wildcard App ID exists or can be used.
- That the Cascable demo Bundle ID can be provisioned.
- That the vendor-owned `se.cascable.CascableCoreiOSDemo` can be signed with a
  Personal Team profile.
- That launch succeeds without manual profile trust.

The explicit temporary ID succeeding is **not** evidence for wildcard support.

---

## 6. Implication for the Cascable demo

The demo remains blocked for a separate reason:

- `se.cascable.CascableCoreiOSDemo` is an unavailable explicit App ID for this
  team.
- Automatic signing attempts explicit registration and fails.
- No wildcard profile covering the demo Bundle ID is installed/selected.
- This isolated test used a brand-new explicit ID under `com.terabooth`, so it
  did not exercise the demo identifier or a wildcard.

The next demo-signing path remains: obtain/select a real Xcode-managed wildcard
team profile (or resolve the vendor App ID ownership with Apple/Cascable), then
try manual signing with that profile. Do not change the demo Bundle ID.

Paid membership is **not required for explicit Personal Team provisioning**.
Whether it is required for the wildcard path remains unproven.

---

## 7. Cleanup

- Disposable app uninstalled from the iPad.
- Temporary `/tmp` project and DerivedData removed.
- No shared certificate, key, provisioning profile or account asset was
  deleted or revoked.
- The generated explicit App ID/profile remain in the team account; they were
  not deleted.

---

## 8. Safety confirmation

| Check | Result |
|---|---|
| Terabooth production target modified | **NO** |
| `Runner-CascableDemo` modified | **NO** |
| Existing Bundle IDs changed | **NO** |
| Certificates revoked/replaced | **NO** |
| Entitlements/capabilities enabled | **NO** |
| Cascable dependency/licence modified | **NO** |
| Camera/shutter command | **NONE** |
| Printer command | **NONE** |
| App left installed | **NO** |
| MockCameraService default | **YES** |
| `USE_NATIVE_CAMERA` default | **FALSE** |

**Stopped after isolated capability verification.**
