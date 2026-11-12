// REFERENCE INTEGRATION — NOT COMPILED IN THE CURRENT TARGET.
//
// Add this file to the Runner target only after:
//   1. CascableCore is added via Swift Package Manager.
//   2. An evaluation/commercial licence is installed.
//   3. Xcode is available to resolve the SDK's Swift signatures.
//
// Cascable's public docs show the concepts below; exact Swift names must be
// validated against the headers shipped in the SDK. Do not ship this file as
// "working" until it compiles and captures a real EOS R image on an iPad.
//
// Public references:
//   https://compatibility.cascable.se/canon/eos-r/
//   https://developer.cascable.se/
//   https://cascable.github.io/
//   https://github.com/cascable/cascablecore-distribution

#if canImport(CascableCore)
import Foundation
import UIKit
import CascableCore

/// Minimal adapter shape for the 11 Nov spike.
/// - Discovery: CBLCameraDiscovery
/// - Connect: camera connect + authentication callbacks
/// - Live view: CBLCameraLiveView / beginLiveViewStream
/// - Shutter: invokeOneShotShutterExplicitlyEngagingAutoFocus
/// - Download: CBLFileStorage / CBLFileSystemItem.streamItem
///
/// The implementation is intentionally left to the integration session so the
/// SDK's exact Swift signatures are taken from the installed headers.
final class CascableCameraAdapter {
    static let shared = CascableCameraAdapter()
    private init() {}

    func connect(completion: @escaping (Result<Void, Error>) -> Void) {
        // Implementation to be completed against the licensed SDK.
        completion(.failure(NSError(
            domain: "TeraboothCamera",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "CascableCore adapter not implemented yet"]
        )))
    }

    func capture(completion: @escaping (Result<Data, Error>) -> Void) {
        completion(.failure(NSError(
            domain: "TeraboothCamera",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "CascableCore capture not implemented yet"]
        )))
    }
}
#endif
