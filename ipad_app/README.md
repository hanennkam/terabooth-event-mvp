# Terabooth iPad App

Flutter iPad UI for the 14 November event MVP.

## Current state

- **Mock camera only.** The welcome screen shows `SIMULATED CAMERA — no Canon EOS R capture`.
- Real Canon EOS R over USB is **not implemented**. It requires CascableCore, Xcode/CocoaPods and a physical iPad + EOS R; see `../docs/technical/CANON_EOS_R_IPAD_FEASIBILITY.md`.
- The `CascableCameraService` placeholder deliberately throws instead of faking a capture.

## Run tests

```bash
flutter analyze
flutter test
```

## Build for iPad (after environment fix)

Prerequisites:

1. Full Xcode installed (not Command Line Tools) and selected:
   `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`
2. CocoaPods installed (`sudo gem install cocoapods` or Homebrew).
3. An iPad connected/trusted, or a simulator.
4. `flutter doctor -v` shows Xcode and CocoaPods healthy.

Then:

```bash
flutter pub get
flutter build ios --no-codesign   # compile check
flutter run -d <device-id>
```

The current Mac has **no full Xcode and no CocoaPods**, so the iOS build cannot be produced here.

## Configuration

- Welcome screen: enter the Windows bridge URL, e.g. `http://192.168.8.50:8787`.
- The iPad and Windows must be on the same LAN/router; no internet is required.
- `Info.plist` includes `NSLocalNetworkUsageDescription` and `NSAllowsLocalNetworking` for the LAN bridge.
- The app writes originals to its documents directory:
  `events/<event_id>/sessions/<session_id>/original_<n>.jpg`.

## Flow

Welcome → Start → 3-photo countdown → Review/Retake → Approve & Print → status + QR → Next guest.

Print status is honest: `202` is “sending”, not “printed”. `completed`/`assumed`/`unknown` are displayed distinctly.
