#if CASCABLE_DEMO
import Foundation
import UIKit
import CascableCore

/// Development-only, no-shutter physical preflight for the licensed demo build.
///
/// Nothing starts at launch. The operator opens the floating "Camera preflight"
/// panel and explicitly chooses discovery, connection, read-only diagnostics,
/// optional Live View, stop and disconnect. This probe never requests a shutter,
/// capture or transfer, never registers a transfer handler and never enables the
/// simulated camera plugin.
final class CascableCoreDemoProbe: NSObject, CameraDiscoveryDelegate {
    static let shared = CascableCoreDemoProbe()

    private let discovery = CameraDiscovery.sharedInstance()
    private var camera: Camera?
    private var discoveredCamera: Camera?
    private var liveViewCamera: CameraLiveView?
    private var liveViewActive = false
    private var licenseApplied = false
    private var entryButton: UIButton?

    var onUpdate: ((String) -> Void)?

    private override init() {
        super.init()
    }

    /// Called at launch. It only records licence state and installs a button;
    /// it deliberately does NOT begin discovery, connect, or start Live View.
    func prepare(licenseApplied: Bool) {
        self.licenseApplied = licenseApplied
        log("CASCABLE_PREFLIGHT_LICENSE=\(licenseApplied ? "applied" : "blocked")")
        log("CASCABLE_PREFLIGHT_PLUGINS=\(discovery.loadedPluginIdentifiers.sorted())")
        installEntryPoint()
    }

    // MARK: - Explicit user actions

    func startDiscovery() {
        guard licenseApplied else {
            log("CASCABLE_PREFLIGHT_DISCOVERY=blocked_missing_license")
            return
        }
        guard discoveredCamera == nil else {
            log("CASCABLE_PREFLIGHT_DISCOVERY=already_have_camera")
            return
        }
        discovery.discoveryMode = .usbOnly
        // Ensure the simulated plugin cannot be selected by this preflight.
        discovery.setEnabled(false, forPluginWithIdentifier: "se.cascable.CascableCore.plugin.simulated-camera")
        discovery.clientName = "Terabooth USB Preflight"
        discovery.delegate = self
        discovery.beginSearching()
        log("CASCABLE_PREFLIGHT_DISCOVERY=started usbOnly simulated=false")
    }

    func connect() {
        guard licenseApplied else {
            log("CASCABLE_PREFLIGHT_CONNECT=blocked_missing_license")
            return
        }
        guard let camera = discoveredCamera else {
            log("CASCABLE_PREFLIGHT_CONNECT=no_discovered_camera")
            return
        }
        guard !camera.connected else {
            self.camera = camera
            log("CASCABLE_PREFLIGHT_CONNECT=already_connected")
            return
        }
        log("CASCABLE_PREFLIGHT_CONNECT=requested")
        camera.connect(authenticationRequestCallback: { context in
            // No credentials are guessed. EOS USB normally needs no auth.
            NSLog("CASCABLE_PREFLIGHT_AUTH=requested type=\(String(describing: context.type))")
            context.submitCancellation()
        }, authenticationResolvedCallback: {
            NSLog("CASCABLE_PREFLIGHT_AUTH=resolved")
        }, completionCallback: { [weak self] error, warnings in
            guard let self else { return }
            if let error {
                self.log("CASCABLE_PREFLIGHT_CONNECT=failed \(error.localizedDescription)")
                return
            }
            self.camera = camera
            let warningText = (warnings ?? []).map { String(describing: $0) }.joined(separator: "; ")
            self.log("CASCABLE_PREFLIGHT_CONNECT=connected warnings=\(warnings?.count ?? 0) state=\(String(describing: camera.connectionState))")
            if !warningText.isEmpty {
                self.log("CASCABLE_PREFLIGHT_WARNINGS=\(warningText)")
            }
        })
    }

    func readPropertiesAndStorage() {
        guard let camera, camera.connected else {
            log("CASCABLE_PREFLIGHT_PROPERTIES=not_connected")
            return
        }
        let ids = camera.knownPropertyIdentifiers
        log("CASCABLE_PREFLIGHT_PROPERTIES=count \(ids.count)")
        let shots = camera.property(with: PropertyIdentifier.shotsAvailable)
        log("CASCABLE_PREFLIGHT_SHOTS=\(shots.currentValue?.localizedDisplayValue ?? "nil")")
        let storage = camera.storageDevices ?? []
        log("CASCABLE_PREFLIGHT_STORAGE=devices \(storage.count)")
        for (index, item) in storage.enumerated() {
            log("CASCABLE_PREFLIGHT_STORAGE_\(index)=name \(item.displayName ?? "unknown") capacity \(item.capacity) available \(item.availableSpace)")
        }
    }

