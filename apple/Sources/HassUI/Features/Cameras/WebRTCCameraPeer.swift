#if canImport(WebRTC) && canImport(UIKit)
import Foundation
import HassCore
import SwiftUI
@preconcurrency import WebRTC

// MARK: - Peer

/// One receive-only go2rtc WebRTC session: the signalling websocket plus its peer connection.
///
/// Mirrors the web stream manager (`SFenton/WebRTC` `www/stream-manager.js`): offer a video
/// transceiver, trickle candidates both ways with `sdpMid` `0`, and treat a failed or closed peer as a
/// failure. Runs on WebRTC's and URLSession's own threads; the only report out is `onFailure`.
final class WebRTCCameraPeer: NSObject, @unchecked Sendable {
    /// Shared factory; WebRTC's factory is thread-safe and expensive to create.
    nonisolated(unsafe) private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
    }()

    /// The remote video track, rendered by ``WebRTCVideoView``.
    let videoTrack: RTCVideoTrack?

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
    init?(socketURL: URL, onFailure: @escaping @Sendable () -> Void) {
        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        configuration.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        guard let peer = Self.factory.peerConnection(with: configuration, constraints: Self.constraints, delegate: nil) else {
            return nil
        }
        let receiveOnly = RTCRtpTransceiverInit()
        receiveOnly.direction = .recvOnly
        videoTrack = peer.addTransceiver(of: .video, init: receiveOnly)?.receiver.track as? RTCVideoTrack
        self.peer = peer
        socket = URLSession.shared.webSocketTask(with: socketURL)
        self.onFailure = onFailure
        super.init()
        peer.delegate = self
    }

    private static var constraints: RTCMediaConstraints {
        RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
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

// MARK: - Video view

/// Renders a WebRTC video track (Metal) and reports its first decoded frame.
struct WebRTCVideoView: UIViewRepresentable {
    var track: RTCVideoTrack?
    var onFirstFrame: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFirstFrame: onFirstFrame) }

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView()
        view.videoContentMode = .scaleAspectFit
        view.delegate = context.coordinator
        view.isAccessibilityElement = false
        track?.add(view)
        context.coordinator.track = track
        return view
    }

    func updateUIView(_ view: RTCMTLVideoView, context: Context) {
        context.coordinator.onFirstFrame = onFirstFrame
        guard context.coordinator.track !== track else { return }
        context.coordinator.track?.remove(view)
        track?.add(view)
        context.coordinator.track = track
    }

    static func dismantleUIView(_ view: RTCMTLVideoView, coordinator: Coordinator) {
        coordinator.track?.remove(view)
        coordinator.track = nil
    }

    /// Holds the attached track and forwards the first size change (the first decoded frame).
    @MainActor
    final class Coordinator: NSObject {
        var onFirstFrame: () -> Void
        var track: RTCVideoTrack?

        init(onFirstFrame: @escaping () -> Void) { self.onFirstFrame = onFirstFrame }
    }
}

// `RTCMTLVideoView` reports size changes on the main queue.
extension WebRTCVideoView.Coordinator: @preconcurrency RTCVideoViewDelegate {
    func videoView(_ videoView: any RTCVideoRenderer, didChangeVideoSize size: CGSize) {
        if size.width > 0, size.height > 0 { onFirstFrame() }
    }
}
#endif
