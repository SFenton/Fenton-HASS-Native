import Foundation
import HassCore
import UserNotifications

/// Finishes a Fenton Push notification before the system shows it (contract v1, rule 3;
/// `.agents/platforms/apple/push.md`):
///
/// - replaces the relay's `fenton.dynamic` placeholder with a category built from the payload's buttons
///   (``PushCategory``), registered next to the categories already there;
/// - threads it by `group`;
/// - attaches the camera snapshot (`/api/camera_proxy/<entity_id>`) or the image, video or file, fetched with the
///   signed-in user's token from the Keychain item the app shares through the app group.
///
/// Anything that fails leaves the notification as the relay sent it.
final class NotificationService: UNNotificationServiceExtension {
    private let state = DeliveryState()

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent,
              let payload = PushPayload(userInfo: content.userInfo) else {
            contentHandler(request.content)
            return
        }
        let thread = content.threadIdentifier.isEmpty ? payload.group : nil
        state.begin(content, handler: contentHandler)
        let state = state
        state.task = Task {
            await Self.applyCategory(payload, to: state)
            if let thread { state.update { $0.threadIdentifier = thread } }
            if let attachment = await Self.attachment(for: payload) { state.update { $0.attachments = [attachment] } }
            state.finish()
        }
    }

    override func serviceExtensionTimeWillExpire() {
        state.task?.cancel()
        state.finish()
    }

    // MARK: - Category

    private static func applyCategory(_ payload: PushPayload, to state: DeliveryState) async {
        guard let category = PushCategory(actions: payload.actions) else {
            state.update { if $0.categoryIdentifier == PushPayload.dynamicCategory { $0.categoryIdentifier = "" } }
            return
        }
        let center = UNUserNotificationCenter.current()
        let existing = await center.notificationCategories()
        center.setNotificationCategories(category.merged(into: existing))
        state.update { $0.categoryIdentifier = category.identifier }
    }

    // MARK: - Attachment

    private static func attachment(for payload: PushPayload) async -> UNNotificationAttachment? {
        let store = KeychainTokenStore(accessGroup: KeychainTokenStore.sharedAccessGroup)
        guard let credentials = store.load(),
              let source = PushAttachmentSource.resolve(payload, server: credentials.server) else { return nil }
        var request = URLRequest(url: source.url, timeoutInterval: 20)
        if source.needsAuthorization {
            guard let token = try? await TokenManager(store: store).validAccessToken() else { return nil }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        guard let (file, response) = try? await URLSession.shared.download(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0, size <= source.byteLimit else { return nil }
        let named = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(source.fileExtension(mimeType: http.mimeType))
        guard (try? FileManager.default.moveItem(at: file, to: named)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: source.kind.rawValue, url: named)
    }
}

/// The content being finished and its handler, shared between the work task and the expiry callback; the
/// handler runs once.
private final class DeliveryState: @unchecked Sendable {
    private let lock = NSLock()
    private var content: UNMutableNotificationContent?
    private var handler: ((UNNotificationContent) -> Void)?
    var task: Task<Void, Never>?

    func begin(_ content: UNMutableNotificationContent, handler: @escaping (UNNotificationContent) -> Void) {
        lock.withLock {
            self.content = content
            self.handler = handler
        }
    }

    func update(_ change: (UNMutableNotificationContent) -> Void) {
        lock.withLock { content.map(change) }
    }

    func finish() {
        let (content, handler) = lock.withLock {
            defer { self.handler = nil }
            return (self.content, self.handler)
        }
        if let content, let handler { handler(content) }
    }
}
