# Phase 6B-5 — Personal Team Developer Trust & First iPad Launch

## Overall result

**PASS — operator trust and first launch confirmed on the physical iPad.**

The disposable Personal Team probe was rebuilt with the same explicit Bundle ID,
installed, manually trusted by the operator, and launched successfully.

No Terabooth source, target, Bundle ID, certificate, entitlement, Cascable
configuration or licence was changed. No camera or printer command was run.

---

## 1. Build, signing and installation

| Step | Result | Evidence |
|---|---|---|
| Artifact existed | No | Previous `/tmp` artifact was deleted; recreated disposable app |
| Build | **PASS** | `** BUILD SUCCEEDED **` |
| Bundle ID | `com.terabooth.personalsigningprobe6b3` | Info.plist |
| Code signature | **PASS** | `codesign --verify --deep --strict` valid |
| Signing identity | Apple Development, team `P2LJT7F45Y` | `codesign -dvv` |
| Provisioning profile | `bd3db3a4-1d92-463d-83ae-27cb45a39f85` | embedded profile |
| Profile type | **Explicit App ID** | `P2LJT7F45Y.com.terabooth.personalsigningprobe6b3` |
| Profile expiration | 2026-11-19 12:20:16 UTC | profile |
| Device UDID in profile | `00008120-0016705822220032` | profile |
| `get-task-allow` | true | profile/entitlements |
| New profile generated | **No** — existing UUID reused | Xcode log |
| Installation | **PASS** | `devicectl` `App installed` |

Installed path:

```text
/private/var/containers/Bundle/Application/D4CE907B-E056-455A-80C4-FD6D4CECBCC0/Runner.app
```

The app is named **Personal Signing Probe 6b5** on the iPad.

---

## 2. Manual trust — operator-confirmed

The operator reported:

| Question | Operator answer |
|---|---|
| Untrusted Developer dialog appeared | **Yes** |
| Developer App entry appeared under Settings → General → VPN & Device Management | **Yes** |
| Trust action succeeded | **Yes** |

These are **operator-confirmed physical actions**, not automated checks.

No device management, Screen Time or supervision settings were changed. The
operator only trusted the Personal Team development identity as required.

---

## 3. Launch — automated confirmation

After the operator confirmed trust:

```text
Launched application with com.terabooth.personalsigningprobe6b3 bundle identifier.
```

`devicectl` returned:

```text
processIdentifier: 814
executable:
file:///private/var/containers/Bundle/Application/
  D4CE907B-E056-455A-80C4-FD6D4CECBCC0/Runner.app/Runner
```

A subsequent `devicectl device info processes` query confirmed PID 814 is still
running with the probe executable.

| Result | Status |
|---|---|
| Launch request | **PASS** |
| Process running | **PASS — PID 814** |
| App left installed | **YES** |
| Developer App trusted | **Operator-confirmed YES** |

---

## 4. What this proves

- A Personal Team can explicitly provision, sign, install, trust and launch a new
  app on this iPad.
- The earlier launch failure was the missing manual trust step, not a certificate,
  provisioning or device-registration defect.
- The explicit profile and current certificate are valid for the connected iPad.
- `allowEnterpriseAppTrust` was not needed or implicated.

### What this does not prove

- Wildcard App ID support. The profile is **explicit**, not wildcard.
- That the Cascable demo Bundle ID `se.cascable.CascableCoreiOSDemo` can be
  provisioned, trusted or launched.
- That Terabooth's native camera path works on the physical iPad.

The demo-vendor-ID/wildcard blocker remains a separate issue.

---

## 5. Safety and cleanup

- Terabooth project/source: **unchanged**
- `Runner-CascableDemo`: **unchanged**
- Certificates/profiles: **not revoked, replaced or deleted**
- New profile: **none**
- Camera/shutter: **none**
- Printer: **none**
- License contents: **not accessed/exposed**
- MockCameraService default: **unchanged**
- `USE_NATIVE_CAMERA`: **disabled by default**

The disposable probe remains installed and running for operator inspection. It
can be uninstalled separately when no longer needed; this report does not remove
it without instruction.

**Stopped after confirmed first launch.**
