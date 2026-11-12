import AppKit
import CascableCore
import ImageIO
import CryptoKit

final class MacCameraProbe: NSObject, NSApplicationDelegate, CameraDiscoveryDelegate {
    private let discovery = CameraDiscovery.sharedInstance()
    private var camera: Camera?
    private var liveViewFrames = 0
    private var didAudit = false
    private var didShutter = false
    private var didRequestTransfer = false
    private var transferHandlerToken: String?
    private var transferRequestCount = 0
    private var transferTimeout: DispatchWorkItem?
    private var transferCompleted = false
    private var cleanupStarted = false
    private var disconnectStarted = false
    private var pendingDisconnectCamera: Camera?
    private var liveViewStartRequested = false
    private var liveViewTerminationObserved = true
    private var liveViewStopTimeout: DispatchWorkItem?

    private var wantsTransfer: Bool { CommandLine.arguments.contains("--transfer") }
    private var capabilityOnly: Bool { CommandLine.arguments.contains("--capability-only") }
    private var noReconnect: Bool { CommandLine.arguments.contains("--no-reconnect") }
    private var wantsDisconnectDuringTransfer: Bool { CommandLine.arguments.contains("--disconnect-during-transfer") }
    private var captureId: String?
    private var predictedOriginalBytes: Int = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let url = Bundle.main.url(forResource: "CascableCoreLicense", withExtension: "licence"),
              let data = try? Data(contentsOf: url), !data.isEmpty else {
            NSLog("CASCABLE_MAC_LICENSE=blocked missing_or_empty")
            NSApp.terminate(nil)
            return
        }

        let result = CascableCoreLicenseVerification.apply(license: data)
        NSLog("CASCABLE_MAC_LICENSE_RESULT=\(result.rawValue)")
        guard result == .success else {
            NSLog("CASCABLE_MAC_LICENSE=blocked")
            NSApp.terminate(nil)
            return
        }

