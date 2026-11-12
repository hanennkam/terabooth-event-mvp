# Phase 6B-2 — Personal Team XC Wildcard Provisioning Investigation

## Overall result

**BLOCKED for installation; investigation complete.**

The app is technically eligible for a wildcard team provisioning profile, but no
such profile is currently available locally, and automatic signing is attempting
an explicit App ID instead. The required demo Bundle ID remains unchanged.

No project, account, certificate, entitlement or provisioning changes were made.
No app was installed or launched. No camera or print action occurred.

---

## 1. Current signing state

| Item | Observation |
|---|---|
| Demo scheme | `Runner-CascableDemo` |
| Demo configuration | `Debug-CascableDemo` |
| Bundle ID | `se.cascable.CascableCoreiOSDemo` |
| Team | Ahmad Suhaib Personal Team (free provisioning team) |
| Paid team in Xcode | **None visible** |
| Signing style | Automatic |
| Development identity | One valid Apple Development identity |
| Provisioning profiles installed | **None** |
| Entitlements file | None |
| Connected iPad | iPad (A16), iPadOS 26.6 |

`xcodebuild -showBuildSettings` confirms:

```text
CODE_SIGN_STYLE = Automatic
DEVELOPMENT_TEAM = <Personal Team>
PRODUCT_BUNDLE_IDENTIFIER = se.cascable.CascableCoreiOSDemo
PROVISIONING_PROFILE_REQUIRED = YES
```

---

## 2. Root cause of the current failure

Automatic signing is trying to register an **explicit App ID** for
`se.cascable.CascableCoreiOSDemo`. That identifier is already unavailable to
this team, so Xcode reports:

```text
The app identifier "se.cascable.CascableCoreiOSDemo" cannot be registered to
your development team because it is not available.
No profiles for 'se.cascable.CascableCoreiOSDemo' were found.
```

The failure is not a missing certificate. A valid Apple Development identity is
present. It is an App ID/provisioning-profile selection failure.

Xcode's automatic-signing path is choosing explicit registration rather than a
wildcard team profile. No wildcard profile is downloaded locally, and there is no
local evidence that one currently exists for this team.

---

## 3. Is Personal Team wildcard provisioning technically possible?

**Conditionally yes, but not yet demonstrated on this machine.**

Apple's Xcode documentation states that when an app can use a wildcard App ID,
Xcode creates a wildcard team provisioning profile (for example,
`iOS Team Provisioning Profile: *`). Apps with capabilities requiring an explicit
App ID force explicit registration.

The Terabooth demo app has:

- no entitlements file;
- no app groups, iCloud, push, HealthKit, IAP or other explicit-ID capability;
- only ordinary app runtime requirements.

That makes it **eligible** for a wildcard profile from a technical standpoint.

However:

- no wildcard provisioning profile is currently installed;
- no wildcard App ID is visible in local team/profile data;
- the Personal Team's ability to create/download such a profile cannot be
  confirmed without the account owner's authenticated Xcode/Developer access;
- a wildcard profile from this team would not change or re-register the
  licence-bound Bundle ID.

Therefore I cannot claim Personal Team wildcard provisioning is already
available. It is the correct supported path to investigate next.

---

## 4. Why automatic signing does not use the wildcard

Xcode automatic signing chooses an explicit App ID when it believes the app or
project requires one, or when it cannot find an applicable wildcard team profile.
The current build has no wildcard profile selected/downloaded, so automatic
signing attempts explicit registration and fails on the unavailable identifier.

This is consistent with Apple's documented behavior for team provisioning
profiles:

- wildcard profile if the app can use a wildcard App ID;
- explicit App ID/profile if a capability requires it;
- explicit App ID exactly matches the bundle ID.

See Apple's [team provisioning profile documentation](https://help.apple.com/xcode/mac/current/en.lproj/deveb89b08eb.html).

---

## 5. Safest next configuration to try

Do this only after account-owner approval; it does not change the Bundle ID,
licence, certificates, entitlements or account settings.

1. In Xcode **Settings → Accounts**, select the Personal Team and choose
   **Download Manual Profiles**. This is the supported way to fetch Xcode-managed
   team profiles for local use.
2. Inspect the demo target **Signing & Capabilities** with
   **Automatically manage signing disabled**.
3. Select the Personal Team.
4. If `iOS Team Provisioning Profile: *` (or equivalent wildcard team profile)
   appears, select it manually for `Debug-CascableDemo`.
5. Build for the connected iPad without changing the Bundle ID.
6. If no wildcard profile appears, the account owner must check whether the
   Personal Team can register/obtain a suitable wildcard App ID/profile in the
   Apple Developer portal. Do not create a new identifier or change the demo ID.

Equivalent build-setting shape, once a real wildcard profile exists:

```text
CODE_SIGN_STYLE = Manual
DEVELOPMENT_TEAM = <Personal Team>
PROVISIONING_PROFILE_SPECIFIER = <the actual downloaded wildcard profile name/UUID>
CODE_SIGN_IDENTITY = Apple Development
PRODUCT_BUNDLE_IDENTIFIER = se.cascable.CascableCoreiOSDemo
```

The profile field must reference the actual downloaded profile, not an invented
UUID or name. Do not apply this until the profile is present.

---

## 6. Is paid Apple Developer membership necessary?

**Not proven.**

- Apple's documentation describes wildcard team provisioning for Xcode-managed
  teams; it does not state that paid membership is required for this case.
- The app has no explicit-ID capabilities.
- Cascable support states demo licences work with personal or paid accounts
  provided a wildcard App ID is registered.
- The current Personal Team has no downloaded wildcard profile, so the practical
  blocker is profile availability, not proof that payment is required.
- If the free Personal Team cannot access/create a wildcard App ID/profile, a
  paid team may be needed—but that must be confirmed by the account owner/Apple,
  not assumed.

Do not upgrade or purchase membership without explicit owner approval.

---

## 7. Can the app be installed now?

**No.**

Required missing pieces:

1. A valid wildcard team provisioning profile covering
   `se.cascable.CascableCoreiOSDemo`.
2. Manual signing selection of that profile for the demo target only.
3. A successful signed device build.

The production Bundle ID, licence and MockCameraService default remain
untouched.

---

## 8. Safety confirmation

| Check | Result |
|---|---|
| Project/source changed | **NO** |
| Bundle ID changed | **NO** |
| Account/certificate/App ID changed | **NO** |
| Entitlements changed | **NO** |
| Licence read/printed/changed | **NO** |
| Signing build retried | **NO** |
| App installed/launched | **NO** |
| Camera/print operation | **NONE** |
| MockCameraService default | **YES** |
| `USE_NATIVE_CAMERA` default | **FALSE** |

**Stopped at the wildcard-profile gate.**
