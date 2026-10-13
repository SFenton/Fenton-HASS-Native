#if canImport(WebRTC) && canImport(UIKit)
import CoreImage
import Foundation
import HassCore
import SwiftUI
@preconcurrency import WebRTC

// MARK: - Peer

/// One receive-only go2rtc WebRTC session: the signalling websocket plus its peer connection.
///
/// Mirrors the web stream manager (`SFenton/WebRTC` `www/stream-manager.js`): offer receive-only video and
/// audio transceivers (`media: 'video,audio'`), trickle candidates both ways with `sdpMid` `0`, and treat a
/// failed or closed peer as a failure. Runs on WebRTC's and URLSession's own threads; the reports out are
/// `onFirstFrame` and `onFailure`. Audio starts muted (``isMuted``) and plays through ``CameraPlayoutDevice``.
final class WebRTCCameraPeer: NSObject, @unchecked Sendable {
    /// Shared factory; WebRTC's factory is thread-safe and expensive to create.
    nonisolated(unsafe) private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory(),
            audioDevice: CameraPlayoutDevice.shared
        )
    }()

    /// The remote video track, rendered by ``WebRTCVideoView``.
    let videoTrack: RTCVideoTrack?
    /// The remote audio track, if the camera sends audio.
    let audioTrack: RTCAudioTrack?
    /// Watches every decoded frame: reports the first one and keeps the latest for snapshots.
    let frames: WebRTCFrameMonitor

    private let peer: RTCPeerConnection
    private let socket: URLSessionWebSocketTask
    private let onFailure: @Sendable () -> Void
    private let lock = NSLock()
    private var finished = false
    private var remoteDescriptionSet = false
    private var pendingCandidates: [String] = []

    /// Creates the peer; nothing is sent until ``start()``.
    /// - Parameters:
    ///   - socketURL: The signed signalling URL (``CameraStreamEndpoints/webRTCSocketURL(signedPath:streamId:baseURL:)``).
    ///   - onFailure: Called once, on any thread, when the session fails after starting.
    ///   - onFirstFrame: Called once, on WebRTC's decode thread, when the first video frame decodes.
    init?(socketURL: URL, onFirstFrame: @escaping @Sendable () -> Void, onFailure: @escaping @Sendable () -> Void) {
        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        configuration.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        guard let peer = Self.factory.peerConnection(with: configuration, constraints: Self.constraints, delegate: nil) else {
            return nil
        }
        let receiveOnly = RTCRtpTransceiverInit()
        receiveOnly.direction = .recvOnly
        let video = peer.addTransceiver(of: .video, init: receiveOnly)?.receiver.track as? RTCVideoTrack
        let audio = peer.addTransceiver(of: .audio, init: receiveOnly)?.receiver.track as? RTCAudioTrack
        audio?.isEnabled = false
        let monitor = WebRTCFrameMonitor(onFirstFrame: onFirstFrame)
        video?.add(monitor)
        videoTrack = video
        audioTrack = audio
        frames = monitor
        self.peer = peer
        socket = URLSession.shared.webSocketTask(with: socketURL)
        self.onFailure = onFailure
        super.init()
        peer.delegate = self
    }

    private static var constraints: RTCMediaConstraints {
        RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
    }

    /// Whether the camera's audio is silenced (the default).
    var isMuted: Bool {
        get { !(audioTrack?.isEnabled ?? false) }
        set { audioTrack?.isEnabled = !newValue }
    }

    // MARK: - Lifecycle

    /// Opens the socket and sends the offer.
    func start() {
        socket.resume()
        receive()
        peer.offer(for: Self.constraints) { [weak self] description, _ in
            guard let self else { return }
            guard let description else { return self.fail() }
            self.peer.setLocalDescription(description) { error in
                if error != nil { return self.fail() }
                self.send(.offer(description.sdp))
            }
        }
    }

    /// Closes the socket and peer without reporting a failure.
    func stop() {
        guard markFinished() else { return }
        close()
    }

    // MARK: - Signalling

    private func receive() {
        socket.receive { [weak self] result in
            guard let self, !self.isFinished else { return }
            switch result {
            case let .success(.string(text)):
                self.handle(text)
                self.receive()
            case .success:
                self.receive()
            case .failure:
                self.fail()
            }
        }
    }

    private func handle(_ text: String) {
        switch WebRTCSignal(text: text) {
        case let .answer(sdp):
            peer.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: sdp)) { [weak self] error in
                guard let self else { return }
                if error != nil { return self.fail() }
                let queued = self.lock.withLock { () -> [String] in
                    self.remoteDescriptionSet = true
                    return self.drainCandidates()
                }
                queued.forEach(self.addCandidate)
            }
        case let .candidate(line) where !line.isEmpty:
            let ready = lock.withLock {
                if !remoteDescriptionSet { pendingCandidates.append(line) }
                return remoteDescriptionSet
            }
            if ready { addCandidate(line) }
        case .error:
            fail()
        default:
            break
        }
    }

    private func drainCandidates() -> [String] {
        let queued = pendingCandidates
        pendingCandidates = []
        return queued
    }

    private func addCandidate(_ line: String) {
        peer.add(RTCIceCandidate(sdp: line, sdpMLineIndex: 0, sdpMid: "0")) { _ in }
    }

    private func send(_ signal: WebRTCSignal) {
        socket.send(.string(signal.encoded())) { [weak self] error in
            if error != nil { self?.fail() }
        }
    }

    // MARK: - Teardown

    private var isFinished: Bool { lock.withLock { finished } }

    /// Marks the session finished; returns `false` if it already was.
    private func markFinished() -> Bool {
        lock.withLock {
            guard !finished else { return false }
            finished = true
            return true
        }
    }

    private func fail() {
        guard markFinished() else { return }
        close()
        onFailure()
    }

    private func close() {
        videoTrack?.remove(frames)
        socket.cancel(with: .goingAway, reason: nil)
        peer.close()
    }
}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCCameraPeer: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        guard !isFinished else { return }
        send(.candidate(candidate.sdp))
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        if newState == .failed || newState == .closed { fail() }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        if newState == .failed { fail() }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