        NSLog("CASCABLE_MAC_BUNDLE=\(Bundle.main.bundleIdentifier ?? "unknown")")
        discovery.discoveryMode = .usbOnly
        discovery.delegate = self
        discovery.beginSearching()
        NSLog("CASCABLE_MAC_DISCOVERY=started mode=usbOnly mode_args transfer=\(wantsTransfer)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 40.0) {
            NSLog("CASCABLE_MAC_TIMEOUT=terminating")
            NSApp.terminate(nil)
        }
    }

    func discovery(_ discovery: CameraDiscovery, didDiscover camera: Camera) {
        NSLog("CASCABLE_MAC_DISCOVERED vendor=\(camera.service.manufacturer ?? "unknown") model=\(camera.service.model ?? "unknown") transport=\(camera.cameraTransport.rawValue) state=\(camera.connectionState.rawValue)")
        discovery.stopSearching()
        connect(camera)
    }

    func discovery(_ discovery: CameraDiscovery, didLoseSightOf camera: Camera) {
        NSLog("CASCABLE_MAC_LOST_SIGHT model=\(camera.service.model ?? "unknown")")
    }

    private func connect(_ camera: Camera) {
        NSLog("CASCABLE_MAC_CONNECT=requested")
        camera.connect(authenticationRequestCallback: { context in
            NSLog("CASCABLE_MAC_AUTH=requested type=\(context.type.rawValue)")
            if context.type == .fourDigitNumericCode {
                context.submitNumericCode("1234")
            } else {
                context.submitCancellation()
            }
        }, authenticationResolvedCallback: {
            NSLog("CASCABLE_MAC_AUTH=resolved")
        }, completionCallback: { [weak self] error, warnings in
            guard let self else { return }
            if let error {
                NSLog("CASCABLE_MAC_CONNECT=failed error=\(error.localizedDescription)")
                return
            }
            self.camera = camera
            NSLog("CASCABLE_MAC_CONNECT=connected warnings=\(warnings?.count ?? 0) state=\(camera.connectionState.rawValue) model=\(camera.service.model ?? "unknown") transport=\(camera.cameraTransport.rawValue)")
            for warning in warnings ?? [] {
                NSLog("CASCABLE_MAC_WARNING type=\(warning.type.rawValue) category=\(warning.category.rawValue)")
            }
            self.installTransferHandler(camera)
            self.audit(camera)
            self.startLiveView(camera)
            self.startRequestedTransferIfPossible(camera)

            let disconnectDelay: TimeInterval = self.capabilityOnly ? 8.0 : 25.0
            DispatchQueue.global().asyncAfter(deadline: .now() + disconnectDelay) {
                DispatchQueue.main.async { [weak self] in
                    self?.stopAndDisconnect(camera)
                }
            }
        })
    }

    // MARK: - Capability audit

    private func audit(_ camera: Camera) {
        guard !didAudit else { return }
        didAudit = true
        let supported = camera.supportedFunctionality
        NSLog("CASCABLE_MAC_CAPABILITY_FUNCTIONALITY_RAW=\(supported.rawValue)")
        NSLog("CASCABLE_MAC_CAPABILITY_FUNCTIONALITY=\(functionalityNames(supported))")
        NSLog("CASCABLE_MAC_CAPABILITY_COMMAND_CATEGORIES_RAW=\(camera.currentCommandCategories.rawValue)")
        NSLog("CASCABLE_MAC_CAPABILITY_COMMAND_CATEGORIES=\(commandCategoryNames(camera.currentCommandCategories))")
        NSLog("CASCABLE_MAC_CAPABILITY_LIVE_VIEW_ACTIVE=\(camera.liveViewStreamActive)")
        NSLog("CASCABLE_MAC_CAPABILITY_KNOWN_PROPERTIES=\(camera.knownPropertyIdentifiers.count)")
        NSLog("CASCABLE_MAC_STORAGE=devices \(camera.storageDevices?.count ?? 0)")
        NSLog("CASCABLE_MAC_STORAGE=shots_available \(camera.property(with: .shotsAvailable).currentValue?.localizedDisplayValue ?? "nil")")

        let identifiers: [PropertyIdentifier] = [.aperture, .shutterSpeed, .isoSpeed, .autoExposureMode, .batteryLevel, .imageQuality, .whiteBalance, .driveMode, .exposureCompensation]
        var writable = 0
        for identifier in identifiers {
            let property = camera.property(with: identifier)
            let name = property.localizedDisplayName ?? "unknown"
            let value = property.currentValue?.localizedDisplayValue ?? "nil"
            let setType = property.valueSetType
            let valid = property.validSettableValues ?? []
            let validPreview = valid.prefix(5).map { $0.localizedDisplayValue ?? $0.stringValue }
            let range = property.validValueRange.map { String(describing: $0) } ?? "nil"
            if setType != [] { writable += 1 }
            NSLog("CASCABLE_MAC_PROPERTY id=\(identifier.rawValue) name=\(name) current=\(value) set_type=\(setType.rawValue) valid_count=\(valid.count) valid_preview=\(validPreview) range=\(range)")
        }
        let imageQuality = camera.property(with: .imageQuality)
        NSLog("CASCABLE_MAC_IMAGE_QUALITY=current \(imageQuality.currentValue?.localizedDisplayValue ?? "nil") set_type=\(imageQuality.valueSetType.rawValue) valid_count=\(imageQuality.validSettableValues?.count ?? 0) known=\(camera.knownPropertyIdentifiers.contains(NSNumber(value: PropertyIdentifier.imageQuality.rawValue)))")
        NSLog("CASCABLE_MAC_CAPABILITY_WRITABLE_SAMPLED=\(writable)")
        NSLog("CASCABLE_MAC_SETTINGS_WRITE=not_attempted")
    }

    private func functionalityNames(_ value: SupportedFunctionality) -> String {
        let names: [(SupportedFunctionality, String)] = [
            (.afPoints, "afPoints"),
            (.liveViewOrientation, "liveViewOrientation"),
            (.remoteControlWithoutLiveView, "remoteControlWithoutLiveView"),
            (.fileDeletion, "fileDeletion"),
            (.depthOfFieldPreview, "depthOfFieldPreview"),
            (.shutterHalfPress, "shutterHalfPress"),
            (.updateClock, "updateClock"),
            (.limitedRemoteControlWithoutLiveView, "limitedRemoteControlWithoutLiveView"),
            (.directFocusManipulation, "directFocusManipulation"),
            (.powerOffOnDisconnect, "powerOffOnDisconnect"),
            (.exposureControl, "exposureControl"),
            (.cameraInitiatedTransfer, "cameraInitiatedTransfer"),
            (.croppableLiveView, "croppableLiveView"),
            (.videoRecording, "videoRecording"),
            (.pannableLiveView, "pannableLiveView"),
            (.mutableRatings, "mutableRatings")
        ]
        return names.filter { value.contains($0.0) }.map { $0.1 }.joined(separator: ",")
    }

    private func commandCategoryNames(_ value: AvailableCommandCategory) -> String {
        var names: [String] = []
        if value.contains(.stillsShooting) { names.append("stillsShooting") }
        if value.contains(.filesystemAccess) { names.append("filesystemAccess") }
        if value.contains(.videoRecording) { names.append("videoRecording") }
        return names.joined(separator: ",")
    }

    // MARK: - Original transfer

    private func startRequestedTransferIfPossible(_ camera: Camera) {
        guard wantsTransfer && !capabilityOnly else {
            NSLog("CASCABLE_MAC_TRANSFER=not_requested")
            return
        }
        let storage = camera.storageDevices?.count ?? 0
        guard storage > 0 else {
            NSLog("CASCABLE_MAC_TRANSFER=blocked_no_storage")
            NSLog("CASCABLE_MAC_SHUTTER=skipped_no_storage")
            return
        }
        didShutter = true
        let id = "cap_\(UUID().uuidString.lowercased())"
        captureId = id
        NSLog("CASCABLE_MAC_CAPTURE_ID=\(id)")
        NSLog("CASCABLE_MAC_TRANSFER=waiting_for_request capture_id=\(id)")
        camera.invokeOneShotShutterExplicitlyEngagingAutoFocus(true, completionCallback: { [weak self] error in
            NSLog("CASCABLE_MAC_SHUTTER=requested capture_id=\(self?.captureId ?? "nil") error=\(error?.localizedDescription ?? "none")")
            guard let self, error == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.transferCompleted else { return }
                NSLog("CASCABLE_MAC_TRANSFER=timeout")
                self.stopAndDisconnect(camera)
            }
            self.transferTimeout = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 20.0, execute: work)
        })
    }

    private func installTransferHandler(_ camera: Camera) {
        if let token = transferHandlerToken {
            camera.removeCameraInitiatedTransferHandler(with: token)
        }
        transferHandlerToken = camera.addCameraInitiatedTransferHandler { [weak self] request in
            self?.handleTransferRequest(request)
        }
        NSLog("CASCABLE_MAC_TRANSFER_HANDLER=registered token=\(transferHandlerToken != nil)")
    }

    private func handleTransferRequest(_ request: CameraInitiatedTransferRequest) {
        transferRequestCount += 1
        NSLog("CASCABLE_MAC_TRANSFER_REQUEST count=\(transferRequestCount) capture_id=\(captureId ?? "nil") valid=\(request.isValid) representations=\(request.availableRepresentations.rawValue) can_original=\(request.canProvide(.original)) can_preview=\(request.canProvide(.preview)) predicted_original_bytes=\(request.predictedFileSize(for: .original)) only_destination=\(request.isOnlyDestinationForImage)")
        predictedOriginalBytes = request.predictedFileSize(for: .original)
        if transferRequestCount > 1 {
            NSLog("CASCABLE_MAC_TRANSFER=duplicate_callback_ignored")
            return
        }
        guard !didRequestTransfer else { return }
        guard request.isValid else {
            NSLog("CASCABLE_MAC_TRANSFER=failed_stale_request")
            return
        }
        guard request.canProvide(.original) else {
            NSLog("CASCABLE_MAC_TRANSFER=unsupported_no_original")
            return
        }
        didRequestTransfer = true
        NSLog("CASCABLE_MAC_TRANSFER=original_requested")

        if wantsDisconnectDuringTransfer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, let camera = self.camera else { return }
                self.stopAndDisconnect(camera)
            }
        }

        request.executeTransfer(for: .original) { [weak self] result, error in
            guard let self else { return }
            if let error {
                NSLog("CASCABLE_MAC_TRANSFER=failed error=\(error.localizedDescription)")
                return
            }
            guard let result else {
                NSLog("CASCABLE_MAC_TRANSFER=failed_no_result")
                return
            }
            NSLog("CASCABLE_MAC_TRANSFER_RESULT available=\(result.availableRepresentations.rawValue) contains_original=\(result.contains(.original)) filename=\(result.fileNameHint ?? "nil")")
            result.generateData(for: .original) { [weak self] data, error in
                guard let self else { return }
                if let error {
                    NSLog("CASCABLE_MAC_TRANSFER=failed_generate_data error=\(error.localizedDescription)")
                    return
                }
                guard let data else {
                    NSLog("CASCABLE_MAC_TRANSFER=failed_no_data")
                    return
                }
                self.validateAndSaveOriginal(data)
            }
        }
    }

    private func validateAndSaveOriginal(_ data: Data) {
        let prefix = [UInt8](data.prefix(8))
        let isJPEG = prefix.count >= 3 && prefix[0] == 0xFF && prefix[1] == 0xD8 && prefix[2] == 0xFF
        let isTIFF = prefix.count >= 4 && ((prefix[0] == 0x49 && prefix[1] == 0x49 && prefix[2] == 0x2A && prefix[3] == 0x00) || (prefix[0] == 0x4D && prefix[1] == 0x4D && prefix[2] == 0x00 && prefix[3] == 0x2A))
        let isCR2 = isTIFF && data.count >= 10 && String(data: data.subdata(in: 8..<10), encoding: .ascii) == "CR"
        let hasEOI = data.count >= 2 && data[data.count - 2] == 0xFF && data[data.count - 1] == 0xD9
        let sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let mime = isJPEG ? "image/jpeg" : (isCR2 ? "image/x-canon-cr2" : "application/octet-stream")
        NSLog("CASCABLE_MAC_ORIGINAL=bytes \(data.count) predicted_bytes=\(predictedOriginalBytes) jpeg_signature=\(isJPEG) eoi=\(hasEOI) tiff=\(isTIFF) cr2=\(isCR2) mime=\(mime) sha256=\(sha256) capture_id=\(captureId ?? "nil")")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("terabooth-eos60d-jpeg-\(UUID().uuidString)", isDirectory: true)
        let payload = dir.appendingPathComponent("payload.bin")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try data.write(to: payload, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: payload.path)
            NSLog("CASCABLE_MAC_ORIGINAL=payload_saved path=\(payload.path) bytes=\(data.count) mode=0600")
        } catch {
            NSLog("CASCABLE_MAC_ORIGINAL=failed_save error=\(error.localizedDescription)")
            stopAfterOriginal(dataAccepted: false)
            return
        }

        guard isJPEG && hasEOI else {
            let ext = isCR2 ? "cr2" : "bin"
            let evidence = dir.appendingPathComponent("original.\(ext)")
            do {
                try FileManager.default.moveItem(at: payload, to: evidence)
                NSLog("CASCABLE_MAC_ORIGINAL=preserved_non_jpeg path=\(evidence.path) type=\(mime)")
            } catch {
                NSLog("CASCABLE_MAC_ORIGINAL=failed_preserve_non_jpeg error=\(error.localizedDescription)")
            }
            NSLog("CASCABLE_MAC_ORIGINAL=failed_jpeg_signature")
            transferCompleted = true
            transferTimeout?.cancel()
            stopAfterOriginal(dataAccepted: false)
            return
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            NSLog("CASCABLE_MAC_ORIGINAL=failed_decode")
            transferCompleted = true
            transferTimeout?.cancel()
            stopAfterOriginal(dataAccepted: false)
            return
        }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 0
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let make = tiff[kCGImagePropertyTIFFMake] as? String ?? "nil"
        let model = tiff[kCGImagePropertyTIFFModel] as? String ?? "nil"
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let dateOriginal = exif[kCGImagePropertyExifDateTimeOriginal] as? String ?? "nil"
        let exposure = exif[kCGImagePropertyExifExposureTime] as? Double
        let fNumber = exif[kCGImagePropertyExifFNumber] as? Double
        let iso = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int]
        let exposureText = exposure.map { String($0) } ?? "nil"
        let fNumberText = fNumber.map { String($0) } ?? "nil"
        let isoText = iso.map { String(describing: $0) } ?? "nil"
        let longEdge = max(width, height)
        let shortEdge = min(width, height)
        let looksFullResolution = longEdge >= 3000 && shortEdge >= 2000
        NSLog("CASCABLE_MAC_ORIGINAL=decoded width=\(width) height=\(height) look_full_resolution=\(looksFullResolution) orientation=\(orientation) make=\(make) model=\(model) exif_date=\(dateOriginal) exposure=\(exposureText) fnumber=\(fNumberText) iso=\(isoText)")

        let final = dir.appendingPathComponent("original.jpg")
        do {
            try FileManager.default.moveItem(at: payload, to: final)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: final.path)
            NSLog("CASCABLE_MAC_ORIGINAL=saved_jpeg path=\(final.path) bytes=\(data.count) width=\(width) height=\(height) mime=\(mime) sha256=\(sha256)")
        } catch {
            NSLog("CASCABLE_MAC_ORIGINAL=failed_save_jpeg error=\(error.localizedDescription)")
            stopAfterOriginal(dataAccepted: false)
            return
        }
        transferCompleted = true
        transferTimeout?.cancel()
        NSLog("CASCABLE_MAC_TRANSFER=original_validated capture_id=\(captureId ?? "nil")")
        NSLog("CASCABLE_MAC_ORIGINAL=exact_camera_file_comparison=not_performed")
        stopAfterOriginal(dataAccepted: true)
    }

    private func stopAfterOriginal(dataAccepted: Bool) {
        NSLog("CASCABLE_MAC_ORIGINAL=result \(dataAccepted ? "jpeg_passed" : "failed")")
        if let camera {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.stopAndDisconnect(camera)
            }
        }
    }

    // MARK: - Live View / cleanup

    private func startLiveView(_ camera: Camera) {
        guard !camera.liveViewStreamActive else {
            NSLog("CASCABLE_MAC_LIVE_VIEW=already_active")
            return
        }
        let delivery: LiveViewFrameDelivery = { [weak self] frame, ready in
            guard let self else { ready(); return }
            self.liveViewFrames += 1
            if self.liveViewFrames == 1 {
                NSLog("CASCABLE_MAC_LIVE_VIEW=frame size=\(frame.naturalImageSize) format=\(frame.rawPixelFormat.rawValue)")
            }
            ready()
        }
        liveViewStartRequested = true
        liveViewTerminationObserved = false
        camera.beginStream(delivery: delivery, deliveryQueue: nil, terminationHandler: { [weak self] reason, error in
            guard let self else { return }
            self.liveViewStartRequested = false
            self.liveViewTerminationObserved = true
            NSLog("CASCABLE_MAC_LIVE_VIEW=terminated reason=\(reason.rawValue) error=\(error?.localizedDescription ?? "none")")
            self.finishLiveViewCleanup()
        })
        NSLog("CASCABLE_MAC_LIVE_VIEW=started")
    }

    private func stopAndDisconnect(_ camera: Camera) {
        guard !cleanupStarted else { return }
        cleanupStarted = true
        pendingDisconnectCamera = camera
        transferTimeout?.cancel()

        let liveViewMayBeActive = camera.liveViewStreamActive || liveViewStartRequested
        guard liveViewMayBeActive else {
            NSLog("CASCABLE_MAC_LIVE_VIEW=already_inactive")
            finishLiveViewCleanup()
            return
        }

        NSLog("CASCABLE_MAC_LIVE_VIEW=stop_requested")
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.liveViewTerminationObserved else { return }
            // Bounded fallback. This is not confirmation that the stream stopped.
            NSLog("CASCABLE_MAC_LIVE_VIEW=stop_timeout_unconfirmed")
            self.finishLiveViewCleanup()
        }
        liveViewStopTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
        camera.endStream()
    }

    private func finishLiveViewCleanup() {
        guard let camera = pendingDisconnectCamera, !disconnectStarted else { return }
        liveViewStopTimeout?.cancel()
        liveViewStopTimeout = nil
        disconnectStarted = true
        if !liveViewTerminationObserved {
            NSLog("CASCABLE_MAC_LIVE_VIEW=termination_not_confirmed")
        }
        if let token = transferHandlerToken {
            camera.removeCameraInitiatedTransferHandler(with: token)
            transferHandlerToken = nil
        }
        NSLog("CASCABLE_MAC_DISCONNECT=requested")
        camera.disconnect({ [weak self] error in
            NSLog("CASCABLE_MAC_DISCONNECT=\(error == nil ? "complete" : "failed") error=\(error?.localizedDescription ?? "none")")
            guard let self else { return }
            self.camera = nil
            self.pendingDisconnectCamera = nil
            if self.capabilityOnly || self.noReconnect {
                NSLog("CASCABLE_MAC_DISCONNECT=no_reconnect_exit")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    NSApp.terminate(nil)
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    NSLog("CASCABLE_MAC_RECONNECT=search_started")
                    self.discovery.beginSearching()
                }
            }
        }, callbackQueue: nil)
    }
}

let app = NSApplication.shared
let probe = MacCameraProbe()
app.delegate = probe
app.setActivationPolicy(.accessory)
app.run()
