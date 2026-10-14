import Foundation
import HassCore
import Observation

/// A notification the system shows now, as the coordinator needs it.
public struct DeliveredNotification: Sendable {
    /// `UNNotificationRequest.identifier`.
    public var identifier: String
    /// The notification's `fenton` tag, if any.
    public var tag: String?

    /// Creates a delivered notification.
    public init(identifier: String, tag: String?) {
        self.identifier = identifier
        self.tag = tag
    }
}

/// What the person did with a notification.
public enum NotificationResponse: Equatable, Sendable {
    /// Tapped the notification.
    case open
    /// Dismissed it.
    case dismiss
    /// Pressed a button, with the typed reply for a text-input button.
    case action(String, replyText: String?)
}

/// A page to open, stamped so the same destination twice in a row still opens.
public struct PushNavigationRequest: Equatable, Sendable {
    /// Increases with each request.
    public var id: Int
    /// The page.
    public var destination: PushDestination
}

/// The system services the coordinator uses; the app supplies UIKit and UserNotifications, tests supply stubs.
public struct PushPlatform: Sendable {
    /// This phone's registration facts.
    public var device: @MainActor @Sendable () -> PushDevice
    /// Asks for alert, sound and badge permission (once; later calls return the stored answer).
    public var requestAuthorization: @Sendable () async -> Bool
    /// `UIApplication.registerForRemoteNotifications()`.
    public var registerForRemoteNotifications: @MainActor @Sendable () -> Void
    /// Notifications in Notification Center now.
    public var deliveredNotifications: @Sendable () async -> [DeliveredNotification]
    /// Removes notifications from Notification Center.
    public var removeDelivered: @Sendable ([String]) -> Void
    /// Opens a web address outside the app.
    public var openExternal: @MainActor @Sendable (URL) -> Void

    /// Creates a platform.
    public init(device: @escaping @MainActor @Sendable () -> PushDevice,
                requestAuthorization: @escaping @Sendable () async -> Bool,
                registerForRemoteNotifications: @escaping @MainActor @Sendable () -> Void,
                deliveredNotifications: @escaping @Sendable () async -> [DeliveredNotification],
                removeDelivered: @escaping @Sendable ([String]) -> Void,
                openExternal: @escaping @MainActor @Sendable (URL) -> Void) {
        self.device = device
        self.requestAuthorization = requestAuthorization
        self.registerForRemoteNotifications = registerForRemoteNotifications
        self.deliveredNotifications = deliveredNotifications
        self.removeDelivered = removeDelivered
        self.openExternal = openExternal
    }

    /// A platform that does nothing (previews, the debug gallery, and UI journeys that must not prompt).
    public static let inert = PushPlatform(
        device: { PushDevice(marketingVersion: "0", build: "0", name: "Preview", model: "Preview", osVersion: "0",
                             deviceID: "preview", apnsEnvironment: .sandbox) },
        requestAuthorization: { false },
        registerForRemoteNotifications: {},
        deliveredNotifications: { [] },
        removeDelivered: { _ in },
        openExternal: { _ in }
    )
}

/// Native notifications for the signed-in session (`.agents/platforms/apple/push.md`).
///
/// Owns the session's ``PushRegistrar``, the APNs token, and what a notification tap or button does. The app
/// delegate forwards system callbacks here; the shell observes ``pendingRequest`` and opens the page
/// (``ShellNavigator/open(_:)``). Home Assistant stays the source of truth: a button fires
/// `mobile_app_notification_action` and the automation decides what happens.
@MainActor
@Observable
public final class PushCoordinator {
    /// The page a notification asked to open, until the shell opens it.
    public private(set) var pendingRequest: PushNavigationRequest?

    @ObservationIgnored private let platform: PushPlatform
    @ObservationIgnored private let store: any PushRegistrationStore
    @ObservationIgnored private let transport: any FeedbackHTTPTransport
    @ObservationIgnored private let isEnabled: Bool
    @ObservationIgnored private var server: HassServer?
    @ObservationIgnored private var registrar: PushRegistrar?
    @ObservationIgnored private var userID: String?
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var requestID = 0
    /// The running registration sync, so a token arriving mid-sync waits for it instead of racing it.
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    /// Creates a coordinator.
    /// - Parameters:
    ///   - platform: System services.
    ///   - store: Saved webhooks.
    ///   - transport: HTTP to Home Assistant.
    ///   - isEnabled: Register and ask for permission. Off for UI journeys signed in with a test token, so they
    ///     neither prompt nor add `mobile_app` devices to the real server.
    public init(platform: PushPlatform, store: any PushRegistrationStore = KeychainPushRegistrationStore(),
                transport: any FeedbackHTTPTransport = URLSessionFeedbackTransport(), isEnabled: Bool = true) {
        self.platform = platform
        self.store = store
        self.transport = transport
        self.isEnabled = isEnabled
    }

