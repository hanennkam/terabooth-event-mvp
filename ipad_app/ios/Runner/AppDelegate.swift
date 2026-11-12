import Flutter
import UIKit
import Vision
#if CASCABLE_DEMO
import CascableCore
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
#if CASCABLE_DEMO
    let licenseResult = CascableCoreLicenseVerification.apply(license: CascableCoreLicense.data)
    let licenseApplied = licenseResult == .success
    NSLog("CASCABLE_DEMO_LICENSE_RESULT=\(licenseResult.rawValue) configured=\(CascableCoreLicense.isConfigured)")
    CascableCoreDemoProbe.shared.start(licenseApplied: licenseApplied)
#endif
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TeraboothCameraPlugin") {
      CameraPlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TeraboothVisionPlugin") {
      VisionFacePlugin.register(with: registrar)
    }
  }
}

/// Flutter camera bridge. CascableCore types remain in CascableCameraAdapter.
final class CameraPlugin: NSObject, FlutterPlugin {
  static var licenseApplied = false
  private let adapter = CascableCameraAdapter()

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = CameraPlugin()
    let methods = FlutterMethodChannel(
      name: "com.terabooth/camera",
      binaryMessenger: registrar.messenger()
    )
    let events = FlutterEventChannel(
      name: "com.terabooth/camera/events",
      binaryMessenger: registrar.messenger()
    )
    methods.setMethodCallHandler(plugin.handle)
    events.setStreamHandler(plugin.adapter)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    adapter.handle(call, result: result)
  }
}


/// Local-only Apple Vision face detection.
///
/// Returns normalized top-left rectangles. The Flutter layer only uses these
/// as crop hints; no network or third-party SDK is involved.
final class VisionFacePlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.terabooth/vision",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(VisionFacePlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "detectFaces" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard
      let args = call.arguments as? [String: Any],
      let typed = args["bytes"] as? FlutterStandardTypedData,
      let image = UIImage(data: typed.data)
    else {
      result(FlutterError(
        code: "INVALID_IMAGE",
        message: "Could not decode image bytes for Vision.",
        details: nil
      ))
      return
    }
    guard let cgImage = image.cgImage else {
      result(FlutterError(
        code: "INVALID_IMAGE",
        message: "Image has no CGImage representation.",
        details: nil
      ))
      return
    }

    let orientation = Self.orientation(image.imageOrientation)
    DispatchQueue.global(qos: .userInitiated).async {
      let request = VNDetectFaceRectanglesRequest()
      let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
      do {
        try handler.perform([request])
        let observations = request.results ?? []
        let faces: [[String: Any]] = observations.map { face in
          let box = face.boundingBox
          // Vision origin is bottom-left; normalize to top-left.
          return [
            "x": box.origin.x,
            "y": 1.0 - box.origin.y - box.height,
            "w": box.width,
            "h": box.height,
            "confidence": face.confidence
          ]
        }
        DispatchQueue.main.async { result(faces) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "VISION_FAILED",
            message: error.localizedDescription,
            details: nil
          ))
        }
      }
    }
  }

  private static func orientation(_ value: UIImage.Orientation) -> CGImagePropertyOrientation {
    switch value {
    case .up: return .up
    case .down: return .down
    case .left: return .left
    case .right: return .right
    case .upMirrored: return .upMirrored
    case .downMirrored: return .downMirrored
    case .leftMirrored: return .leftMirrored
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
  }
}
