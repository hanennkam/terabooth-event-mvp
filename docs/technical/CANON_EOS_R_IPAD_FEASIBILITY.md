# Canon EOS R → iPad Cable Feasibility

> **Status:** Phase 0 feasibility assessment — **G0 is NOT physically verified.** No iPad, Canon EOS R, Xcode, CocoaPods or Windows/DNP printer is attached to this environment.
> **Scope:** determine whether a custom Flutter iPad app can capture from a Canon EOS R over a **physical cable**, without moving camera control to Windows and without silently switching to Wi-Fi.
> **Date:** 2026-11-09.

---

## 1. Bottom line

| Path | Verdict | Confidence |
|---|---|---|
| **Canon EDSDK on iPad over USB** | **NO-GO** — Canon does not ship EDSDK for iOS/iPadOS | High |
| **Canon CCAPI over the physical cable** | **NO-GO / unsupported assumption** — CCAPI is a network API; it is not USB/PTP over cable | High |
| **CCAPI over Wi-Fi** | **Conditional alternative only** — iOS is supported by CCAPI, but EOS R CCAPI compatibility is unconfirmed and it violates the cable requirement | Medium/low |
| **iPadOS DriverKit custom PTP driver** | **Technically possible in principle, not feasible for this event** — requires a driver extension, entitlement and a Canon PTP implementation; months, not days | High |
| **ExternalAccessory / MFi** | **NO-GO** — requires an MFi-certified Canon accessory/protocol; no evidence EOS R provides one | High |
| **CascableCore (third-party SDK)** | **CONDITIONAL GO** — official third-party SDK; EOS R is listed as supported via USB on iPad; requires a commercial/evaluation licence, a native Swift/ObjC wrapper and physical testing | Medium |
| **Existing cable workflow** | **UNVERIFIED** — no source was recoverable; cannot confirm which SDK/plugin it used | Unknown |
| **iPad built-in camera fallback** | **Works, but not Canon** — quality/experience degradation; only an event fallback, not a solution to G0 | High |

**G0 verdict: NO-GO for a from-scratch Canon cable integration using Canon's official SDKs. CONDITIONAL GO only if CascableCore is licensed and a physical iPad + EOS R capture test passes before the event deadline.**

The gate remains **UNVERIFIED** in this environment. No camera test was performed.

---

## 2. Verified technical findings

### 2.1 Canon EDSDK is desktop-only

Canon's Camera API Package (CAP) contains EDSDK and CCAPI:

| SDK | Connection | Supported OS (per Canon) |
|---|---|---|
| **EDSDK** | USB wired | Windows 10/11 (32/64), macOS 13–15, Linux (ARM/x64) |
| **CCAPI** | Wi-Fi (wired LAN only on specific bodies) | OS-independent, including **iOS** and Android |

