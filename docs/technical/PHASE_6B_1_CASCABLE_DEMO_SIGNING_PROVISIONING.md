# Phase 6B-1 — Cascable Demo App Signing & Provisioning

## Overall result

**BLOCKED — demo signing/provisioning is not yet possible with the locally
available Apple team configuration.**

No account, certificate, App ID, entitlement or provisioning change was made.
No app was installed or launched. No camera or print action was performed.

---

## 1. Current environment

| Item | Observation |
|---|---|
| Physical iPad | Connected — iPad (A16), iPadOS 26.6 |
| Demo scheme | `Runner-CascableDemo` |
| Demo configuration | `Debug-CascableDemo` |
| Demo Bundle ID | `se.cascable.CascableCoreiOSDemo` |
| Demo team | Existing Personal Team configured |
| Signing style | Automatic |
| Valid signing identity | One Apple Development identity |
| Provisioning profiles | **None available locally** |
| Paid/development team in Xcode | **Not present**; only Personal Team |
| Entitlements file | None |
| CascableCore | 18.0.2, unchanged |
| Production Bundle ID | `com.terabooth.teraboothIpad` |

The Xcode account/team metadata contains only the Personal Team. Account
credentials and Apple ID details are deliberately not reproduced here.

---

## 2. Root cause

The previous device build failed at provisioning with:

```text
The app identifier "se.cascable.CascableCoreiOSDemo" cannot be registered to
your development team because it is not available.
No profiles for 'se.cascable.CascableCoreiOSDemo' were found.
```

This is an App ID ownership/availability and provisioning-profile problem, not
a certificate-only problem:

- The demo Bundle ID must remain exactly `se.cascable.CascableCoreiOSDemo`
  because the Cascable evaluation licence is bundle-ID-specific.
- The Personal Team cannot register that identifier directly.
- No matching provisioning profile exists locally.
- No wildcard App ID is present in the available team/profile data.
- A wildcard App ID cannot be invented or assumed to exist; it must belong to
  the selected Apple team and be valid for this bundle identifier.

The production Bundle ID is unaffected. No ad-hoc or entitlement bypass was
attempted.

---

## 3. Wildcard App ID status

**Not available/verified locally.** There are no provisioning profiles and no
local evidence of a wildcard App ID for the Personal Team.

Portal state cannot be verified from this Mac session without the account
owner's authenticated Apple Developer access. Therefore:

- I cannot claim a wildcard exists.
- I cannot claim the Personal Team can create one.
- I cannot claim a paid team is available locally.
- I did not register an App ID or create a profile.

Cascable support's wildcard guidance is the relevant next path, but the actual
team portal state must be checked by the account owner.

---

## 4. Which team should be used

Use an Apple team that:

1. is authorized for the account/device being used;
2. can own a wildcard App ID that matches
   `se.cascable.CascableCoreiOSDemo`;
3. can create an iOS App Development provisioning profile for that App ID;
4. has the Apple Development certificate installed on this Mac.

The only team currently visible to Xcode is the **Ahmad Suhaib Personal Team**.
A paid team is **not present locally** according to Xcode metadata. If the
Personal Team cannot access wildcard App ID management, a paid Apple Developer
team will be required, or Cascable/Apple must provide an authorized
provisioning path for their demo identifier.

Do not change the demo Bundle ID and do not use a production/team-owned
identifier as a workaround.

---

## 5. Minimum official manual steps

These require the account owner's explicit approval and Apple Developer portal
access. No step was performed.

1. Sign in to the Apple Developer account for the intended team and open
   **Certificates, Identifiers & Profiles → Identifiers**.
2. Determine whether a wildcard App ID already exists that can cover
   `se.cascable.CascableCoreiOSDemo` for this team.
3. If absent and permitted by the account type, register the appropriate
   wildcard App ID. Do not change the required demo Bundle ID. Do not add
   entitlements that are not required.
4. Ensure the Apple Development certificate and team are available in Xcode:
   **Xcode → Settings → Accounts → team → Manage Certificates**.
5. In the demo target (`Debug-CascableDemo` only), select that team with
   Automatic signing. Production signing must remain unchanged.
6. Build the demo for the physical iPad with `-allowProvisioningUpdates`.
7. Verify the profile covers `se.cascable.CascableCoreiOSDemo` before installing.
8. Only after signing succeeds, install/launch and perform non-capture
   connection checks. Camera capture/Live View remain separately authorized.

If Apple reports that the identifier is owned by another team, the account
owner must resolve ownership with Apple/Cascable; changing the ID is not an
acceptable workaround.

---

## 6. Is physical installation possible now?

**No.** The demo target has a valid development identity and connected iPad, but
no valid provisioning profile/wildcard for the required demo Bundle ID.

No further signing retry was made in this phase. Repeating builds with different
IDs would violate the constraint and invalidate the licence.

---

## 7. Safety confirmation

| Check | Result |
|---|---|
| Demo Bundle ID changed | **NO** |
| Production Bundle ID changed | **NO** |
| Licence read/printed/changed | **NO** |
| App installed/launched | **NO** |
| Camera discovery/connection/Live View | **NONE** |
| Shutter/capture/transfer/settings | **NONE** |
| Physical print | **NONE** |
| Account/certificate/App ID changes | **NONE** |
| Ad-hoc signing/entitlement bypass | **NONE** |
| MockCameraService default | **YES** |
| `USE_NATIVE_CAMERA` default | **FALSE** |

**Stopped at the provisioning gate.**
