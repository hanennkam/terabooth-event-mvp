#if CASCABLE_DEMO
import Foundation
import CascableCore
import CascableCoreSimulatedCamera

/// Development-only probe for the licensed demo build. It intentionally uses
/// the official CameraDiscovery, SimulatedCameraConfiguration and Camera APIs.
/// It is not wired into BoothController and does not replace MockCameraService.
final class CascableCoreDemoProbe: NSObject, CameraDiscoveryDelegate {
    static let shared = CascableCoreDemoProbe()

    private var camera: Camera?
    private var liveViewFrames = 0
    private var transferHandlerToken: String?

    private override init() {
        super.init()
    }

    func start(licenseApplied: Bool) {
        let discovery = CameraDiscovery.sharedInstance()
        NSLog("CASCABLE_DEMO_LICENSE=\(licenseApplied ? "applied" : "blocked")")
        NSLog("CASCABLE_DEMO_PLUGINS=\(discovery.loadedPluginIdentifiers.sorted())")
        guard licenseApplied else {
            NSLog("CASCABLE_DEMO_PROBE=blocked_missing_or_invalid_license")
            return
        }

        var configuration = SimulatedCameraConfiguration.default
        configuration.connectionAuthentication = .none
        configuration.connectionSpeed = .fast
        configuration.apply()

        discovery.setEnabled(true, forPluginWithIdentifier: SimulatedCameraPluginIdentifier)
        discovery.clientName = "Terabooth Cascable Demo"
        discovery.delegate = self
        discovery.beginSearching()
        NSLog("CASCABLE_DEMO_DISCOVERY=started")
    }

    func discovery(_ discovery: CameraDiscovery, didDiscover camera: Camera) {
        NSLog("CASCABLE_DEMO_DISCOVERED=\(camera.service.model ?? "unknown") transport=\(String(describing: camera.cameraTransport))")
        discovery.stopSearching()
        connect(camera)
    }

    func discovery(_ discovery: CameraDiscovery, didLoseSightOf camera: Camera) {
        NSLog("CASCABLE_DEMO_LOST_SIGHT=\(camera.service.model ?? "unknown")")
    }

    private func connect(_ camera: Camera) {
        camera.connect(authenticationRequestCallback: { context in
            NSLog("CASCABLE_DEMO_AUTH=requested type=\(String(describing: context.type))")
            if context.type == .fourDigitNumericCode {
                context.submitNumericCode("1234")
            } else {
                context.submitCancellation()
            }
        }, authenticationResolvedCallback: {
            NSLog("CASCABLE_DEMO_AUTH=resolved")
        }, completionCallback: { [weak self] error, warnings in
            if let error {
                NSLog("CASCABLE_DEMO_CONNECT=failed \(error.localizedDescription)")
                return
            }
            self?.camera = camera
            NSLog("CASCABLE_DEMO_CONNECT=connected warnings=\(warnings?.count ?? 0) state=\(String(describing: camera.connectionState))")
            self?.startLiveView(camera)
            self?.capture(camera)
            DispatchQueue.global().asyncAfter(deadline: .now() + 10.0) { [weak self] in
                DispatchQueue.main.async {
                    guard let self, self.camera != nil else { return }
                    NSLog("CASCABLE_DEMO_DISCONNECT=requested")
                    camera.disconnect({ error in
                        NSLog("CASCABLE_DEMO_DISCONNECT=\(error == nil ? "complete" : "failed") error=\(error?.localizedDescription ?? "none")")
                    }, callbackQueue: nil)
                    self.camera = nil
                }
            }
        })
    }

    private func startLiveView(_ camera: Camera) {
        guard let liveViewCamera = camera as? CameraLiveView else {
            NSLog("CASCABLE_DEMO_LIVE_VIEW=unsupported")
            return
        }
        let delivery: LiveViewFrameDelivery = { [weak self] frame, readyForNextFrame in
            guard let self else { readyForNextFrame(); return }
            self.liveViewFrames += 1
            if self.liveViewFrames == 1 {
                NSLog("CASCABLE_DEMO_LIVE_VIEW=frame size=\(frame.naturalImageSize) format=\(String(describing: frame.rawPixelFormat))")
            }
            readyForNextFrame()
        }
        liveViewCamera.beginStream(delivery: delivery, deliveryQueue: nil, terminationHandler: { reason, error in
            NSLog("CASCABLE_DEMO_LIVE_VIEW=terminated reason=\(String(describing: reason)) error=\(error?.localizedDescription ?? "none")")
        })
    }

    private func capture(_ camera: Camera) {
        transferHandlerToken = camera.addCameraInitiatedTransferHandler { request in
            guard request.isValid else {
                NSLog("CASCABLE_DEMO_TRANSFER=invalid")
                return
            }
            guard request.canProvide(.preview) else {
                NSLog("CASCABLE_DEMO_TRANSFER=no_preview")
                return
            }
            NSLog("CASCABLE_DEMO_TRANSFER=preview_available")
            request.executeTransfer(for: .preview) { result, error in
                guard let result else {
                    NSLog("CASCABLE_DEMO_TRANSFER=failed \(error?.localizedDescription ?? "unknown")")
                    return
                }
                result.generatePreviewImage { image, error in
                    if let image {
                        NSLog("CASCABLE_DEMO_TRANSFER=preview_received size=\(image.size)")
                    } else {
                        NSLog("CASCABLE_DEMO_TRANSFER=preview_decode_failed \(error?.localizedDescription ?? "unknown")")
                    }
                }
            }
        }

        // The SDK completion means the request was sent, not that a frame was captured.
        camera.invokeOneShotShutterExplicitlyEngagingAutoFocus(true, completionCallback: { error in
            NSLog("CASCABLE_DEMO_CAPTURE_REQUEST=\(error == nil ? "sent" : "failed") error=\(error?.localizedDescription ?? "none")")
        })
    }
}
#endif
