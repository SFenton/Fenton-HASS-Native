import Foundation

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
