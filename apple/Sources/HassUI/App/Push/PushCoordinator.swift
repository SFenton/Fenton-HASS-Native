import Foundation
import HassCore
import Observation

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