    func startLiveView() {
        guard let camera, camera.connected else {
            log("CASCABLE_PREFLIGHT_LIVE_VIEW=not_connected")
            return
        }
        guard liveViewActive == false else {
            log("CASCABLE_PREFLIGHT_LIVE_VIEW=already_started")
            return
        }
        guard let liveView = camera as? CameraLiveView else {
            log("CASCABLE_PREFLIGHT_LIVE_VIEW=unsupported")
            return
        }
        liveViewCamera = liveView
        liveViewActive = true
        let delivery: LiveViewFrameDelivery = { [weak self] frame, ready in
            guard let self else { ready(); return }
            self.log("CASCABLE_PREFLIGHT_LIVE_VIEW=frame size=\(frame.naturalImageSize)")
            ready()
        }
        liveView.beginStream(delivery: delivery, deliveryQueue: nil, terminationHandler: { [weak self] reason, error in
            self?.liveViewActive = false
            self?.liveViewCamera = nil
            self?.log("CASCABLE_PREFLIGHT_LIVE_VIEW=terminated reason=\(reason.rawValue) error=\(error?.localizedDescription ?? "none")")
        })
        log("CASCABLE_PREFLIGHT_LIVE_VIEW=started")
    }

    func stopLiveView() {
        guard liveViewActive, let liveViewCamera else {
            log("CASCABLE_PREFLIGHT_LIVE_VIEW=not_running")
            return
        }
        liveViewCamera.endStream()
        liveViewActive = false
        self.liveViewCamera = nil
        log("CASCABLE_PREFLIGHT_LIVE_VIEW=stop_requested")
    }

    func disconnect() {
        stopLiveView()
        guard let camera else {
            log("CASCABLE_PREFLIGHT_DISCONNECT=not_connected")
            return
        }
        log("CASCABLE_PREFLIGHT_DISCONNECT=requested")
        camera.disconnect({ [weak self] error in
            self?.camera = nil
            self?.log("CASCABLE_PREFLIGHT_DISCONNECT=\(error == nil ? "complete" : "failed") error=\(error?.localizedDescription ?? "none")")
        }, callbackQueue: nil)
    }

    // MARK: - Discovery delegate

    func discovery(_ discovery: CameraDiscovery, didDiscover camera: Camera) {
        discoveredCamera = camera
        discovery.stopSearching()
        log("CASCABLE_PREFLIGHT_DISCOVERED=model \(camera.service.model ?? "unknown") transport \(String(describing: camera.cameraTransport))")
    }

    func discovery(_ discovery: CameraDiscovery, didLoseSightOf camera: Camera) {
        if discoveredCamera === camera {
            discoveredCamera = nil
        }
        log("CASCABLE_PREFLIGHT_LOST_SIGHT=\(camera.service.model ?? "unknown")")
    }

    // MARK: - UI

    private func installEntryPoint() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) else { return }
            let button = UIButton(type: .system)
            button.setTitle("Camera preflight", for: .normal)
            button.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.92)
            button.setTitleColor(.label, for: .normal)
            button.layer.cornerRadius = 10
            button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addTarget(self, action: #selector(showPreflight), for: .touchUpInside)
            window.addSubview(button)
            NSLayoutConstraint.activate([
                button.trailingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.trailingAnchor, constant: -16),
                button.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -16)
            ])
            self.entryButton = button
        }
    }

    @objc private func showPreflight() {
        guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }),
              let root = window.rootViewController else { return }
        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        let controller = CascablePreflightViewController(probe: self)
        controller.modalPresentationStyle = .formSheet
        presenter.present(controller, animated: true)
    }

    private func log(_ message: String) {
        NSLog("%@", message)
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(message)
        }
    }
}

private final class CascablePreflightViewController: UIViewController {
    private weak var probe: CascableCoreDemoProbe?
    private let logView = UITextView()

    init(probe: CascableCoreDemoProbe) {
        self.probe = probe
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Terabooth camera preflight"
        view.backgroundColor = .systemBackground
        logView.isEditable = false
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.translatesAutoresizingMaskIntoConstraints = false
        logView.text = "USB-only preflight. No shutter, capture or transfer.\\n"

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        for title in ["1. USB discovery", "2. Connect", "3. Properties / storage", "Optional: start Live View", "Stop Live View", "Disconnect", "Close"] {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.contentHorizontalAlignment = .leading
            button.addTarget(self, action: #selector(actionTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
        }

        view.addSubview(logView)
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            logView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            logView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            logView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            logView.heightAnchor.constraint(equalToConstant: 220),
            stack.leadingAnchor.constraint(equalTo: logView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: logView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: logView.bottomAnchor, constant: 12)
        ])

        probe?.onUpdate = { [weak self] message in
            guard let self else { return }
            self.logView.text += message + "\\n"
            let end = NSRange(location: self.logView.text.count, length: 0)
            self.logView.scrollRangeToVisible(end)
        }
    }

    @objc private func actionTapped(_ sender: UIButton) {
        switch sender.title(for: .normal) {
        case "1. USB discovery": probe?.startDiscovery()
        case "2. Connect": probe?.connect()
        case "3. Properties / storage": probe?.readPropertiesAndStorage()
        case "Optional: start Live View": probe?.startLiveView()
        case "Stop Live View": probe?.stopLiveView()
        case "Disconnect": probe?.disconnect()
        case "Close": dismiss(animated: true)
        default: break
        }
    }
}
#endif
