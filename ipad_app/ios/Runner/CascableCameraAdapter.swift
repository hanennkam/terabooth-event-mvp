import Flutter
import Foundation
import UIKit
import CascableCore
import CascableCoreSimulatedCamera

/// iOS-side CascableCore adapter. SDK types never cross the Flutter boundary.
///
/// The adapter deliberately does not report a capture after the shutter request:
/// a capture completes only when the camera provides original image bytes.
final class CascableCameraAdapter: NSObject, FlutterStreamHandler, CameraDiscoveryDelegate {
    private let discovery = CameraDiscovery.sharedInstance()
    private var camera: Camera?
    private var discovered: [String: Camera] = [:]
    private var eventSink: FlutterEventSink?
    private var pendingConnect: FlutterResult?
    private var pendingConnectId: String?
    private var connectTimeout: DispatchWorkItem?
    private var pendingCapture: PendingCapture?
    private var transferHandlerToken: String?
    private var liveViewActive = false
    private var lastLiveFrameEmission = Date.distantPast

    private final class PendingCapture {
        let captureId: String
        let result: FlutterResult
        var completed = false
        var timeout: DispatchWorkItem?
        init(captureId: String, result: @escaping FlutterResult) {
            self.captureId = captureId
            self.result = result
        }
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    // MARK: - Method channel

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            initialize(result)
        case "startDiscovery":
            startDiscovery(result)
        case "stopDiscovery":
            discovery.stopSearching()
            result(nil)
        case "connect":
            connect(call.arguments, result: result)
        case "disconnect":
            disconnect(result)
        case "capture":
            capture(call.arguments, result: result)
        case "status":
            result(statusPayload())
        case "startLiveView":
            startLiveView(result)
        case "stopLiveView":
            stopLiveView()
            result(nil)
        case "dispose":
            dispose()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Initialization / authorization

    private func initialize(_ result: @escaping FlutterResult) {
        guard CameraPlugin.licenseApplied else {
            result(FlutterError(code: "CAMERA_LICENSE_MISSING", message: "CascableCore licence was not applied.", details: nil))
            return
        }
        let supportsWired = discovery.platformSupportsWiredCameras
        if supportsWired && !discovery.hasAuthorizationToDiscoverWiredCameras {
            discovery.attemptToObtainWiredCameraAuthorization { [weak self] success in
                DispatchQueue.main.async {
                    result(self?.initializationPayload(wiredAuthorization: success) ?? [
                        "ok": false,
                        "licensed": true,
                        "platformSupportsWiredCameras": supportsWired,
                        "wiredAuthorization": false
                    ])
                }
            }
            return
        }
        result(initializationPayload(wiredAuthorization: discovery.hasAuthorizationToDiscoverWiredCameras))
    }

    private func initializationPayload(wiredAuthorization: Bool) -> [String: Any] {
        return [
            "ok": true,
            "backend": "cascablecore",
            "licensed": CameraPlugin.licenseApplied,
            "platformSupportsWiredCameras": discovery.platformSupportsWiredCameras,
            "wiredAuthorization": wiredAuthorization
        ]
    }

    // MARK: - Discovery / connection

    private func startDiscovery(_ result: @escaping FlutterResult) {
        guard CameraPlugin.licenseApplied else {
            result(FlutterError(code: "CAMERA_LICENSE_MISSING", message: "CascableCore licence was not applied.", details: nil))
            return
        }
        discovery.discoveryMode = .usbOnly
        discovery.setEnabled(false, forPluginWithIdentifier: SimulatedCameraPluginIdentifier)
        discovery.clientName = "Terabooth"
        discovery.delegate = self
        discovery.beginSearching()
        result(nil)
    }

