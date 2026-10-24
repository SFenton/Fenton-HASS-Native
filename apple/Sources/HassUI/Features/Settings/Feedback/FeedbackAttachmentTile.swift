import SwiftUI
import QuickLookThumbnailing
import HassCore
import HassDesign

// MARK: - Tile

/// One thumbnail button plus its remove button, each at least 44 pt.
struct FeedbackAttachmentTile: View {
    let attachment: FeedbackAttachment
    let position: Int
    let onOpen: () -> Void
    let onRemove: () -> Void
    @State private var thumbnail: CGImage?
    @Environment(\.displayScale) private var displayScale

    private static let side: CGFloat = 76

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onOpen) {
                preview
                    .frame(width: Self.side, height: Self.side)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.separator)
                    }
                    .overlay(alignment: .bottomLeading) {
                        if attachment.isVideo {
                            Image(systemName: "play.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(.black.opacity(0.55), in: Circle())
                                .padding(5)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .padding(.trailing, 10)
            .accessibilityLabel(attachment.accessibilityLabel(position: position))
            .accessibilityHint(openHint)
            .accessibilityIdentifier("feedback.attachment.\(position)")

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: 12, y: -12)
            .accessibilityLabel("Remove \(attachment.filename)")
            .accessibilityIdentifier("feedback.attachment.\(position).remove")
        }
        .padding(.trailing, 12)
        .padding(.top, 2)
        .task(id: attachment.fileURL) { await loadThumbnail() }
    }

    @ViewBuilder
    private var preview: some View {
        if let thumbnail {
            Image(decorative: thumbnail, scale: displayScale)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Rectangle().fill(.quaternary)
                Image(systemName: attachment.isVideo ? "film" : "photo")
                    .font(.title2)
                    .foregroundStyle(HassTokens.Ink.secondary)
            }
        }
    }

    private var openHint: String {
        #if os(macOS)
        "Opens in the default app"
        #else
        "Opens in Quick Look"
        #endif
    }

    private func loadThumbnail() async {
        let request = QLThumbnailGenerator.Request(
            fileAt: attachment.fileURL,
            size: CGSize(width: Self.side, height: Self.side),
            scale: displayScale,
            representationTypes: .thumbnail
        )
        thumbnail = try? await QLThumbnailGenerator.shared
            .generateBestRepresentation(for: request).cgImage
    }
}
