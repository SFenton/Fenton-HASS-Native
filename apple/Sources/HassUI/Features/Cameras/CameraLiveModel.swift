import AVFoundation
import CoreImage
import Foundation
import QuartzCore
import HassCore
import Observation
#if canImport(WebRTC) && canImport(UIKit)
import WebRTC
#endif

/// Drives live video for one camera: WebRTC first, HLS if that fails, the snapshot if both do.
///
/// One model per camera is shared by every tile and viewer through ``CameraStreamPool``, so a viewer opened
/// from a tile shows the frames the tile is already playing. Each attempt gets its mode's
/// ``CameraStreamMode/firstFrameTimeout`` to show a frame before the next mode is tried. Views keep the
/// snapshot up until ``state`` is live, so nothing blanks while streams connect or fall back.
@MainActor
@Observable
final class CameraLiveModel {
    // MARK: - State

    /// Mode and phase (connecting, live, failed).
    private(set) var state: CameraStreamState
    /// The HLS player while HLS is the current mode.
    private(set) var hlsPlayer: AVPlayer?
    #if canImport(WebRTC) && canImport(UIKit)
    /// The WebRTC session while WebRTC is the current mode.
    private(set) var webRTCPeer: WebRTCCameraPeer?
    #endif

    /// Whether the camera's sound is off (the default; web cameras open muted).
    private(set) var isMuted = true
    /// Whether a stream is connecting or playing (``start(connection:)`` ran and ``stop()`` has not).
    private(set) var isRunning = false

    let camera: HomeConfig.Camera
    /// Called when every mode failed, so the pool can drop the stream's retention.
    @ObservationIgnored var onExhausted: (() -> Void)?
    /// Called when ``isMuted`` changes, so the pool can update the app's audio session.
    @ObservationIgnored var onMuteChange: (() -> Void)?
    @ObservationIgnored private var hlsVideoOutput: AVPlayerItemVideoOutput?

    @ObservationIgnored private weak var connection: HassConnection?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var attempt: Task<Void, Never>?
    /// KVO on the HLS item and player. (Combine's `publisher(for:).values` delivered only the initial
    /// values here, so a playing stream never reported its first frame.)
    @ObservationIgnored private var hlsObservations: [NSKeyValueObservation] = []

    // MARK: - Init

    /// - Parameters:
    ///   - camera: The camera to stream.
    ///   - modes: Modes to try in order; defaults to ``defaultModes``.
    init(camera: HomeConfig.Camera, modes: [CameraStreamMode] = CameraLiveModel.defaultModes) {
        self.camera = camera
        state = CameraStreamState(modes: modes)
    }

    /// WebRTC then HLS on iOS. macOS (hosted tests) has no player views, so no live modes.
    /// Debug builds honor `FENTON_CAMERA_MODE=webrtc|hls` to pin one mode for tests.
    static var defaultModes: [CameraStreamMode] {
        #if canImport(UIKit)
        #if DEBUG
        if let pinned = ProcessInfo.processInfo.environment["FENTON_CAMERA_MODE"],
           let mode = CameraStreamMode.allCases.first(where: { $0.rawValue.lowercased() == pinned.lowercased() }) {
            return [mode]
        }
        #endif
        #if canImport(WebRTC)
        return [.webRTC, .hls]
        #else
        return [.hls]
        #endif
        #else
        return []
        #endif
    }

    // MARK: - Lifecycle

    /// Starts (or restarts) from the first mode.
    func start(connection: HassConnection) {
        self.connection = connection
        stop()
        state.restart()
        isRunning = state.phase != .failed
        connectCurrentMode()
    }

    /// Stops every stream. The state keeps its phase so a paused view still reads correctly.
    func stop() {
        generation += 1
        attempt?.cancel()
        attempt = nil
        isRunning = false
        tearDownPlayers()
    }

    // MARK: - Controls

    /// Turns the camera's sound on or off (web `toggleCameraStreamMuted`).
    func setMuted(_ muted: Bool) {
        guard muted != isMuted else { return }
        isMuted = muted
        applyMute()
        onMuteChange?()
    }