    private func connect(_ arguments: Any?, result: @escaping FlutterResult) {
        guard CameraPlugin.licenseApplied else {
            result(FlutterError(code: "CAMERA_LICENSE_MISSING", message: "CascableCore licence was not applied.", details: nil))
            return
        }
        guard discovery.platformSupportsWiredCameras else {
            result(FlutterError(code: "CAMERA_PERMISSION_DENIED", message: "wired cameras are not supported on this platform", details: nil))
            return
        }
        guard discovery.hasAuthorizationToDiscoverWiredCameras else {
            result(FlutterError(code: "CAMERA_PERMISSION_DENIED", message: "wired-camera authorization has not been granted", details: nil))
            return
        }
        if let camera, camera.connected {
            result(connectionPayload(camera))
            return
        }
        if pendingConnect != nil {
            result(FlutterError(code: "CAMERA_CONNECT_FAILED", message: "camera connection already in progress", details: nil))
            return
        }

        let requestedId = (arguments as? [String: Any])?["cameraId"] as? String
        pendingConnect = result
        pendingConnectId = requestedId
        startDiscovery { _ in }
        scheduleConnectTimeout()
    }

    private func scheduleConnectTimeout() {
        connectTimeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let pending = self.pendingConnect else { return }
            self.pendingConnect = nil
            self.pendingConnectId = nil
            self.discovery.stopSearching()
            pending(FlutterError(code: "CAMERA_CONNECT_TIMEOUT", message: "camera connection timed out", details: nil))
        }
        connectTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0, execute: work)
    }

    func discovery(_ discovery: CameraDiscovery, didDiscover camera: Camera) {
        let id = cameraId(camera)
        discovered[id] = camera
        let payload: [String: Any] = [
            "type": "discovery",
            "id": id,
            "model": camera.service.model ?? "unknown",
            "manufacturer": camera.service.manufacturer ?? "unknown",
            "transport": transportName(camera.cameraTransport),
            "state": "discovered"
        ]
        emit(payload)

        guard pendingConnect != nil else { return }
        if let requested = pendingConnectId, requested != id { return }
        discovery.stopSearching()
        connectCamera(camera)
    }

    func discovery(_ discovery: CameraDiscovery, didLoseSightOf camera: Camera) {
        let id = cameraId(camera)
        discovered.removeValue(forKey: id)
        emit([
            "type": "discovery",
            "id": id,
            "model": camera.service.model ?? "unknown",
            "state": "lost"
        ])
    }

    private func connectCamera(_ camera: Camera) {
        let id = cameraId(camera)
        emit([
            "type": "connection",
            "id": id,
            "model": camera.service.model ?? "unknown",
            "state": "connecting"
        ])
        camera.connect(authenticationRequestCallback: { context in
            self.emit(["type": "connection", "id": id, "state": "authenticationRequired", "authenticationType": context.type.rawValue])
            // No PIN is known for the camera. Do not guess or fake success.
            context.submitCancellation()
        }, authenticationResolvedCallback: {
            self.emit(["type": "connection", "id": id, "state": "authenticationResolved"])
        }, completionCallback: { [weak self] error, warnings in
            guard let self else { return }
            if let error {
                self.finishConnectFailure(id: id, message: error.localizedDescription)
                return
            }
            self.camera = camera
            self.installTransferHandler(on: camera)
            self.emit([
                "type": "connection",
                "id": id,
                "model": camera.service.model ?? "unknown",
                "transport": self.transportName(camera.cameraTransport),
                "state": "connected",
                "warnings": warnings?.count ?? 0
            ])
            self.finishConnectSuccess(camera)
        })
    }

    private func finishConnectSuccess(_ camera: Camera) {
        connectTimeout?.cancel()
        connectTimeout = nil
        pendingConnectId = nil
        guard let pending = pendingConnect else { return }
        pendingConnect = nil
        pending(connectionPayload(camera))
    }

    private func finishConnectFailure(id: String, message: String) {
        connectTimeout?.cancel()
        connectTimeout = nil
        pendingConnectId = nil
        emit(["type": "connection", "id": id, "state": "failed", "message": message])
        guard let pending = pendingConnect else { return }
        pendingConnect = nil
        pending(FlutterError(code: "CAMERA_CONNECT_FAILED", message: message, details: nil))
    }

    private func connectionPayload(_ camera: Camera) -> [String: Any] {
        return [
            "ok": true,
            "cameraId": cameraId(camera),
            "model": camera.service.model ?? "unknown",
            "manufacturer": camera.service.manufacturer ?? "unknown",
            "transport": transportName(camera.cameraTransport),
            "state": "connected"
        ]
    }

    // MARK: - Disconnect

    private func disconnect(_ result: @escaping FlutterResult) {
        connectTimeout?.cancel()
        connectTimeout = nil
        if let pending = pendingConnect {
            pendingConnect = nil
            pendingConnectId = nil
            pending(FlutterError(code: "CAMERA_DISCONNECTED", message: "camera disconnected", details: nil))
        }
        failCapture(code: "CAMERA_DISCONNECTED", message: "camera disconnected before image transfer")
        stopLiveView()
        removeTransferHandler()
        discovery.stopSearching()
        guard let camera else {
            emit(["type": "connection", "state": "disconnected"])
            result(nil)
            return
        }
        self.camera = nil
        camera.disconnect({ [weak self] error in
            self?.emit([
                "type": "connection",
                "state": error == nil ? "disconnected" : "disconnectFailed",
                "message": error?.localizedDescription ?? ""
            ])
            result(nil)
        }, callbackQueue: nil)
    }

    // MARK: - Capture / original transfer

    private func capture(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let camera, camera.connected else {
            result(FlutterError(code: "CAMERA_NOT_CONNECTED", message: "camera is not connected", details: nil))
            return
        }
        guard pendingCapture == nil else {
            result(FlutterError(code: "CAPTURE_IN_PROGRESS", message: "a capture is already in progress", details: nil))
            return
        }

        let captureId = (arguments as? [String: Any])?["captureId"] as? String
            ?? "cap_\(UUID().uuidString)"
        let pending = PendingCapture(captureId: captureId, result: result)
        pendingCapture = pending
        emit(["type": "capture", "captureId": captureId, "state": "shutterRequested"])

        let timeout = DispatchWorkItem { [weak self] in
            self?.failCapture(code: "CAPTURE_TIMEOUT", message: "original image did not arrive before timeout")
        }
        pending.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 12.0, execute: timeout)

        camera.invokeOneShotShutterExplicitlyEngagingAutoFocus(true, completionCallback: { [weak self] error in
            guard let self else { return }
            if let error {
                self.failCapture(code: "CAPTURE_FAILED", message: error.localizedDescription)
            } else {
                // This is only the shutter request acknowledgement.
                self.emit(["type": "capture", "captureId": captureId, "state": "shutterSent"])
            }
        })
    }

    private func installTransferHandler(on camera: Camera) {
        removeTransferHandler()
        transferHandlerToken = camera.addCameraInitiatedTransferHandler { [weak self] request in
            self?.handleTransferRequest(request)
        }
    }

    private func removeTransferHandler() {
        if let token = transferHandlerToken, let camera {
            camera.removeCameraInitiatedTransferHandler(with: token)
        }
        transferHandlerToken = nil
    }

    private func handleTransferRequest(_ request: CameraInitiatedTransferRequest) {
        guard let pending = pendingCapture else {
            // A late transfer after timeout/disconnect must not complete anything.
            return
        }
        guard request.isValid else {
            failCapture(code: "TRANSFER_FAILED", message: "camera transfer request expired")
            return
        }
        guard request.canProvide(.original) else {
            failCapture(code: "TRANSFER_FAILED", message: "camera did not offer an original image")
            return
        }

        emit(["type": "capture", "captureId": pending.captureId, "state": "transferring"])
        request.executeTransfer(for: .original) { [weak self] transferResult, error in
            guard let self, self.pendingCapture === pending else { return }
            if let error {
                self.failCapture(code: "TRANSFER_FAILED", message: error.localizedDescription)
                return
            }
            guard let transferResult else {
                self.failCapture(code: "TRANSFER_FAILED", message: "camera returned no transfer result")
                return
            }
            transferResult.generateData(for: .original) { [weak self] data, error in
                guard let self, self.pendingCapture === pending else { return }
                if let error {
                    self.failCapture(code: "TRANSFER_FAILED", message: error.localizedDescription)
                    return
                }
                guard let data, Self.isJPEG(data) else {
                    self.failCapture(code: "INVALID_IMAGE", message: "camera original is not a JPEG")
                    return
                }
                self.completeCapture(pending: pending, data: data)
            }
        }
    }

    private static func isJPEG(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let bytes = [UInt8](data)
        return bytes[0] == 0xFF &&
            bytes[1] == 0xD8 &&
            bytes[2] == 0xFF &&
            bytes[bytes.count - 2] == 0xFF &&
            bytes[bytes.count - 1] == 0xD9
    }

    private func completeCapture(pending: PendingCapture, data: Data) {
        guard pendingCapture === pending, !pending.completed else { return }
        pending.completed = true
        pending.timeout?.cancel()
        pendingCapture = nil
        emit(["type": "capture", "captureId": pending.captureId, "state": "originalReceived", "byteCount": data.count])
        pending.result([
            "captureId": pending.captureId,
            "bytes": data.base64EncodedString(),
            "width": 0,
            "height": 0
        ])
    }

    private func failCapture(code: String, message: String) {
        guard let pending = pendingCapture, !pending.completed else { return }
        pending.completed = true
        pending.timeout?.cancel()
        pendingCapture = nil
        emit(["type": "capture", "captureId": pending.captureId, "state": "failed", "code": code, "message": message])
        pending.result(FlutterError(code: code, message: message, details: nil))
    }

    // MARK: - Live View

    private func startLiveView(_ result: @escaping FlutterResult) {
        guard let camera, camera.connected else {
            result(FlutterError(code: "CAMERA_NOT_CONNECTED", message: "camera is not connected", details: nil))
            return
        }
        let liveView = camera
        guard !liveViewActive else {
            result(nil)
            return
        }
        liveViewActive = true
        let delivery: LiveViewFrameDelivery = { [weak self] frame, ready in
            guard let self else { ready(); return }
            defer { ready() }
            guard frame.rawPixelFormat == .JPEG else { return }
            let now = Date()
            guard now.timeIntervalSince(self.lastLiveFrameEmission) >= 0.1 else { return }
            self.lastLiveFrameEmission = now
            self.emit([
                "type": "liveViewFrame",
                "bytes": frame.rawPixelData.base64EncodedString(),
                "width": Int(frame.naturalImageSize.width),
                "height": Int(frame.naturalImageSize.height)
            ])
        }
        liveView.beginStream(delivery: delivery, deliveryQueue: nil, terminationHandler: { [weak self] reason, error in
            self?.liveViewActive = false
            self?.emit([
                "type": "connection",
                "state": "liveViewTerminated",
                "reason": reason.rawValue,
                "message": error?.localizedDescription ?? ""
            ])
        })
        emit(["type": "connection", "state": "liveViewStarted"])
        result(nil)
    }

    private func stopLiveView() {
        guard liveViewActive else { return }
        camera?.endStream()
        liveViewActive = false
        emit(["type": "connection", "state": "liveViewStopped"])
    }

    // MARK: - Helpers

    private func dispose() {
        stopLiveView()
        removeTransferHandler()
        failCapture(code: "CAMERA_DISCONNECTED", message: "camera adapter disposed")
        discovery.stopSearching()
        discovery.delegate = nil
        camera = nil
        discovered.removeAll()
    }

    private func cameraId(_ camera: Camera) -> String {
        if let identifier = camera.friendlyIdentifier, !identifier.isEmpty {
            return identifier
        }
        return "camera-\(String(describing: ObjectIdentifier(camera).hashValue))"
    }

    private func transportName(_ transport: CameraTransport) -> String {
        switch transport {
        case .USB: return "usb"
        case .network: return "network"
        @unknown default: return "unknown"
        }
    }

    private func statusPayload() -> [String: Any] {
        var payload: [String: Any] = [
            "licensed": CameraPlugin.licenseApplied,
            "connected": camera?.connected ?? false,
            "backend": "cascablecore"
        ]
        if let camera {
            payload["cameraId"] = cameraId(camera)
            payload["model"] = camera.service.model ?? "unknown"
            payload["state"] = camera.connected ? "connected" : "disconnected"
            payload["transport"] = transportName(camera.cameraTransport)
        } else {
            payload["state"] = "disconnected"
        }
        return payload
    }

    private func emit(_ payload: [String: Any]) {
        guard let eventSink else { return }
        if Thread.isMainThread {
            eventSink(payload)
        } else {
            DispatchQueue.main.async { eventSink(payload) }
        }
    }
}
