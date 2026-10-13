import HassCore
import Observation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The app's camera streams: one ``CameraLiveModel`` per camera, shared by every tile and viewer (web
/// `stream-manager.js` pooling plus `rtcStreamRetention.ts`).
///
/// A tile and the viewer it opens show the same stream, so the viewer is live the moment it opens. Once a
/// camera has been shown its stream keeps running for the session (``CameraStreamRetention``), so moving
/// between Home, Security and the viewer never reconnects. Every stream stops when the app goes to the
/// background and the retained ones restart when it returns; their snapshots cover the gap.
@MainActor
@Observable
final class CameraStreamPool {
    /// The app's pool.
    static let shared = CameraStreamPool()

    @ObservationIgnored private var models: [String: CameraLiveModel] = [:]
    @ObservationIgnored private var retention: CameraStreamRetention
    @ObservationIgnored private weak var connection: HassConnection?
    @ObservationIgnored private let modes: [CameraStreamMode]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// - Parameters:
    ///   - modes: Modes each stream tries, in order.
    ///   - retainsShownStreams: Keep shown streams running for the session (web parity).
    ///   - observesApp: Stop and restart streams with the app's background and foreground transitions.
    init(modes: [CameraStreamMode] = CameraLiveModel.defaultModes, retainsShownStreams: Bool = true, observesApp: Bool = true) {
        self.modes = modes
        retention = CameraStreamRetention(retainsShownStreams: retainsShownStreams)
        #if canImport(UIKit)
        guard observesApp else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.enterBackground() }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.enterForeground() }
            },
        ]
        #endif
    }

    // MARK: - Models

    /// The shared model for a camera, created on first use (not started).
    func model(for camera: HomeConfig.Camera) -> CameraLiveModel {
        if let model = models[camera.id] { return model }
        let model = CameraLiveModel(camera: camera, modes: modes)
        model.onExhausted = { [weak self] in self?.retention.failed(camera.id) }
        model.onMuteChange = { [weak self] in self?.updateAudio() }
        models[camera.id] = model
        return model
    }

    /// Whether the camera's stream should be running now (tests and diagnostics).
    func shouldRun(_ camera: HomeConfig.Camera) -> Bool { retention.shouldRun(camera.id) }

    // MARK: - Views

    /// A view showing the camera appeared: starts its stream unless it is already connecting or live.
    @discardableResult
    func appear(_ camera: HomeConfig.Camera, connection: HassConnection) -> CameraLiveModel {
        self.connection = connection
        let model = model(for: camera)
        if retention.appear(camera.id, isRunning: model.isRunning) == .start {
            model.start(connection: connection)
        }
        return model
    }

    /// A view showing the camera disappeared: stops its stream only if nothing retains it.
    func disappear(_ camera: HomeConfig.Camera) {
        if retention.disappear(camera.id) == .stop {
            models[camera.id]?.stop()
        }
    }

    /// Restarts a camera whose modes all failed (the viewer's retry).
    func retry(_ camera: HomeConfig.Camera, connection: HassConnection) {
        self.connection = connection
        model(for: camera).start(connection: connection)
    }

    // MARK: - App lifecycle

    func enterBackground() {
        for id in retention.enterBackground() {
            models[id]?.stop()
        }
        // Sound never keeps playing behind the app; cameras reopen muted like the web's pooled cards.
        models.values.forEach { $0.setMuted(true) }
    }

    func enterForeground() {
        let ids = retention.enterForeground()
        guard let connection else { return }
        for id in ids {
            models[id]?.start(connection: connection)
        }
    }

    // MARK: - Audio

    private func updateAudio() {
        #if canImport(UIKit)
        CameraAudioSession.shared.setAudible(models.values.contains { !$0.isMuted })
        #endif
    }
}

// MARK: - Environment

extension EnvironmentValues {
    /// A camera stream pool to use instead of ``CameraStreamPool/shared`` (hosted tests).
    @Entry var cameraStreamPool: CameraStreamPool?
}
