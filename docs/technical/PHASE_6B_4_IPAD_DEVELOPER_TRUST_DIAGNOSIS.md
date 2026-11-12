# Phase 6B-4 — iPad Developer Trust Diagnosis (Read-only)

## Overall result

**CONFIRMED: the prior launch rejection was a developer-profile trust failure.**
**CURRENT STATE: no apps are installed on the iPad, so no installed app/profile
can be inspected now and no Developer App entry is expected.**

No reinstall, deletion, signing, provisioning, entitlement, account or device
setting change was made. No camera or printer command was executed.

---

## 1. Read-only evidence

Commands used:

```bash
xcrun devicectl list devices
xcrun devicectl device info details --device <iPad>
xcrun devicectl device info apps --device <iPad> --json-output /tmp/6b4-readonly/apps.json
xcrun devicectl device info authListing --device <iPad> --json-output /tmp/6b4-readonly/auth.json
security find-identity -p codesigning -v
security cms -D -i ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/<uuid>.mobileprovision
```

No secrets or private keys were printed.

### Device state

| Property | Evidence |
|---|---|
| Device | iPad (A16), iPad15,7 |
| OS | iPadOS 26.6, build 23G71 |
| Developer Mode | **enabled** |
| Pairing | paired |
| Transport | wired USB tunnel connected |
| Boot state | booted |
| Installed apps from `devicectl` | **none** |

The `devicectl device info apps` result was:

```text
Apps installed:
```

with an empty app list.

This conflicts with the premise that the probe app is currently installed. The
probe was uninstalled at the end of Phase 6B-3; no reinstall was performed in
this read-only phase.

---

## 2. Retained provisioning profile

The generated profile remains locally at:

```text
~/Library/Developer/Xcode/UserData/Provisioning Profiles/
  bd3db3a4-1d92-463d-83ae-27cb45a39f85.mobileprovision
```

| Property | Value |
|---|---|
| Name | `iOS Team Provisioning Profile: com.terabooth.personalsigningprobe6b3` |
| UUID | `bd3db3a4-1d92-463d-83ae-27cb45a39f85` |
| App ID name | `XC com terabooth personalsigningprobe6b3` |
| Application identifier | `P2LJT7F45Y.com.terabooth.personalsigningprobe6b3` |
| Team identifier | `P2LJT7F45Y` |
| Wildcard | **No — explicit App ID** |
| `get-task-allow` | **true** |
| Created | 2026-11-12 12:20:16 UTC |
| Expires | 2026-11-19 12:20:16 UTC |
| Provisioned device | `00008120-0016705822220032` (connected iPad) |
| Developer certificates | 1 |
| Certificate SHA-256 | `01faa0ea69687487d234fcac6693d870c6563c2695a6708861a98c4eafd51074` |
| Current local identity hash | **same certificate hash** |
| Xcode managed | true |

Entitlements are the normal development set: `application-identifier`,
team identifier, `get-task-allow`, and keychain access group. No app-specific
capability entitlements are present.

No wildcard was used.

---

## 3. Prior launch rejection

Phase 6B-3 installation succeeded; launch was rejected by iPadOS:

```text
Unable to launch com.terabooth.personalsigningprobe6b3 because it has an
invalid code signature, inadequate entitlements or its profile has not been
explicitly trusted by the user.
```

`FBSOpenApplicationServiceErrorDomain` code 3, reason `Security`.

This is the normal iOS development-profile trust gate. It is not evidence of a
profile/certificate mismatch: the retained profile matches the explicit App ID,
the current certificate, the connected iPad, and has `get-task-allow=true`.

---

## 4. Findings by category

| Possible cause | Finding |
|---|---|
| Provisioning mismatch | **Not supported.** Profile App ID, team, certificate and device all match. |
| Certificate/keychain mismatch | **Not supported.** Profile certificate hash matches the current identity. |
| Device UDID missing | **No.** Connected iPad is included. |
| Expired profile | **No.** Valid for 7 days from 2026-11-12. |
| Developer Mode disabled | **No.** `developerModeStatus: enabled`. |
| MDM/supervision restriction | **No MDM profile/management evidence.** User reports no Device Management and no supervised indicator. |
| `allowEnterpriseAppTrust` | **Not applicable on current evidence.** This is a management/enterprise-trust restriction; there is no MDM/supervision profile to carry it. It is not a normal Personal Team development-profile setting. |
| Apple verification/network | **Not established.** USB pairing/tunnel works; device internet reachability to Apple services was not tested read-only. No credentials or tokens were used. |
| Trust UI registration | **Most likely.** The profile was never explicitly trusted after install. |
| Current missing Developer App entry | **Explained by no current installed app.** `devicectl` reports zero apps. |

---

## 5. Root cause

**Confirmed historical cause:** the app installed and code-signed correctly, but
its explicit Personal Team development profile had not been trusted by the user,
so iPadOS refused first launch.

**Current-state cause of the missing Developer App entry:** there is currently no
probe app installed on the device. A Developer App trust entry cannot exist for
an uninstalled app.

The evidence does **not** support a provisioning mismatch, certificate problem,
expired profile, device registration problem, or confirmed iPadOS management
restriction.

`allowEnterpriseAppTrust` should not be changed as a workaround. It is not
implicated by any current evidence.

---

## 6. Network verification limitation

I did not have a read-only, credential-free way to execute a network check from
inside iPadOS. The Mac-to-iPad USB developer tunnel is connected, but that is not
proof that the iPad can reach Apple developer verification endpoints.

This does not currently appear to be the failure cause: the rejection occurred
at local code-signature/profile trust evaluation, and the profile itself is
internally valid. A network check would only become relevant if a correctly
trusted app still failed with a certificate/verification error.

---

## 7. Minimum safe next step

Do not change Bundle IDs, certificates, profiles, entitlements or iPad settings
to work around this. The minimum safe diagnostic sequence is:

1. With explicit operator approval, reinstall **the same** signed probe app.
2. Launch it once from the iPad Home Screen (not only through `devicectl`) so the
   normal "Untrusted Developer" trust prompt can appear.
3. Open **Settings → General → VPN & Device Management → Developer App**, select
   the Apple Development identity, and tap **Trust**.
4. Launch the app again. Report whether the trust entry appears and whether
   launch succeeds.
5. If the entry is still absent after installation and a launch attempt, stop
   reinstalling. Collect an iPad sysdiagnose and inspect the device logs for
   `amfid`/`installd`/`Security`/`Trust`, and verify whether Screen Time
   restrictions are blocking trust UI.

No reinstall or trust change was performed in this phase.

---

## 8. Safety confirmation

| Check | Result |
|---|---|
| Reinstall/delete app | **NO** |
| Bundle ID/signing/provisioning change | **NO** |
| Certificate change | **NO** |
| Entitlements change | **NO** |
| Account/MDM/device settings change | **NO** |
| Camera/shutter command | **NONE** |
| Printer command | **NONE** |
| License/private key/token exposed | **NO** |
| MockCameraService default | **YES** |
| `USE_NATIVE_CAMERA` default | **FALSE** |

**Stopped after read-only diagnosis.**
