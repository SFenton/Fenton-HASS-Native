import HassCore
import HassDesign
import ImageIO
import SwiftUI

/// Home cameras (web `CameraTile` grid: `columns={2} maxCellWidth={280} maxColumns={4}`).
struct CameraGrid: View {
    var onOpen: (HomeConfig.Camera) -> Void
    @Environment(\.cameraStreamPool) private var poolOverride

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            Text("Cameras")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            DynamicGridLayout(minCellWidth: 160, maxColumns: 4) {
                ForEach(HomeConfig.cameras) { camera in
                    Button { onOpen(camera) } label: {
                        CameraTile(camera: camera)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(camera.title) camera")
                    .accessibilityValue(CameraTile.statusText((poolOverride ?? .shared).model(for: camera).state))
                    .accessibilityHint("Opens the camera")
                    .accessibilityIdentifier("home.camera.\(camera.rtcStreamId)")
                }
            }
        }
    }
}

/// One camera tile: the camera's shared live stream (web `CameraTile` → `RtcPilotCamera variant="tile"`) over
/// its latest snapshot, with its title and, while live, a Live label.
struct CameraTile: View {
    var camera: HomeConfig.Camera
    @Environment(\.cameraStreamPool) private var poolOverride

    private let shape = RoundedRectangle(cornerRadius: HassTokens.Radius.media, style: .continuous)

    var body: some View {
        let isLive = (poolOverride ?? .shared).model(for: camera).state.phase == .live
        // The cell sets the 16:9 frame and the video fills it, so wide cameras can't widen the tile.
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay { CameraLiveView(camera: camera, style: .tile) }
            .clipShape(shape)
            // Hit-test only the tile's own frame: the fill-scaled Driveway (10:3) image is wider than its cell,
            // and without this its overflow took taps meant for the Front Door tile beside it.
            .contentShape(shape)
            .overlay(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: HassTokens.Spacing.xs) {
                    // Wraps at large Dynamic Type instead of truncating.
                    label { Text(camera.title).fixedSize(horizontal: false, vertical: true) }
                    Spacer(minLength: 0)
                    if isLive {
                        label {
                            HStack(spacing: HassTokens.Spacing.xs) {
                                Circle().fill(.red).frame(width: 6, height: 6)
                                Text("Live")
                            }
                        }
                    }
                }
                .padding(HassTokens.Spacing.s)
            }
    }

    /// The tile's VoiceOver value: live, or the snapshot it is showing.
    static func statusText(_ state: CameraStreamState) -> String {
        state.phase == .live ? "Live" : "Snapshot"
    }

    private func label(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, HassTokens.Spacing.s)
            .padding(.vertical, HassTokens.Spacing.xs)
            // A dark scrim keeps contrast on any picture (thin material failed on dark images).
            .background(.black.opacity(0.75), in: Capsule())
    }
}

/// A camera's `entity_picture` snapshot (a tokenized `/api/camera_proxy` URL) through ``CachedImage``: downsampled
/// to the tile off the main thread, the last snapshot kept on screen (and on disk for cold launches) while the
/// next one loads, including when Home Assistant rotates the URL's token (`.agents/patterns/image-cache.md`).
struct CameraSnapshotView: View {
    var entityId: String
    @Environment(EntityStore.self) private var store
    @Environment(HassConnection.self) private var connection

    var body: some View {
        Rectangle().fill(.quaternary)
            .overlay {
                CachedImage(url: snapshotURL) {
                    Image(systemName: "video").font(.title).foregroundStyle(.secondary)
                }
                .blur(radius: ScreenshotPrivacy.isRedacting ? 40 : 0)
                // Decorative (the camera's element reads its state), and hidden so the fill-scaled image's
                // overflow doesn't widen that element's VoiceOver frame past the video.
                .accessibilityHidden(true)
            }
            // The fill-scaled image stays inside the frame for both drawing and hit-testing.
            .clipped()
            .allowsHitTesting(false)
    }

    private var snapshotURL: URL? {
        guard let picture = store.entity(entityId).state?.attributes["entity_picture"]?.string else { return nil }
        return URL(string: picture, relativeTo: connection.server.baseURL)?.absoluteURL
    }
}
