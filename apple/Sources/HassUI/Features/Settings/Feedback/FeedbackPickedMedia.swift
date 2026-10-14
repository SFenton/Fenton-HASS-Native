import CoreTransferable
import Foundation
import HassCore
import UniformTypeIdentifiers

/// A photo or video copied into app temporary storage, from the photo picker's temporary file (before
/// its import closure returns) or a file importer URL.
struct FeedbackPickedMedia: Transferable {
    let url: URL

    /// Parent of every staged copy, inside the app's temporary directory.
    static let stagingFolder = FileManager.default.temporaryDirectory
        .appendingPathComponent("fenton-feedback-media", isDirectory: true)

    static var transferRepresentation: some TransferRepresentation {
        // Movies first so a video (screen recordings included) arrives as its own file, not a still.
        FileRepresentation(importedContentType: .movie) { try stage($0.file) }
        FileRepresentation(importedContentType: .image) { try stage($0.file) }
    }

    /// Copies `file` into its own UUID folder, keeping a safe version of its name.
    ///
    /// - Parameter file: Readable source file.
    /// - Returns: The app-owned copy.
    /// - Throws: File system errors.
    static func stage(_ file: URL) throws -> FeedbackPickedMedia {
        let folder = stagingFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(FeedbackAttachmentPolicy.sanitizedFilename(file.lastPathComponent))
        try FileManager.default.copyItem(at: file, to: destination)
        return FeedbackPickedMedia(url: destination)
    }
}
