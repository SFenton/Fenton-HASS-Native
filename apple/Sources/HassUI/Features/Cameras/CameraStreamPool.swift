import HassCore
import HassTelemetry
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
///
/// **Coming back from the background** the websocket may be gone or dead, and Home Assistant's commands for a
/// stream (`auth/sign_path`, `camera/stream`) are dropped by HAKit without an answer when they are caught by a
/// reconnect (owner report 2026-10-16: streams never came back). So the return first makes the connection
/// answer (``HassConnection/ensureLive(timeout:)``), then starts the streams, and any stream that is still
/// wanted but not running, or gave up while the socket was down, restarts when the socket next becomes ready.
/// A healthy stream is never touched. See `.agents/platforms/apple/connection-lifecycle.md`, "Camera streams".
@MainActor
@Observable
final class CameraStreamPool {
    /// The app's pool.
    static let shared = CameraStreamPool()

    @ObservationIgnored private var models: [String: CameraLiveModel] = [:]
    @ObservationIgnored private var retention: CameraStreamRetention
    @ObservationIgnored private weak var connection: HassConnection?
    @ObservationIgnored private let modes: [CameraStreamMode]
    @ObservationIgnored private let opener: CameraStreamOpener?
    @ObservationIgnored private let prepareConnection: @MainActor (HassConnection) async -> Void
    // Read in `deinit`, which is nonisolated; only the main actor writes it.
    @ObservationIgnored nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var census: ResourceCensus.Registration?
    /// The foreground restart while it waits for the connection; nil when none is pending.
    @ObservationIgnored private var resumeTask: Task<Void, Never>?

    /// - Parameters:
    ///   - modes: Modes each stream tries, in order.
    ///   - retainsShownStreams: Keep shown streams running for the session (web parity).
    ///   - observesApp: Stop and restart streams with the app's background and foreground transitions, and
    ///     restart stalled ones when the connection becomes ready again.
    ///   - opener: Replaces how each mode opens its stream (tests).
    ///   - prepareConnection: Runs when the app returns, before streams restart; the default makes the websocket
    ///     answer, reconnecting it if it is dead.
    init(modes: [CameraStreamMode] = CameraLiveModel.defaultModes, retainsShownStreams: Bool = true, observesApp: Bool = true,
         opener: CameraStreamOpener? = nil,
         prepareConnection: @escaping @MainActor (HassConnection) async -> Void = { _ = await $0.ensureLive() }) {
        self.modes = modes
        self.opener = opener
        self.prepareConnection = prepareConnection
        retention = CameraStreamRetention(retainsShownStreams: retainsShownStreams)
        census = ResourceCensus.shared.register { [weak self] in self?.liveResources ?? [:] }
        guard observesApp else { return }
        let center = NotificationCenter.default
        #if canImport(UIKit)
        observers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.enterBackground() }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.enterForeground() }
            },
        ]
        #endif
        observers.append(center.addObserver(forName: HassConnection.didBecomeReadyNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.connectionBecameReady() }
        })
    }

    /// What the pool holds right now (`ResourceCensus`).
    var liveResources: [String: Int] {
        [
            "CameraPool.observers": observers.count,
            "CameraPool.resumeTask": resumeTask == nil ? 0 : 1,
            "CameraPool.models": models.count,
            "CameraPool.running": models.values.filter(\.isRunning).count,
        ]
    }

    deinit {
        // Block observers stay registered until removed; dropping the tokens would leave them behind.
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Models

    /// The shared model for a camera, created on first use (not started).
    ///
    /// A memoizing lookup: views call it from `body`, and since the cache is not observed, filling it never
    /// invalidates a view. Views observe the returned model's own state.
    func model(for camera: HomeConfig.Camera) -> CameraLiveModel {
        if let model = models[camera.id] { return model }
        let model = CameraLiveModel(camera: camera, modes: modes, opener: opener)
        model.onExhausted = { [weak self] in self?.retention.failed(camera.id) }
        model.onMuteChange = { [weak self] in self?.updateAudio() }
        models[camera.id] = model
        return model
    }

    /// Whether the camera's stream should be running now (tests and diagnostics).
    func shouldRun(_ camera: HomeConfig.Camera) -> Bool { retention.shouldRun(camera.id) }

    // MARK: - Views

    /// A view showing the camera appeared: starts its stream unless it is already connecting or live.
    ///
    /// While the app is coming back from the background the start waits for the connection check with the rest
    /// (``enterForeground()``).
    @discardableResult
    func appear(_ camera: HomeConfig.Camera, connection: HassConnection) -> CameraLiveModel {
        self.connection = connection
        let model = model(for: camera)
        if retention.appear(camera.id, isRunning: model.isRunning) == .start, resumeTask == nil {
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
        retention.retry(camera.id)
        model(for: camera).start(connection: connection)
    }

    // MARK: - App lifecycle

    func enterBackground() {
        CameraTrace.record("pool background, \(models.values.filter(\.isRunning).count) running")
        resumeTask?.cancel()
        resumeTask = nil
        for id in retention.enterBackground() {
            models[id]?.suspend()
        }
        // Sound never keeps playing behind the app; cameras reopen muted like the web's pooled cards.
        models.values.forEach { $0.setMuted(true) }
    }

    /// The app is returning. Streams restart once the connection answers; the snapshots stay up meanwhile.
    func enterForeground() {
        let ids = retention.enterForeground()
        guard let connection, !ids.isEmpty else { return }
        CameraTrace.record("pool foreground, \(ids.count) wanted, connection \(connection.status)")
        resumeTask?.cancel()
        resumeTask = Task { [weak self] in
            if let self { await prepareConnection(connection) }
            guard !Task.isCancelled, let self else { return }
            resumeTask = nil
            CameraTrace.record("pool resuming, connection \(connection.status)")
            startStalled(connection)
        }
    }

    /// The websocket became ready (first connect, or after a drop). Streams that are wanted but not running, or
    /// that gave up while the socket was down, start again; connecting and live ones are left alone.
    func connectionBecameReady() {
        guard resumeTask == nil, let connection else { return }
        startStalled(connection)
    }

    /// Starts every wanted stream that is not running or has failed.
    private func startStalled(_ connection: HassConnection) {
        for id in retention.wanted {
            guard let model = models[id], !model.isRunning || model.state.phase == .failed else { continue }
            CameraTrace.record("\(model.camera.rtcStreamId) restarting (running \(model.isRunning), \(model.state.phase))")
            model.start(connection: connection)
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
