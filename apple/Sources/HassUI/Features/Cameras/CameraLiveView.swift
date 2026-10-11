import AVFoundation
import HassCore
import HassDesign
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WebRTC) && canImport(UIKit)
import WebRTC
#endif

/// Live video for one camera, over its latest snapshot.
///
/// The snapshot stays on top until the stream shows a frame, then cross-fades out; if every mode fails it
/// stays with a retry. Streams stop when the view leaves or the app goes to the background and restart on
/// return. With `FENTON_REDACT_PRIVATE` the blurred snapshot always covers the video, so shared screenshots
/// show the live badge but never the picture.
struct CameraLiveView: View {
    var camera: HomeConfig.Camera
    @Environment(HassConnection.self) private var connection
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: CameraLiveModel
    @State private var pausedInBackground = false

    init(camera: HomeConfig.Camera) {
        self.camera = camera
        _model = State(initialValue: CameraLiveModel(camera: camera))
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.black)
            player
            if model.state.phase != .live || ScreenshotPrivacy.isRedacting {
                CameraSnapshotView(entityId: camera.entityId)
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(camera.title) camera")
        .accessibilityValue(Self.statusText(model.state))
        .accessibilityIdentifier("camera.viewer.video")
        .overlay(alignment: .topLeading) { badge }
        .overlay(alignment: .bottom) { retry }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: model.state.phase)
        .onAppear { model.start(connection: connection) }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active where pausedInBackground:
                pausedInBackground = false
                model.start(connection: connection)
            case .background:
                pausedInBackground = true
                model.stop()
            default: break
            }
        }
    }

    // MARK: - Pieces

    @ViewBuilder private var player: some View {
        #if canImport(UIKit)
        if let hls = model.hlsPlayer {
            HLSPlayerView(player: hls)
        }
        #if canImport(WebRTC)
        if let peer = model.webRTCPeer {
            WebRTCVideoView(track: peer.videoTrack) { model.firstFrame(.webRTC) }
        }
        #endif
        #endif
    }

    private var badge: some View {
        HStack(spacing: HassTokens.Spacing.xs) {
            switch model.state.phase {
            case .connecting:
                ProgressView().controlSize(.mini).tint(.white)
            case .live:
                Circle().fill(.red).frame(width: 8, height: 8)
            case .failed:
                Image(systemName: "photo")
            }
            Text(Self.badgeText(model.state))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, HassTokens.Spacing.s)
        .padding(.vertical, HassTokens.Spacing.xs)
        .background(.black.opacity(0.75), in: Capsule())
        .padding(HassTokens.Spacing.s)
        .accessibilityHidden(true) // Read as the video's value.
    }

    @ViewBuilder private var retry: some View {
        if model.state.phase == .failed, !model.state.modes.isEmpty {
            Button {
                model.start(connection: connection)
            } label: {
                Label("Retry Live Video", systemImage: "arrow.clockwise")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .padding(HassTokens.Spacing.s)
            .accessibilityIdentifier("camera.viewer.retry")
        }
    }

    // MARK: - Text

    /// The short badge text.
    static func badgeText(_ state: CameraStreamState) -> String {
        switch state.phase {
        case .connecting: "Connecting"
        case .live: state.mode == .hls ? "Live · Delayed" : "Live"
        case .failed: "Snapshot"
        }
    }

    /// The VoiceOver value for the video.
    static func statusText(_ state: CameraStreamState) -> String {
        switch state.phase {
        case .connecting: "Connecting to live video"
        case .live: state.mode == .hls ? "Live, a few seconds behind" : "Live"
        case .failed: state.modes.isEmpty ? "Latest snapshot" : "Live video unavailable, showing the latest snapshot"
        }
    }
}

#if canImport(UIKit)
/// An `AVPlayerLayer` host with no controls (live HLS has nothing to scrub).
struct HLSPlayerView: UIViewRepresentable {
    var player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    /// A view backed by `AVPlayerLayer`.
    final class PlayerLayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer } // swiftlint:disable:this force_cast
    }
}
#endif