    /// The current live frame as an image (web `webrtc-screenshot`), or `nil` while nothing is playing.
    func liveFrame() -> CGImage? {
        #if canImport(WebRTC) && canImport(UIKit)
        if let frame = webRTCPeer?.frames.snapshot() { return frame }
        #endif
        guard let player = hlsPlayer, let output = hlsVideoOutput else { return nil }
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        let current = output.hasNewPixelBuffer(forItemTime: time) ? time : player.currentTime()
        guard let pixels = output.copyPixelBuffer(forItemTime: current, itemTimeForDisplay: nil) else { return nil }
        let image = CIImage(cvPixelBuffer: pixels)
        return CIContext().createCGImage(image, from: image.extent)
    }

    private func applyMute() {
        hlsPlayer?.isMuted = isMuted
        #if canImport(WebRTC) && canImport(UIKit)
        webRTCPeer?.isMuted = isMuted
        #endif
    }

    /// A player showed its first frame.
    func firstFrame(_ mode: CameraStreamMode) {
        guard mode == state.mode, state.phase == .connecting else { return }
        state.firstFrame(mode)
        attempt?.cancel()
        attempt = nil
    }

    // MARK: - Attempts

    private func connectCurrentMode() {
        guard let mode = state.mode, let connection else { return }
        generation += 1
        let current = generation
        tearDownPlayers()
        attempt = Task { [weak self] in
            do {
                switch mode {
                case .hls: try await self?.openHLS(connection, generation: current)
                case .webRTC: try await self?.openWebRTC(connection, generation: current)
                }
                try await Task.sleep(for: mode.firstFrameTimeout)
                self?.modeFailed(mode, generation: current)
            } catch is CancellationError {
            } catch {
                self?.modeFailed(mode, generation: current)
            }
        }
    }

    private func modeFailed(_ mode: CameraStreamMode, generation failed: Int) {
        guard failed == generation, mode == state.mode else { return }
        attempt?.cancel()
        attempt = nil
        state.failed(mode)
        tearDownPlayers()
        if state.phase == .failed {
            isRunning = false
            onExhausted?()
        }
        connectCurrentMode()
    }

    private func openHLS(_ connection: HassConnection, generation current: Int) async throws {
        let path = try await connection.cameraStreamPath(entityId: camera.entityId)
        guard current == generation else { throw CancellationError() }
        guard let url = CameraStreamEndpoints.hlsURL(path: path, baseURL: connection.server.baseURL) else {
            throw URLError(.badURL)
        }
        let item = AVPlayerItem(url: url)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(output)
        hlsVideoOutput = output
        let player = AVPlayer(playerItem: item)
        player.isMuted = isMuted
        player.preventsDisplaySleepDuringVideoPlayback = false
        hlsPlayer = player
        hlsObservations = [
            item.observe(\.status) { @Sendable [weak self] item, _ in
                guard item.status == .failed else { return }
                Task { @MainActor in self?.modeFailed(.hls, generation: current) }
            },
            player.observe(\.timeControlStatus) { @Sendable [weak self] player, _ in
                guard player.timeControlStatus == .playing else { return }
                Task { @MainActor in self?.firstFrame(.hls) }
            },
        ]
        player.play()
    }

    private func openWebRTC(_ connection: HassConnection, generation current: Int) async throws {
        #if canImport(WebRTC) && canImport(UIKit)
        let signed = try await connection.signPath(CameraStreamEndpoints.webRTCSocketPath)
        guard current == generation else { throw CancellationError() }
        guard let url = CameraStreamEndpoints.webRTCSocketURL(
            signedPath: signed,
            streamId: camera.rtcStreamId,
            baseURL: connection.server.baseURL
        ) else { throw URLError(.badURL) }
        let peer = WebRTCCameraPeer(socketURL: url) { [weak self] in
            Task { @MainActor in
                guard current == self?.generation else { return }
                self?.firstFrame(.webRTC)
            }
        } onFailure: { [weak self] in
            Task { @MainActor in self?.modeFailed(.webRTC, generation: current) }
        }
        guard let peer else { throw URLError(.cannotConnectToHost) }
        peer.isMuted = isMuted
        webRTCPeer = peer
        peer.start()
        #else
        throw URLError(.unsupportedURL)
        #endif
    }

    private func tearDownPlayers() {
        hlsObservations.forEach { $0.invalidate() }
        hlsObservations = []
        hlsPlayer?.pause()
        hlsPlayer = nil
        hlsVideoOutput = nil
        #if canImport(WebRTC) && canImport(UIKit)
        webRTCPeer?.stop()
        webRTCPeer = nil
        #endif
    }
}
