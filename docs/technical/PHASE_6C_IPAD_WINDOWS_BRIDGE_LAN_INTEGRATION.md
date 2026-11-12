# Phase 6C — iPad ↔ Windows Bridge LAN Integration

## Overall result

**PASS for physical authenticated iPad→Windows Bridge health.**
**Upload/retrieval is NOT TESTED.**

The production Terabooth Release app on the physical iPad now authenticates to
the Windows Bridge over the shared Wi-Fi and reports **Bridge connected**.

No camera, shutter, capture, printer, DNP or Windows Bridge configuration change
was performed.

---

## 1. Architecture audit

```text
iPad Release app
  → BridgeClient
      → GET /v1/health (Bearer token)
      → POST /v1/print-jobs (multipart, approved JPEGs)
      → status / artefact / GIF / delivery endpoints
  → Windows Bridge (FastAPI/Uvicorn, 0.0.0.0:8787)
      → SQLite, delivery, QR, GIF/ZIP, print queue
```

| Item | Finding |
|---|---|
| Bridge URL | Configurable in Settings and persisted |
| Compiled default | Was stale `http://192.168.8.50:8787` |
| Actual Windows LAN IP | `192.168.8.192` |
| API token | Previously build-time only; no runtime replacement/clear |
| Authentication | `Authorization: Bearer <token>`; health 401 without it |
| Timeouts/errors | Existing `BridgeException` mapping preserved |
| Local Network | `NSLocalNetworkUsageDescription` already present |
| ATS | `NSAllowsLocalNetworking` already present |
| Camera | `MockCameraService` default; `USE_NATIVE_CAMERA=false` |
| Printer | `MockPrinter` default on Windows |

### Gap found

The installed app had no Bridge token compiled in and no way to enter one on the
iPad. The default URL was also stale. The Bridge token is now a masked runtime
setting stored in iOS Keychain; the URL remains separately configurable.

---

## 2. Windows connectivity

Operator-confirmed:

- Windows IPv4 remains **192.168.8.192**.
- iPad and Windows laptop are on the same Wi-Fi.
- Bridge port **8787**.
- API token found in the Windows bridge `.env`.

Independent checks from the Mac:

```text
TCP 192.168.8.192:8787        succeeded
GET /v1/health                HTTP 401 {"detail":"unauthorized"}
GET /                         HTTP 404 {"detail":"Not Found"}
```

From iPad Safari, the exact health URL returned:

```json
{"detail":"unauthorized"}
```

This confirms iPad network reachability and Bridge authentication enforcement.
The app then authenticated successfully.

---

## 3. Changes

### Secure runtime token

Added `lib/services/bridge_token_store.dart`:

- `BridgeTokenStore` abstraction.
- `KeychainBridgeTokenStore` using `flutter_secure_storage`.
- iOS Keychain accessibility `first_unlock_this_device`.
- Token key is not written to app documents, diagnostics or logs.

### Controller

`BoothController` now:

- loads URL and Keychain token separately;
- preserves the token when the URL changes;
- updates the token without changing the URL;
- clears the token explicitly;
- creates a new `BridgeClient` with the stored token.

### Settings UI

Added a masked **Bridge API token** field with:

- show/hide toggle;
- Save updates URL and token;
- stored-token indication without displaying the value;
- **Clear stored token** action;
- diagnostics show only `Configured securely` / `Not configured`.

No token is included in error text, snackbars or diagnostics.

### URL

The compiled default and Settings hint now use the verified
`http://192.168.8.192:8787`, while remaining operator-editable.

### Dependency

Added `flutter_secure_storage: ^11.2.0` for Keychain storage. No other dependency
was added.

---

## 4. Build and tests

```text
Flutter analyze: No issues
Flutter tests: 144 passed
Windows Bridge tests: 61 passed
```

New tests:

- Keychain token loads with stored URL.
- Token save/update does not change URL.
- Token clear removes Keychain value and in-memory token.
- URL save preserves the existing token.

### Release build

```text
xcodebuild -scheme Runner -configuration Release
BUILD SUCCEEDED
Bundle: com.terabooth.teraboothIpad
Team: P2LJT7F45Y
Profile: 0a12cb09-dbbd-4c11-856d-3b44a94b80c3
Expiry: 2026-11-19
Demo licence: absent
```

Installed over the existing app without uninstalling the production app or the
disposable probe.

---

## 5. Physical iPad result

| Check | Status | Evidence |
|---|---|---|
| App launch | **PASS** | Release app open |
| Settings fields | **PASS** | URL + masked token visible |
| Local Network permission | **PASS** | Operator: Terabooth ON |
| iPad Safari health reachability | **PASS** | 401 unauthorized |
| Authenticated app health | **PASS** | Operator: **Bridge connected** |
| URL | **PASS** | `http://192.168.8.192:8787` |
| Token at rest | **PASS** | Not present in `Documents/settings.json`; stored in Keychain |
| Authentication failure | **PASS** | Unauthenticated health returns 401 |

`Documents/settings.json` contains only:

```json
{"selected_event_id":"...","bridge_url":"http://192.168.8.192:8787"}
```

No token key is present.

---

## 6. NOT tested

- Photo upload / print-job submission from iPad
- Server-side receipt of a test asset
- Guest delivery/QR/GIF/ZIP retrieval from this iPad
- Printer or DNP commands
- Camera discovery/Live View/shutter/capture
- Token persistence across app reinstall/device reboot
- Auth failure UI after a deliberately wrong token

No physical print or camera action was performed.

---

## 7. Remaining blockers / risks

- End-to-end photo upload/retrieval is not yet verified from this iPad.
- The app still requires manual token entry on first use; Keychain persists it
  thereafter.
- The default LAN URL is a convenience only; operators must update it if Windows
  DHCP changes.
- Windows Bridge and printer configuration were not modified.
- Cascable demo signing/installation remains separate and blocked.
- Mock camera and Mock printer remain default.

---

## 8. Exact operator actions completed

1. Confirmed Windows IPv4 `192.168.8.192` and same Wi-Fi.
2. Confirmed iPad Safari reaches `/v1/health` with 401.
3. Confirmed Terabooth Local Network permission is ON.
4. Entered the Bridge API token only in the masked iPad field.
5. Saved and tested; app reported **Bridge connected**.

No token was sent to the agent, printed, logged or written to documentation.

**Stopped after verified authenticated LAN health.**
