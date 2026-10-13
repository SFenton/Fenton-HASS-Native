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
/// The stream comes from ``CameraStreamPool``, so a tile and the viewer it opens show the same frames. The
/// snapshot stays on top until the stream shows a frame, then cross-fades out; if every mode fails it stays
/// (with a retry in the viewer). With `FENTON_REDACT_PRIVATE` the blurred snapshot always covers the video,
/// so shared screenshots show the live badge but never the picture.
struct CameraLiveView: View {
    /// Where the video is shown.
    enum Style {
        /// A grid tile: fills and crops, no badge, not hit-testable (the tile's button takes the tap).
        case tile
        /// The camera viewer: fits, with the status badge and a retry.
        case viewer
    }

    var camera: HomeConfig.Camera
    var style: Style = .viewer
    @Environment(HassConnection.self) private var connection
    @Environment(\.cameraStreamPool) private var poolOverride
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pool: CameraStreamPool { poolOverride ?? .shared }

    var body: some View {
        let model = pool.model(for: camera)
        // The black frame sets the size; the fill-scaled snapshot must not grow it past the frame, or the
        // badge lands outside the clip and the overflow steals taps from neighbouring tiles.
        Rectangle().fill(.black)
            .overlay {
                // Redacted runs keep the player decoding (so the state still reaches Live) but never show
                // it: the Metal video view can draw above the snapshot that covers it.
                player(model).opacity(ScreenshotPrivacy.isRedacting ? 0 : 1)
            }
            .overlay {
                if model.state.phase != .live || ScreenshotPrivacy.isRedacting {
                    CameraSnapshotView(entityId: camera.entityId)
                        .transition(.opacity)
                }
            }
            .clipped()
            .allowsHitTesting(false)
            .modifier(VideoAccessibility(style: style, camera: camera, state: model.state))
            .overlay(alignment: .topLeading) {
                if style == .viewer { badge(model.state) }
            }
            .overlay(alignment: .bottom) {
                if style == .viewer { retry(model.state) }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: model.state.phase)
            .onAppear { pool.appear(camera, connection: connection) }
            .onDisappear { pool.disappear(camera) }
    }

    // MARK: - Pieces

    @ViewBuilder private func player(_ model: CameraLiveModel) -> some View {
        #if canImport(UIKit)
        if let hls = model.hlsPlayer {
            HLSPlayerView(player: hls, fills: style == .tile)
        }
        #if canImport(WebRTC)
        if let peer = model.webRTCPeer {
            WebRTCVideoView(track: peer.videoTrack, fills: style == .tile)
        }
        #endif
        #endif
    }

    private func badge(_ state: CameraStreamState) -> some View {
        HStack(spacing: HassTokens.Spacing.xs) {
            switch state.phase {
            case .connecting:
                ProgressView().controlSize(.mini).tint(.white)
            case .live:
                Circle().fill(.red).frame(width: 8, height: 8)
            case .failed:
                Image(systemName: "photo")
            }
            Text(Self.badgeText(state))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, HassTokens.Spacing.s)
        .padding(.vertical, HassTokens.Spacing.xs)
        .background(.black.opacity(0.75), in: Capsule())
        .padding(HassTokens.Spacing.s)
        .accessibilityHidden(true) // Read as the video's value.
    }

    @ViewBuilder private func retry(_ state: CameraStreamState) -> some View {
        if state.phase == .failed, !state.modes.isEmpty {
            Button {
                pool.retry(camera, connection: connection)
            } label: {
                Label("Retry Live Video", systemImage: "arrow.clockwise")
                    .frame(minHeight: HassTokens.minTarget)
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

/// The viewer's video is one element that reads its live state; a tile's video is hidden because the tile's
/// button already names the camera and reads the state.
private struct VideoAccessibility: ViewModifier {
    var style: CameraLiveView.Style
    var camera: HomeConfig.Camera
    var state: CameraStreamState

    func body(content: Content) -> some View {
        switch style {
        case .viewer:
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(camera.title) camera")
                .accessibilityValue(CameraLiveView.statusText(state))
                .accessibilityIdentifier("camera.viewer.video")
        case .tile:
            content.accessibilityHidden(true)
        }
    }
}

#if canImport(UIKit)
/// An `AVPlayerLayer` host with no controls (live HLS has nothing to scrub). Several layers can show one
/// player (a tile and its viewer).
struct HLSPlayerView: UIViewRepresentable {
    var player: AVPlayer
    /// Fill crops to the frame (tiles); fit letterboxes (the viewer).
    var fills = false

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.videoGravity = fills ? .resizeAspectFill : .resizeAspect
        view.playerLayer.player = player
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        view.playerLayer.videoGravity = fills ? .resizeAspectFill : .resizeAspect
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    /// A view backed by `AVPlayerLayer`.
    final class PlayerLayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer } // swiftlint:disable:this force_cast
    }
}
#endif
