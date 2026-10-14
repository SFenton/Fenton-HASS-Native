import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// What the notification service extension changes on a notification before it shows (contract v1, rule 3;
/// `.agents/platforms/apple/push.md`). Pure, so the extension and the debug local-notification preview share it.
public struct PushEnrichment: Equatable, Sendable {
    /// The category to register and use; nil when the payload has no buttons.
    public var category: PushCategory?
    /// Clear the relay's `fenton.dynamic` placeholder (no buttons).
    public var clearsPlaceholderCategory: Bool
    /// Thread id to set (`group`), when the notification has none.
    public var threadIdentifier: String?
    /// The file to attach.
    public var attachment: PushAttachmentSource?

    /// Plans the changes.
    /// - Parameters:
    ///   - payload: The `fenton` block.
    ///   - categoryIdentifier: The notification's category now.
    ///   - threadIdentifier: The notification's thread now.
    ///   - server: The signed-in server, if any (attachments need it).
    public init(payload: PushPayload, categoryIdentifier: String, threadIdentifier: String, server: HassServer?) {
        category = PushCategory(actions: payload.actions)
        clearsPlaceholderCategory = category == nil && categoryIdentifier == PushPayload.dynamicCategory
        self.threadIdentifier = threadIdentifier.isEmpty ? payload.group : nil
        attachment = server.flatMap { PushAttachmentSource.resolve(payload, server: $0) }
    }
}

/// Downloads a notification attachment to a file the system can attach.
public struct PushAttachmentLoader: Sendable {
    private let transport: any FeedbackHTTPTransport
    private let directory: URL

    /// Creates a loader.
    /// - Parameters:
    ///   - transport: The HTTP seam.
    ///   - directory: Where downloaded files go.
    public init(transport: any FeedbackHTTPTransport = URLSessionFeedbackTransport(),
                directory: URL = FileManager.default.temporaryDirectory) {
        self.transport = transport
        self.directory = directory
    }

    /// Fetches a source; nil on any failure, an empty body, or a file over the kind's limit.
    /// - Parameters:
    ///   - source: What to fetch.
    ///   - accessToken: The Home Assistant token, for sources that need it.
    public func load(_ source: PushAttachmentSource, accessToken: String?) async -> URL? {
        var request = URLRequest(url: source.url, timeoutInterval: 20)
        if source.needsAuthorization {
            guard let accessToken else { return nil }
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await transport.send(request), (200..<300).contains(response.statusCode),
              !data.isEmpty, data.count <= source.byteLimit else { return nil }
        let file = directory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(source.fileExtension(mimeType: response.mimeType ?? response.value(forHTTPHeaderField: "Content-Type")))
        guard (try? data.write(to: file)) != nil else { return nil }
        return file
    }
}

#if canImport(UserNotifications)
extension PushEnrichment {
    /// Applies the category and thread to content (the attachment is added by the caller once loaded).
    public func apply(to content: UNMutableNotificationContent) {
        if let category { content.categoryIdentifier = category.identifier }
        if clearsPlaceholderCategory { content.categoryIdentifier = "" }
        if let threadIdentifier { content.threadIdentifier = threadIdentifier }
    }
}
#endif
