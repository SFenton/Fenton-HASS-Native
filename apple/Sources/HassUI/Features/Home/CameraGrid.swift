#if os(iOS)
import HassCore
import HassDesign
import SwiftUI
import UIKit

/// Home cameras (web `CameraTile` grid: `columns={2} maxCellWidth={280} maxColumns={4}`).
struct CameraGrid: View {
    var onOpen: (HomeConfig.Camera) -> Void

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
                    .accessibilityHint("Opens the camera")
                }
            }
        }
    }
}

/// One camera tile: the latest snapshot with its title.
struct CameraTile: View {
    var camera: HomeConfig.Camera

    var body: some View {
        CameraSnapshotView(entityId: camera.entityId)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: HassTokens.Radius.media, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Text(camera.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, HassTokens.Spacing.s)
                    .padding(.vertical, HassTokens.Spacing.xs)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(HassTokens.Spacing.s)
            }
    }
}

/// Full-screen camera view. First pass: a larger snapshot; live WebRTC comes later
/// (`.agents/pages/home/ios.md`).
struct CameraViewer: View {
    var camera: HomeConfig.Camera
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CameraSnapshotView(entityId: camera.entityId)
                .aspectRatio(camera.aspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: HassTokens.Radius.media, style: .continuous))
                .padding()
                .frame(maxHeight: .infinity)
                .navigationTitle(camera.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
        .presentationDetents([.large])
    }
}

/// Loads a camera's `entity_picture` snapshot (a tokenized `/api/camera_proxy` URL) and keeps the last
/// image on screen while the next one loads, so refreshes never flash.
struct CameraSnapshotView: View {
    var entityId: String
    @Environment(EntityStore.self) private var store
    @Environment(HassConnection.self) private var connection
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "video").font(.title).foregroundStyle(.secondary)
            }
        }
        .task(id: snapshotURL) {
            guard let url = snapshotURL,
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let loaded = UIImage(data: data) else { return }
            image = loaded
        }
    }

    private var snapshotURL: URL? {
        guard let picture = store.entity(entityId).state?.attributes["entity_picture"]?.string else { return nil }
        return URL(string: picture, relativeTo: connection.server.baseURL)?.absoluteURL
    }
}
#endif
