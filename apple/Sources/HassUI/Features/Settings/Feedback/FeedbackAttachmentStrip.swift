import SwiftUI
import QuickLookThumbnailing
import HassCore
import HassDesign
#if os(iOS)
import QuickLook
#elseif os(macOS)
import AppKit
#endif

// MARK: - Strip

/// Attached media shown above Attach Media (ported from FestivalNativeApps): a thumbnail per file that opens
/// in the system viewer (Quick Look on iOS/iPadOS, the default app on macOS) with a
/// remove button. The app never plays or views media itself.
///
/// HIG (File management, Quick Look): "Use its viewer for attachments or files your app
/// cannot open".
struct FeedbackAttachmentStrip: View {
    let attachments: [FeedbackAttachment]
    let onRemove: (FeedbackAttachment) -> Void
    @State private var previewURL: URL?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                    FeedbackAttachmentTile(
                        attachment: attachment, position: index + 1,
                        onOpen: { open(attachment) }, onRemove: { onRemove(attachment) }
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("feedback.attachments")
        #if os(iOS)
        .quickLookPreview($previewURL, in: attachments.map(\.fileURL))
        #endif
    }

    private func open(_ attachment: FeedbackAttachment) {
        #if os(macOS)
        NSWorkspace.shared.open(attachment.fileURL)
        #else
        previewURL = attachment.fileURL
        #endif
    }
}
