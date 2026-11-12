# Terabooth CascableCore macOS Demo

Isolated native AppKit validation target for the physical Canon EOS 60D.

- Bundle ID: `se.cascable.CascableCoreMacDemo`
- SDK: official remote CascableCore 18.0.2
- Licence: place the issued bytes at `CascableCoreLicense.licence`; this file is ignored and must not be committed.
- Do not run while Cascable Studio/EOS Utility owns the USB camera.

```bash
xcodebuild -project TeraboothCascableMacDemo.xcodeproj \
  -scheme TeraboothCascableMacDemo \
  -configuration Debug \
  -derivedDataPath /tmp/TeraboothMacDemoDerived build

# With camera connected and competing apps closed:
/tmp/TeraboothMacDemoDerived/Build/Products/Debug/TeraboothCascableMacDemo.app/Contents/MacOS/TeraboothCascableMacDemo

# No shutter request:
.../TeraboothCascableMacDemo --no-shutter
```

See `../docs/technical/PHASE_3A_1B_CANON_60D_MAC_SDK_VALIDATION.md`.
