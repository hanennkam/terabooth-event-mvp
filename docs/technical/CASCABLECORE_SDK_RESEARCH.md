# CascableCore SDK Research — Canon EOS R on iPadOS

> **TARGET CORRECTION (2026-11-12):** The actual camera is a **Canon EOS 60D**, not an EOS R. The EOS 60D is absent from Cascable's official Canon compatibility list and its direct model page returns 404. All EOS R-specific assumptions here are historical and must not be used as EOS 60D compatibility evidence. See `PHASE_3A_1_CASCABLE_SETUP.md`. **Update:** macOS CascableCore 18.0.2 physically discovered/connected to the EOS 60D and validated settings read, Live View, a shutter request and reconnect; see `PHASE_3A_1B_CANON_60D_MAC_SDK_VALIDATION.md`. iPadOS and image transfer remain unverified.

> **Phase 1B — documentation-only.**
> **No application source was modified. CascableCore was not added to the Xcode project. No licence was purchased.**
> **Physical EOS R compatibility has NOT been tested.**
> **Status:** prepared for evaluation-licence approval; integration is blocked on the licence and iPad/EOS R hardware.

---

## 1. Research access log

| Resource | Result | Notes |
|---|---|---|
| [Cascable Developer Portal](https://developer.cascable.se/) | **Accessible (HTTP 200)** | Confirms iOS/iPadOS/macOS/visionOS, 250+ cameras, Wi-Fi and USB, 30-day evaluation |
| [CascableCore Distribution](https://github.com/cascable/cascablecore-distribution) | **Accessible** | Official SPM distribution; README read |
| [`Package.swift`](https://raw.githubusercontent.com/cascable/cascablecore-distribution/main/Package.swift) | **Accessible** | Exact platforms/products read |
| [CascableCore Demo](https://github.com/cascable/cascablecore-demo) | **Accessible** | Official Swift/Obj-C demo; README and source read |
| [Getting Started With CascableCore](https://github.com/cascable/cascablecore-demo/blob/master/Getting%20Started%20With%20CascableCore.md) | **Accessible** | Official concepts/API quick-start read |
| [CascableCore API reference](https://cascable.github.io/) | **Accessible** | Generated API docs, last updated 2026-08-25 |
| [CascableCoreSwift](https://github.com/cascable/cascablecore-swift) | **Accessible** | Recommended Swift additions; README and Package.swift read |
| [EOS R compatibility](https://compatibility.cascable.se/canon/eos-r/) | **Accessible** | Official vendor compatibility table |
| [Cascable wired-camera guide](https://cascable.se/help/wired-cameras/) | **Accessible** | Official iPad USB guidance |
| Evaluation licence / account | **Not accessed** | Requires sign-up/request; no credentials supplied; not purchased |
| CascableCore framework/headers | **Not downloaded** | No licence; no local SDK to compile against |

**Limitation:** without the evaluation licence and SDK binaries, the exact Swift overloads and the real EOS R behaviour cannot be compiled or physically verified. Everything below is grounded in official public docs/source; anything inferred is marked.

---

## 2. SDK distribution and build facts — confirmed

### 2.1 SPM package URLs and products

| Package | URL | Products / modules | Notes |
|---|---|---|---|
| CascableCore distribution | `https://github.com/cascable/cascablecore-distribution` | `CascableCore` (targets `CascableCore`, `StopKit`) | Core ObjC/Swift-compatible SDK |
| CascableCoreSwift | `https://github.com/cascable/cascablecore-swift` | `CascableCoreSwift` | Swift additions; depends on `cascablecore-distribution` from `18.0.2` |

Official guidance: if using Swift, add **CascableCoreSwift**; it brings CascableCore in as a dependency. The demo imports both `CascableCore` and `CascableCoreSwift`. For this project, the intended baseline is:

- Add `https://github.com/cascable/cascablecore-swift` via **File → Add Package Dependencies**.
- Add the `CascableCoreSwift` product to the Runner target.
- Import both `CascableCore` and `CascableCoreSwift`.
- If Xcode does not expose the transitive module, add the distribution package/product explicitly.

### 2.2 Minimum platforms

`cascablecore-distribution/Package.swift` declares:

```swift
platforms: [.macOS(.v11), .iOS(.v14), .macCatalyst(.v15), .visionOS("1.1")]
```

`cascablecore-swift/Package.swift` declares the same and `.iOS(.v14)`.

**Consequence:** the Terabooth iPad app is currently configured with `IPHONEOS_DEPLOYMENT_TARGET = 13.0`. CascableCore requires **iOS/iPadOS 14.0 minimum**; the deployment target must be raised to 14.0 before adding the SDK. This is a documented technical reason for a project-setting change, not a UI/architecture change.

### 2.3 Toolchain

- Swift tools version: **5.9**.
- Official demo says **Xcode 15.0 or later**; current environment is **Xcode 26.6**, which is compatible.
- No CocoaPods dependency is required for CascableCore; it is distributed via SPM.

### 2.4 What SPM adds to the app

The package is a binary XCFramework distribution (`CascableCore.xcframework`, `StopKit.xcframework`). It is embedded/linked by Xcode. Do not copy frameworks manually; use SPM as documented.

**Unverified:** exact resolved version, binary size, bitcode/signing behaviour under Xcode 26.6, and whether the evaluation build requires any additional build settings. These require the actual SDK.

---

## 3. Licence facts and installation

### 3.1 Evaluation

Official developer portal and demo README:

- **30-day fully featured evaluation licence**.
- Request via account sign-up on the developer portal.
- Demo: replace the placeholder `CascableCoreLicense.h`, `.m`, or `.swift` files with the supplied licence, then the project compiles.
- Commercial use requires a licence; the evaluation is not a substitute for event/production rights.

**Status: BLOCKED.** No account/licence was available. Do not purchase without approval.

### 3.2 Applying the licence

Official API:

```swift
// CascableCore
class CascableCoreLicenseVerification {
    class func apply(license licenseData: Data) -> LicenseVerificationResult
}
```

Result cases (confirmed):

- `.success`
- `.expired`
- `.invalidLicense`

It **must be called before any other CascableCore API**. If it does not return `.success`, fail closed: do not start discovery or show a camera as usable.

`CascableCoreSwift` also documents key-based activation:

```swift
let validatedToken = try await CascableCoreLicenseVerification.apply(
    "1234",
    offlineToken: existingToken
)
```

Key activation contacts the licensing service on first use and stores an offline token; licence files are applied locally. **For the no-internet event, do not rely on first-time key activation at the venue.** Install/activate the licence during setup and verify it works offline before 14 November. Exact evaluation-licence delivery format must be confirmed with Cascable.

### 3.3 Secret handling

- Do **not** commit the licence bytes/key.
- Do **not** put licence data in this repository or docs.
- Add a non-committed licence source file to the Runner target, or inject the approved licence at build time.
- Do not log the licence.

---

## 4. Required permissions and capabilities

Official CascableCore distribution README:

| Requirement | Needed for | Current Terabooth status |
|---|---|---|
| `NSAppTransportSecurity` → `NSAllowsLocalNetworking = YES` | local camera/network communication | **Present** |
| `NSLocalNetworkUsageDescription` | local-network permission prompt | **Present** |
| `NSBonjourServices` → `_ptp._tcp` | Canon EOS “EOS Utility”/PTP Bonjour discovery | **Present** |
| `NSCameraUsageDescription` | USB camera access prompt (demo uses this) | **Present** |
| `com.apple.developer.networking.multicast` | SSDP discovery (Canon “Smartphone” Wi-Fi mode, some Sony/Panasonic) | **Not present / not needed for USB-only** |

The multicast entitlement requires manual Apple approval. It is **not required for the agreed USB cable topology**; do not apply for it just for this event. Do not add macOS sandbox entitlements from the demo to the iOS target.

Runtime permissions (official wired guide):

- iOS/iPadOS **Settings → Privacy → Files and Folders** must allow the app.
- The app’s own Settings → **Camera** must be enabled.
- The wired-camera API also exposes an authorization step:
  - `platformSupportsWiredCameras`
  - `hasAuthorizationToDiscoverWiredCameras`
  - `attemptToObtainWiredCameraAuthorization() async -> Bool`

These are runtime checks, not Info.plist keys. The integration must call the authorization method before discovery and surface a clear error if denied.

---

## 5. Canon EOS R compatibility evidence

### 5.1 Confirmed by Cascable’s official compatibility page

Canon EOS R is listed as supported by **Cascable Studio**, **Cascable Pro Webcam**, and **Cascable Transfer**:

- **Wi-Fi:** supported.
- **USB:** supported.
- **USB support requires Cascable Studio 5.2 or higher**.
- Listed features (general table):
  - Remote control & automation
  - Tethered shooting
  - **Live view**
  - Video recording
  - Photo review
  - **Storage access**
  - RAW images

The page explicitly warns that the table is a general overview and exact behaviour varies by camera.

### 5.2 Official wired setup facts

- On iPad with USB-C, connect the camera **directly with a USB-C cable** if the camera has USB-C, or via a USB-C→USB-A adapter and the camera cable.
- Canon cameras may disable USB when **Wi-Fi is enabled**; disable Wi-Fi if the camera is not detected.
- EOS R predates Canon’s “Choose USB connection app” setting (introduced from EOS R6 Mark II); most Canon bodies have no USB mode setting and use PTP/MTP, which is correct for Cascable.
- USB is **not supported in the iOS Simulator**; physical iPad required.
- Use a data-capable cable, not a charge-only cable.

### 5.3 What is confirmed vs not confirmed

| Claim | Evidence | Confidence |
|---|---|---|
| EOS R supports USB in Cascable apps | Official compatibility page | **Confirmed (vendor docs)** |
| EOS R live view/remote/storage supported | Official compatibility page | **Confirmed (vendor docs)** |
| CascableCore exposes discovery/connect/live view/shutter/transfer APIs | Official API docs/demo | **Confirmed** |
| EOS R will work with *this* app on *this* iPad | No physical test | **UNVERIFIED** |
| File sizes/timing/transfer strategy on EOS R | No physical test | **UNVERIFIED** |
| EOS R JPEG original available via camera-initiated transfer | Not documented specifically | **UNVERIFIED** |
| 2×6 source images meet 300 dpi after crop | Depends on capture/transfer | **UNVERIFIED** |

**No physical EOS R compatibility claim is made.**

---

## 6. Confirmed API inventory

All names below are from official API docs/demo. Objective-C selectors are shown where the docs are primarily ObjC; Swift declarations are shown where explicitly documented.

### 6.1 Discovery

```swift
// Swift names from API docs / demo
CameraDiscovery.shared
discovery.discoveryMode = .usbOnly
discovery.platformSupportsWiredCameras          // Bool
discovery.hasAuthorizationToDiscoverWiredCameras // Bool
await discovery.attemptToObtainWiredCameraAuthorization() // Bool
discovery.clientName = "Terabooth"
discovery.delegate = self
discovery.beginSearching()
discovery.stopSearching()
```

Delegate:

```swift
func discovery(_ discovery: CameraDiscovery, didDiscover camera: any CBLCamera)
func discovery(_ discovery: CameraDiscovery, didLoseSightOf camera: any CBLCamera)
```

`CameraDiscoveryMode`: `.networkOnly`, `.usbOnly`, `.networkAndUSB`.

### 6.2 Connection / lifecycle

```swift
camera.connect(
  authenticationRequestCallback: { context in ... },
  authenticationResolvedCallback: { ... },
  completionCallback: { error, warnings in ... }
)
```

Other confirmed members:

- `connectionState` → `.notConnected`, `.connectionInProgress`, `.connected`, `.disconnectionInProgress`
- `connected: Bool`
- `disconnectionWasExpected: Bool`
- `cameraTransport` → `.network` / `.USB`
- `friendlyIdentifier`, `friendlyDisplayName`, `deviceInfo`, `service`
- `connectionWarnings`
- `disconnect(_:callbackQueue:)`
- `supportedFunctionality`, `supportsFunctionality(_:)`
- `currentCommandCategories`, `setCurrentCommandCategories(_:completionCallback:)`
- `storageDevices`

`AvailableCommandCategory`: `.stillsShooting`, `.filesystemAccess`, `.videoRecording`.

### 6.3 Live view

```swift
camera.beginStream(
  delivery: { frame, completionHandler in
      // frame.image; call completionHandler() when ready for next frame
  },
  deliveryQueue: .main,
  terminationHandler: { reason, error in ... }
)
camera.endStream()
camera.liveViewStreamActive
```

Or the recommended Swift Combine path:

```swift
camera.liveViewPublisher(options: [...])
  .receive(on: .main)
  .sinkWithReadyHandler { terminationReason in ... }
  receiveValue: { frame, readyForNextFrame in
      // render frame
      readyForNextFrame()
  }
```

Termination reasons: `.endedNormally`, `.alreadyStreaming`, `.failed`.

Documented caveat: live view start/stop is a heavy, multi-second operation; frames can arrive faster than the UI can consume; the delivery completion handler **must** be called for the next frame.

### 6.4 Shutter

```swift
camera.invokeOneShotShutterExplicitlyEngagingAutoFocus(
  true,
  completionCallback: { error in ... }
)
```

Fine-grained alternative: `engageAutoFocus`, `engageShutter`, `disengageShutter`, `disengageAutoFocus`.

**Critical official caveat:** the completion callback only indicates whether the request was sent without error. It does **not** indicate whether the shutter actually fired. A successful callback is not proof of a captured image.

### 6.5 Camera-initiated transfer

```swift
let token = camera.addCameraInitiatedTransferHandler { request in
    guard request.isValid else { return }
    guard request.canProvide(.original) else { ... }
    request.executeTransfer(for: .original, completionQueue: .main) { result, error in
        // result.write(.original, to: url) / generateData
    }
}
camera.removeCameraInitiatedTransferHandler(with: token)
```

Confirmed request members:

- `isValid` (requests time out)
- `isOnlyDestinationForImage` (true means failing to transfer can lose the image)
- `executionRequiredToClearBuffer`
- `availableRepresentations` / `canProvide(_:)`
- `fileNameHint`, `dateProduced`
- `executeTransfer(for:completionQueue:)` (and async variant)

Confirmed result members:

- `availableRepresentations`, `contains(_:)`
- `isOnlyDestinationForImage`
- `write(_:to:)` / `generateData(for:)`
- `generatePreviewImage()`
- `suggestedFileNameExtension(for:)`

### 6.6 Filesystem / original transfer

```swift
camera.setCurrentCommandCategories(.filesystemAccess) { error in ... }

let storage = camera.storageDevices?.first
let root = storage?.rootDirectory
root?.loadChildren { error in ... }

item.streamItem(
  preflightBlock: { item in ... return context },
  chunkDeliveryBlock: { item, chunk, context in ... return .continue },
  complete: { item, error, context in ... }
)
```

Confirmed:

- `CBLFileStorage`: `rootDirectory`, `addFileSystemObserver`, `removeFileSystemObserver`.
- `CBLFileSystemItem`: `loadChildren`, `name`, `size`, `metadataLoaded`, `streamItem(...)`.
- The camera must be in `.filesystemAccess` to access storage.
- Directory structure must not be assumed; metadata may not be loaded immediately.
- File streaming is chunked; callbacks default to the main queue; completion must handle errors/cancellation.

**Important:** switching to `.filesystemAccess` may stop live view. This is a documented command-category behaviour; the exact EOS R transition timing is unverified.

### 6.7 Licence

```swift
CascableCoreLicenseVerification.apply(license: Data) -> LicenseVerificationResult
```

Result: `.success`, `.expired`, `.invalidLicense`.

---

## 7. SDK limitations relevant to Terabooth

1. **iOS 14 minimum** — current project targets 13.0.
2. **No USB in iOS Simulator** — physical iPad required for camera tests.
3. **Capture callback is not proof of shutter** — need transfer/file evidence and timeouts.
4. **Camera-initiated transfer can time out** — must handle immediately; `isOnlyDestinationForImage` can mean data loss if ignored.
5. **No generic guarantee of original via camera-initiated transfer** — filesystem fallback may be required; exact EOS R behaviour unverified.
6. **Command-category switch can stop live view** — design the session to capture/transfer without assuming continuous preview.
7. **All CascableCore calls must be on the main thread**; callbacks are main-thread unless a queue is specified.
8. **Live view is expensive** — start/stop multi-second; frame pacing required.
9. **License must be applied before any SDK API**, and fail closed.
10. **Network permission is still relevant** even for USB, because CascableCore may use local networking internally and the SDK docs require the keys.
11. **Multicast entitlement is for SSDP/Wi-Fi discovery**, not the USB-only topology; do not add unnecessarily.

---

## 8. Existing implementation audit

| File | Current state |
|---|---|
| `lib/services/native_camera_service.dart` | MethodChannel client; methods `connect`, `capture`, `status`; expects base64 bytes; no events/status stream |
| `ios/Runner/AppDelegate.swift` | Registers `CameraPlugin`; compile-safe stub returns `CAMERA_SDK_MISSING` |
| `ios/Runner/Cascable/CascableCameraAdapter.swift` | Reference only, `#if canImport(CascableCore)`, not in Xcode target |
| `lib/services/camera_service.dart` | `CameraService` interface; `MockCameraService` remains default; `CascableCameraService` placeholder |
| `lib/booth_controller.dart` | 3-photo countdown; calls `connect()` once at session start; no disconnect/reconnect; no live view; errors set `phase = error` |
| `ios/Runner/Info.plist` | ATS local, Local Network description, `_ptp._tcp`, camera description present |
| Xcode target | Deployment target 13.0; no CascableCore package |

**Gaps to address after licence:** iOS 14 target, SPM package, licence, adapter target membership, event channel, connection state, capture correlation, transfer/file evidence, reconnect/background handling.

---

## 9. Open questions requiring Cascable confirmation

1. Exact evaluation-licence delivery format and installation procedure for SPM-based apps (license file vs key; offline validity).
2. Whether the evaluation licence permits a one-time paid event; commercial terms and event date.
3. Whether EOS R camera-initiated transfer provides **original** JPEG or only preview; recommended original-download path for EOS R.
4. Whether switching to `.filesystemAccess` on EOS R reliably stops/restarts live view and expected timing.
5. Whether `NSCameraUsageDescription` plus Files and Folders is sufficient for USB on current iPadOS, or another authorization is required.
6. Exact behavior of EOS R when Wi-Fi is enabled/USB mode; recommended camera settings.
7. Whether `CascableCoreSwift`'s `liveViewPublisher` is suitable for a 3-photo countdown UI, or whether the plain `beginStream` API is safer for MVP.
8. Minimum/recommended SDK version for EOS R USB on iPadOS 26.x.

---

## 10. Official references

- Developer portal: <https://developer.cascable.se/>
- Distribution: <https://github.com/cascable/cascablecore-distribution>
- Distribution Package.swift: <https://github.com/cascable/cascablecore-distribution/blob/main/Package.swift>
- CascableCoreSwift: <https://github.com/cascable/cascablecore-swift>
- Demo: <https://github.com/cascable/cascablecore-demo>
- Getting Started: <https://github.com/cascable/cascablecore-demo/blob/master/Getting%20Started%20With%20CascableCore.md>
- API reference: <https://cascable.github.io/>
- EOS R compatibility: <https://compatibility.cascable.se/canon/eos-r/>
- Wired guide: <https://cascable.se/help/wired-cameras/>

**No purchase, no SDK installation, no source modification, no physical test.**