    /// A coordinator that never registers or prompts.
    public static func inert() -> PushCoordinator {
        PushCoordinator(platform: .inert, store: InMemoryPushRegistrationStore(), isEnabled: false)
    }

    // MARK: - Session

    /// A session started on a server.
    /// - Parameters:
    ///   - server: The signed-in server.
    ///   - accessToken: Valid access tokens for it.
    func sessionStarted(server: HassServer, accessToken: @escaping @Sendable () async throws -> String) {
        self.server = server
        userID = nil
        let client = HomeAssistantPushClient(server: server, accessToken: accessToken, transport: transport)
        registrar = PushRegistrar(server: server, client: client, store: store, device: platform.device())
    }

    /// The websocket is up and the user is known: ask for permission (first time only), register for remote
    /// notifications, and sync the registration.
    /// - Parameter userID: The signed-in Home Assistant user.
    public func didConnect(userID: String) async {
        guard isEnabled, registrar != nil, self.userID != userID else { return }
        self.userID = userID
        if await platform.requestAuthorization() { platform.registerForRemoteNotifications() }
        await sync()
    }

    /// The system issued an APNs token.
    public func didRegister(deviceToken: Data) async {
        let hex = PushToken.hex(deviceToken)
        guard hex != token else { return }
        token = hex
        await sync()
    }

    /// Signing out: clear Home Assistant's push details for this phone (before the refresh token is revoked).
    func sessionEnded() async {
        let registrar = registrar
        self.registrar = nil
        server = nil
        userID = nil
        pendingRequest = nil
        await registrar?.signOut()
    }

    private func sync() async {
        await syncTask?.value
        guard isEnabled, let registrar, let userID else { return }
        let token = token
        let task = Task { _ = try? await registrar.sync(userID: userID, token: token) }
        syncTask = task
        await task.value
    }

    // MARK: - Notifications

    /// A tap, dismissal or button press on a notification.
    /// - Parameters:
    ///   - response: What the person did.
    ///   - userInfo: The notification's `userInfo`.
    public func handle(_ response: NotificationResponse, userInfo: [AnyHashable: Any]) async {
        guard let payload = PushPayload(userInfo: userInfo) else { return }
        switch response {
        case .dismiss:
            return
        case .open:
            if let url = payload.url { open(link: url) }
        case let .action(id, replyText):
            guard let action = payload.action(id) else { return }
            if let uri = action.uri {
                open(link: uri)
            } else {
                try? await registrar?.fireAction(PushActionEvent(action: id, tag: payload.tag, replyText: replyText))
            }
        }
    }

    /// A background push: runs its command.
    /// - Returns: Whether the push carried a command this version runs.
    @discardableResult
    public func handleBackground(userInfo: [AnyHashable: Any]) async -> Bool {
        guard case let .clearNotification(tag)? = PushPayload(userInfo: userInfo)?.command else { return false }
        let ids = await platform.deliveredNotifications().filter { $0.tag == tag }.map(\.identifier)
        if !ids.isEmpty { platform.removeDelivered(ids) }
        return true
    }

    /// The shell opened ``pendingRequest``.
    public func didOpen(_ request: PushNavigationRequest) {
        if pendingRequest == request { pendingRequest = nil }
    }

    /// Opens a notification link: an app page, Home Assistant's own page, or another site.
    func open(link: String) {
        switch PushLink(link, server: server) {
        case let .dashboard(path, _)?:
            requestID += 1
            pendingRequest = PushNavigationRequest(id: requestID, destination: PushDestination(dashboardPath: path))
        case let .homeAssistant(path)?:
            if let server { platform.openExternal(server.url(path)) }
        case let .external(url)?:
            platform.openExternal(url)
        case nil:
            return
        }
    }
}