Source: [Canon CAP overview](https://asia.canon/en/campaign/developerresources/cap).

**Consequence:** EDSDK cannot be linked into an iPad app. It is not an iOS framework, and Canon does not list iOS as a supported OS. Any claim that a custom iPad app can use EDSDK over USB is false.

### 2.2 CCAPI is a network API, not a cable API

Canon describes CCAPI as an HTTP-based API for controlling cameras **over a network**. Its documented connection is Wi-Fi; the only wired-LAN exceptions are specific bodies (EOS-1D X Mark III, EOS R3) — not the EOS R, and not USB.

**Consequence:** CCAPI cannot be assumed to work over the USB-C cable. Using it would require Wi-Fi, which is explicitly not the requested cable workflow.

**EOS R CCAPI support is not confirmed** by Canon's public CAP material. Do not assume it.

### 2.3 iOS/iPadOS USB access is restricted

Apple provides two public routes for third-party USB device communication:

1. **ExternalAccessory** — for MFi-certified accessories. A camera must implement the MFi protocol; Canon EOS R is not documented as an MFi camera accessory.
2. **DriverKit for iPadOS** — Apple documents driver creation for iPadOS. This can, in principle, drive a USB device, but it requires a driver extension, Apple entitlements, and a full implementation of the device's protocol.

Sources: [External Accessory](https://developer.apple.com/documentation/externalaccessory) · [Creating drivers for iPadOS](https://developer.apple.com/documentation/driverkit/creating-drivers-for-ipados).

**Consequence:** a custom app cannot simply open a generic USB/PTP camera through Flutter or a normal iOS API. Writing a Canon PTP driver via DriverKit is a research project, not a five-day event task. It also would not reuse Canon's desktop SDK.

### 2.4 CascableCore is a verified third-party cable path

Cascable documents:

- **Canon EOS R** is supported by Cascable Studio, Pro Webcam and Transfer; **USB** and Wi-Fi are both marked compatible.
- USB support for EOS R requires **Cascable Studio 5.2 or later**.
- Supported features on EOS R include remote control/automation, tethered shooting, live view, video recording, photo review, storage access and RAW.
- CascableCore is an SDK for **iOS, iPadOS, macOS and visionOS**, supporting 250+ cameras via **Wi-Fi or USB**, with live view, shooting and file transfer APIs.
- A **30-day fully featured evaluation licence** is available; commercial distribution requires a licence from Cascable.

Sources: [EOS R compatibility](https://compatibility.cascable.se/canon/eos-r/) · [CascableCore developer portal](https://developer.cascable.se/) · [CascableCore API docs](https://cascable.github.io/) · [Wired camera guide](https://cascable.se/help/wired-cameras/).

**Consequence:** this is the only researched path that can plausibly satisfy “EOS R → physical cable → iPad → custom app” on a five-day horizon. It is a **third-party commercial dependency**, not a Canon official SDK, and it still requires a native iOS wrapper plus physical verification.

### 2.5 What CascableCore does not remove

- It is **Swift/Objective-C**, not Flutter. A Flutter app needs a platform channel plugin.
- It requires a **licence** (evaluation then commercial); terms must be obtained from Cascable.
- It requires **Xcode** and a working iOS build chain; neither is present on this Mac.
- It must be tested with the **actual EOS R, cable and iPad**; the compatibility page is vendor evidence, not a test of our app.
- It may require camera settings (Wi-Fi disabled, correct USB mode) and iOS permissions (Local Network, Files and Folders, Camera).

---

## 3. Connection-method matrix

| Method | Cable? | Official? | iPad custom app? | Event-feasible? | Notes |
|---|---|---|---|---|---|
| Canon EDSDK over USB | Yes | Canon official (desktop) | **No** | **No** | No iOS support |
| Canon CCAPI over USB | No (network) | Canon official | N/A | **No** | Not a cable API |
| Canon CCAPI over Wi-Fi | No | Canon official | Yes (HTTP) | Conditional | EOS R support unconfirmed; violates cable requirement; camera Wi-Fi/network conflict |
| iPadOS DriverKit custom PTP | Yes | Apple API | Technically | **No** | Driver extension + entitlement + Canon protocol; months |
| ExternalAccessory/MFi | Yes | Apple API | Only MFi accessory | **No** | No evidence EOS R is MFi |
| CascableCore | Yes (USB) | Third-party commercial | Yes, via native wrapper | **Conditional** | EOS R USB listed; licence + Xcode + hardware test |
| Existing app's cable workflow | Yes | Unknown | Unknown | **Unknown** | Source not recoverable; cannot verify |
| iPad built-in camera | No | Apple | Yes | Fallback | Not Canon; quality/experience degradation |

---

## 4. Implementation options

### Option A — CascableCore + Flutter platform channel (recommended conditional path)

**Shape:**

```
Flutter UI (Dart)
  └─ MethodChannel/EventChannel "terabooth/camera"
       └─ Swift plugin (iOS)
            └─ CascableCore (SPM/CocoaPods)
                 └─ USB-C → Canon EOS R
```

**Required:**
- CascableCore evaluation/commercial licence.
- Xcode + CocoaPods or SPM; a Mac capable of building iOS.
- iPad with USB-C, EOS R, data-capable USB-C cable.
- Camera Wi-Fi disabled; camera in the correct USB/PTP mode.
- iOS `NSLocalNetworkUsageDescription`; `NSAllowsLocalNetworking`; possibly `NSBonjourServices` if Cascable discovers via Bonjour.
- A native plugin exposing: connect, live view frames, capture, download original, disconnect/reconnect, error mapping.
- Physical test: 10 consecutive capture/download sessions.

**Time risk:** high for five days. The SDK handles the hard protocol work, but the Flutter wrapper, licensing, Xcode setup and hardware debugging are real work.

**Verdict:** **CONDITIONAL GO** — only if the licence and build chain are available immediately and a 30–60 minute hardware spike captures an image.

### Option B — CCAPI over Wi-Fi

- Official Canon HTTP API; iOS-capable.
- Not cable; violates the confirmed requirement.
- EOS R CCAPI support unconfirmed.
- If camera joins a router (infrastructure), iPad and Windows can share the LAN; if camera uses its own AP, the iPad cannot also join the guest/router Wi-Fi.

**Verdict:** **fallback only**, not a solution to G0.

### Option C — iPadOS DriverKit PTP driver

- Technically possible; Apple documents iPadOS drivers.
- Requires entitlement, driver extension, Canon PTP implementation, signing and App Store/TestFlight distribution.
- No Canon SDK reuse.

**Verdict:** **NO-GO for this event.** Do not attempt.

### Option D — ExternalAccessory/MFi

- Requires Canon MFi certification/protocol.
- No evidence EOS R exposes an MFi camera protocol.

**Verdict:** **NO-GO.**

### Option E — iPad built-in camera fallback

- Works today; no Canon.
- Quality and brand promise degraded.
- Acceptable only as an event fallback if G0 cannot be solved; must be disclosed to the client.

**Verdict:** **event fallback**, not G0.

### Option F — Existing cable workflow reuse

- If the previous app used CascableCore or another licensed SDK, reuse its integration.
- The source is not recoverable in this environment; cannot verify.

**Verdict:** **unknown** until the project/SDK is identified.

---

## 5. Compatibility confidence

| Claim | Confidence | Basis |
|---|---|---|
| EDSDK does not support iOS | **High** | Canon CAP OS list |
| CCAPI is network/Wi-Fi, not USB cable | **High** | Canon CAP description |
| EOS R is supported by Cascable via USB | **High (vendor claim)** | Cascable compatibility page |
| CascableCore can integrate into a custom iOS app | **High** | CascableCore docs/portal |
| Our Flutter app can complete the integration in five days | **Medium/low** | Native wrapper + licence + Xcode + hardware debugging |
| EOS R CCAPI support | **Unknown** | Not confirmed in public Canon material |
| Existing cable workflow can be replicated | **Unknown** | No source |
| Physical G0 passes | **Unverified** | No hardware |

---

## 6. Physical test requirements (must be executed, not simulated)

1. iPad with USB-C (M-series preferred), iPadOS current.
2. Canon EOS R with charged battery/AC adapter.
3. Data-capable USB-C cable (not charge-only); direct connection, no unpowered hub.
4. Camera Wi-Fi **disabled**; correct USB/PTP mode.
5. CascableCore evaluation licence installed in a minimal test app or the Flutter plugin.
6. Connect; confirm camera model/serial; start live view; capture; download original; verify file on iPad.
7. Repeat **10 consecutive sessions**; disconnect/reconnect 5 times; lock/unlock iPad; confirm no lost images.
8. Measure: connect time, live-view latency, capture-to-download time, reconnect time.
9. Record exact errors and camera settings.

**Pass criteria:** 10/10 captures, original file saved, live view usable, reconnect works, no app crash.

**If this test cannot be run, G0 stays UNVERIFIED and the event must not claim Canon cable capture.**

---

## 7. GO / NO-GO

### G0 — Canon EOS R → iPad cable

# NO-GO (current) — CONDITIONAL GO via CascableCore only

- **NO-GO** for Canon EDSDK on iPad: impossible.
- **NO-GO** for CCAPI over cable: it is a network API.
- **NO-GO** for a custom DriverKit PTP driver in five days.
- **CONDITIONAL GO** only if:
  1. A CascableCore licence/evaluation is obtained.
  2. Xcode + CocoaPods are installed and an iOS build is possible.
  3. An iPad + EOS R + cable are available.
  4. A native Flutter plugin captures/downloads an image in a 30–60 minute spike.
  5. The spike passes by **Tuesday 10 November 2026, 12:00**.

If the spike cannot pass, the event must use a fallback:
- **iPad built-in camera** (degraded, but working), or
- the **proven LumaBooth rig**, or
- reschedule the Canon requirement.

**Do not silently switch to Wi-Fi and call it done. Do not move camera control to Windows. Do not claim Canon compatibility without the physical test.**

---

## 8. Required SDKs, permissions and dependencies

### CascableCore path

| Item | Requirement |
|---|---|
| SDK | CascableCore (evaluation/commercial licence) |
| Distribution | Swift Package Manager (CascableCore distribution) or vendor-supported CocoaPods; follow vendor docs |
| Native language | Swift/Objective-C |
| Flutter bridge | MethodChannel/EventChannel plugin |
| Xcode | Full Xcode, not Command Line Tools |
| CocoaPods/SPM | CocoaPods or SPM; Flutter iOS plugins may require CocoaPods |
| iOS permissions | Local Network (`NSLocalNetworkUsageDescription`), Files and Folders if applicable, Camera if using device camera |
| ATS | `NSAllowsLocalNetworking` if local HTTP/Bonjour is used |
| Camera settings | Wi-Fi disabled; correct USB/PTP mode; auto-power-off disabled |
| Hardware | USB-C iPad, EOS R, data cable, power |

### No-go paths

- EDSDK: no iOS support; do not attempt.
- CCAPI over USB: unsupported; do not attempt.
- DriverKit PTP: not feasible for the event.
- MFi: no Canon MFi evidence.

---

## 9. Recommendation for the event

1. **Immediately** request a CascableCore evaluation licence and install Xcode/CocoaPods.
2. Build a **minimal native spike** (not the full app) that connects to EOS R via USB, captures one image and saves it.
3. If the spike passes by Tuesday noon, proceed with the Flutter wrapper and the event MVP.
4. If it fails or the licence/build chain is unavailable, **do not gamble on Canon cable capture**:
   - use the iPad built-in camera for the event (disclosed), or
   - use the proven LumaBooth rig, or
   - renegotiate the camera requirement.
5. Keep the rest of the system (Windows print bridge, 2×6 print, QR delivery, local storage) independent of the camera path so it can be built and tested in parallel.

---

## 10. Sources

- Canon CAP overview (EDSDK OS list; CCAPI Wi-Fi/iOS): <https://asia.canon/en/campaign/developerresources/cap>
- Canon EDSDK release note: <https://asia.canon/en/campaign/developerresources/camera/cap/edsdk-eos-digital-camera-sdk-release-note>
- Canon SDK terms: <https://asia.canon/en/campaign/developerresources/terms-conditions-for-digital-camera-software-development-kit-sdk>
- Cascable EOS R compatibility (USB/Wi-Fi, Studio 5.2+): <https://compatibility.cascable.se/canon/eos-r/>
- Cascable wired camera guide (iOS USB-C connection): <https://cascable.se/help/wired-cameras/>
- CascableCore developer portal (250+ cameras, iOS/iPadOS, USB/Wi-Fi, 30-day trial): <https://developer.cascable.se/>
- CascableCore API docs (live view, shutter, file streaming): <https://cascable.github.io/>
- CascableCore distribution/SPM: <https://github.com/cascable/cascablecore-distribution>
- Apple ExternalAccessory (MFi): <https://developer.apple.com/documentation/externalaccessory>
- Apple DriverKit for iPadOS: <https://developer.apple.com/documentation/driverkit/creating-drivers-for-ipados>
