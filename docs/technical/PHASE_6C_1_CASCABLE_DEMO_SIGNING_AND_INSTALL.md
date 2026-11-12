# Phase 6C-1 — Cascable Demo Signing & Physical iPad Installation

## Overall result

**BLOCKED — no wildcard provisioning profile is available for the Cascable demo
Bundle ID.**

Per the phase rule, no demo build, signing attempt or installation was performed.
No camera or printer command was executed.

---

## 1. Wildcard App ID / profile availability

Local provisioning profiles:

| UUID | Name | Application identifier | Expiry |
|---|---|---|---|
| `bd3db3a4-1d92-463d-83ae-27cb45a39f85` | `iOS Team Provisioning Profile: com.terabooth.personalsigningprobe6b3` | `P2LJT7F45Y.com.terabooth.personalsigningprobe6b3` | 2026-11-19 |
| `0a12cb09-dbbd-4c11-856d-3b44a94b80c3` | `iOS Team Provisioning Profile: com.terabooth.teraboothIpad` | `P2LJT7F45Y.com.terabooth.teraboothIpad` | 2026-11-19 |

Both are **explicit** App IDs. There is:

- no `iOS Team Provisioning Profile: *`;
- no profile with `application-identifier` `P2LJT7F45Y.*`;
- no profile covering `se.cascable.CascableCoreiOSDemo`.

Xcode still exposes only the free **Ahmad Suhaib Personal Team**
(`P2LJT7F45Y`). No paid team is present locally.

The portal's wildcard App ID inventory cannot be verified without the account
owner's authenticated Apple Developer access. What is confirmed is that no
usable wildcard **profile** is available locally.

---

## 2. Demo target / SDK / licence evidence

| Item | Finding |
|---|---|
| Scheme | `Runner-CascableDemo` |
| Configuration | `Debug-CascableDemo` |
| Bundle ID | `se.cascable.CascableCoreiOSDemo` |
| Signing style | Automatic |
| Team | `P2LJT7F45Y` |
| `SWIFT_ACTIVE_COMPILATION_CONDITIONS` | `DEBUG CASCABLE_DEMO` |
| CascableCore distribution | **18.0.2** |
| CascableCore Swift | **18.0.2** |
| Demo licence | Present, 471 bytes, mode 600; contents not read |
| Production Bundle ID | `com.terabooth.teraboothIpad` — unchanged |
| Production target/capabilities | Unchanged |

The demo licence copy phase is restricted to `Debug-CascableDemo`; production
does not include it.

---

## 3. Signing feasibility

**Not feasible with currently available signing assets.**

Automatic signing for `se.cascable.CascableCoreiOSDemo` would attempt an explicit
App ID registration. That identifier is unavailable to this Personal Team, and
no wildcard profile exists to authorize it.

No manual signing profile can be selected because no wildcard profile exists.

Do not fabricate a profile, change the bundle ID, alter entitlements or bypass
provisioning.

---

## 4. Build / installation / launch

| Step | Status |
|---|---|
| Demo build | **NOT ATTEMPTED** |
| Demo signing | **BLOCKED** |
| Installation | **NOT ATTEMPTED** |
| Operator trust | **NOT REACHED** |
| Launch | **NOT TESTED** |
| CascableCore initialization | **NOT TESTED** |

The production Terabooth app and Personal Signing Probe remain installed and
untouched.

---

## 5. Exact blocker and shortest legitimate next action

### Missing prerequisite

A valid Xcode-managed **wildcard** team provisioning profile, owned by a team
authorized for this Mac/device, that can cover
`se.cascable.CascableCoreiOSDemo`, with:

- the current Apple Development certificate;
- the connected iPad UDID;
- a non-expired validity period.

### Shortest legitimate next action

1. Account owner opens **Xcode → Settings → Accounts → Personal Team** and uses
   **Download Manual Profiles**.
2. If a wildcard team profile (`iOS Team Provisioning Profile: *`) appears,
   select it manually for `Debug-CascableDemo` and build.
3. If no wildcard profile appears, account owner checks **Certificates,
   Identifiers & Profiles → Identifiers** for a wildcard App ID that can cover
   the demo ID, and creates/authorizes one only if their account permits it.
4. Do not change the demo Bundle ID, buy membership, alter entitlements or use
   ad-hoc signing.

No account/App ID/profile changes were made in this phase.

---

## 6. Safety confirmation

| Check | Result |
|---|---|
| Demo build attempted | **NO** |
| Install/launch attempted | **NO** |
| Production Bundle ID/signing changed | **NO** |
| Demo Bundle ID changed | **NO** |
| Certificate/profile changed or revoked | **NO** |
| Entitlements changed | **NO** |
| Licence contents exposed | **NO** |
| Camera/discovery/Live View/shutter | **NONE** |
| Printer command | **NONE** |
| MockCameraService default | **YES** |
| `USE_NATIVE_CAMERA` | **false** |

**Stopped at the missing-wildcard-profile prerequisite.**