// MARK: - Frames

/// A hidden renderer on the video track: reports the first decoded frame (so a pooled stream goes live with no
/// view attached) and keeps the latest frame for the camera's snapshot button.
final class WebRTCFrameMonitor: NSObject, RTCVideoRenderer, @unchecked Sendable {
    private let lock = NSLock()
    private var latest: RTCVideoFrame?
    private var reported = false
    private let onFirstFrame: @Sendable () -> Void

    init(onFirstFrame: @escaping @Sendable () -> Void) {
        self.onFirstFrame = onFirstFrame
    }

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        let first = lock.withLock { () -> Bool in
            latest = frame
            defer { reported = true }
            return !reported
        }
        if first { onFirstFrame() }
    }

    /// The latest decoded frame, or `nil` before the first frame.
    func latestFrame() -> RTCVideoFrame? {
        lock.withLock { latest }
    }
}

/// Converts decoded WebRTC frames to images.
enum CameraFrameImage {
    nonisolated static func image(from frame: RTCVideoFrame) -> CGImage? {
        let image: CIImage
        if let buffer = frame.buffer as? RTCCVPixelBuffer {
            image = CIImage(cvPixelBuffer: buffer.pixelBuffer)
        } else if let pixels = pixelBuffer(from: frame.buffer.toI420()) {
            image = CIImage(cvPixelBuffer: pixels)
        } else {
            return nil
        }
        let orientation: CGImagePropertyOrientation = switch frame.rotation {
        case ._90: .right
        case ._180: .down
        case ._270: .left
        default: .up
        }
        let upright = image.oriented(orientation)
        return CameraFrameContext.shared.createCGImage(upright, from: upright.extent)
    }

    /// Copies an I420 frame (software decode) into a bi-planar 4:2:0 pixel buffer Core Image can read.
    nonisolated private static func pixelBuffer(from i420: any RTCI420BufferProtocol) -> CVPixelBuffer? {
        let width = Int(i420.width), height = Int(i420.height)
        var output: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &output)
        guard let output else { return nil }
        CVPixelBufferLockBaseAddress(output, [])
        defer { CVPixelBufferUnlockBaseAddress(output, []) }
        guard let luma = CVPixelBufferGetBaseAddressOfPlane(output, 0)?.assumingMemoryBound(to: UInt8.self),
              let chroma = CVPixelBufferGetBaseAddressOfPlane(output, 1)?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(output, 0)
        let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(output, 1)
        for row in 0..<height {
            memcpy(luma + row * lumaStride, i420.dataY + row * Int(i420.strideY), width)
        }
        let chromaWidth = Int(i420.chromaWidth), chromaHeight = Int(i420.chromaHeight)
        for row in 0..<chromaHeight {
            let u = i420.dataU + row * Int(i420.strideU)
            let v = i420.dataV + row * Int(i420.strideV)
            let line = chroma + row * chromaStride
            for column in 0..<chromaWidth {
                line[2 * column] = u[column]
                line[2 * column + 1] = v[column]
            }
        }
        return output
    }
}

// MARK: - Video view

/// Renders a WebRTC video track (Metal). Several views can show one track (a tile and its viewer).
struct WebRTCVideoView: UIViewRepresentable {
    var track: RTCVideoTrack?
    /// Fill crops to the frame (tiles); fit letterboxes (the viewer).
    var fills = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView()
        view.videoContentMode = fills ? .scaleAspectFill : .scaleAspectFit
        view.clipsToBounds = true
        // Taps go to the SwiftUI button around a tile, not the Metal view.
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        track?.add(view)
        context.coordinator.track = track
        return view
    }

    func updateUIView(_ view: RTCMTLVideoView, context: Context) {
        view.videoContentMode = fills ? .scaleAspectFill : .scaleAspectFit
        guard context.coordinator.track !== track else { return }
        context.coordinator.track?.remove(view)
        track?.add(view)
        context.coordinator.track = track
    }

    static func dismantleUIView(_ view: RTCMTLVideoView, coordinator: Coordinator) {
        coordinator.track?.remove(view)
        coordinator.track = nil
    }

    /// Holds the attached track.
    @MainActor
    final class Coordinator: NSObject {
        var track: RTCVideoTrack?
    }
}
#endif
