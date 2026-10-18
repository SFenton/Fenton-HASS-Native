import FentonActivityModel
import Foundation
import HassCore
import Observation

/// Native notifications for the signed-in session (`.agents/platforms/apple/push.md`).
///
/// Asks for notification permission, hands the APNs token to the session's shared `mobile_app` registration
/// (``mobileApp``), and decides what a notification tap or button does. The app delegate forwards system callbacks
/// here; the shell observes ``pendingRequest`` and opens the page (``ShellNavigator/open(_:)``). Home Assistant
/// stays the source of truth: a button fires `mobile_app_notification_action` and the automation decides what
/// happens.
@MainActor
@Observable
public final class PushCoordinator {
    /// The page a notification asked to open, until the shell opens it.
    public private(set) var pendingRequest: PushNavigationRequest?

    /// The session's `mobile_app` registration, which location and sensors share.
    @ObservationIgnored public let mobileApp: MobileAppCoordinator

    @ObservationIgnored private let platform: PushPlatform
    @ObservationIgnored private var server: HassServer?
    @ObservationIgnored private var requestID = 0

    /// Creates a coordinator.
    /// - Parameters:
    ///   - platform: System services.
    ///   - store: Saved webhooks.
    ///   - transport: HTTP to Home Assistant.
    ///   - isEnabled: Register and ask for permission. Off for UI journeys signed in with a test token, so they
    ///     neither prompt nor add `mobile_app` devices to the real server.
    public init(platform: PushPlatform, store: any MobileAppRegistrationStore = KeychainMobileAppRegistrationStore(),
                transport: any FeedbackHTTPTransport = URLSessionFeedbackTransport(), isEnabled: Bool = true) {
        self.platform = platform
        mobileApp = MobileAppCoordinator(device: platform.device, store: store, transport: transport, isEnabled: isEnabled)
    }

    /// A coordinator that never registers or prompts.
    public static func inert() -> PushCoordinator {
        PushCoordinator(platform: .inert, store: InMemoryMobileAppRegistrationStore(), isEnabled: false)
    }

    // MARK: - Session

    /// A session started on a server.
    /// - Parameters:
    ///   - server: The signed-in server.
    ///   - accessToken: Valid access tokens for it.
    func sessionStarted(server: HassServer, accessToken: @escaping @Sendable () async throws -> String) {
        self.server = server
        mobileApp.sessionStarted(server: server, accessToken: accessToken)
    }

    /// The websocket is up and the user is known: ask for permission (first time only), register for remote
    /// notifications, and sync the registration.
    /// - Parameters:
    ///   - userID: The signed-in Home Assistant user.
    ///   - userName: Their display name, which names a phone the system reports only as "iPhone".
    public func didConnect(userID: String, userName: String? = nil) async {
        guard mobileApp.begin(userID: userID, userName: userName) else { return }
        if await platform.requestAuthorization() { platform.registerForRemoteNotifications() }
        await mobileApp.sync()
    }

    /// The system issued an APNs token.
    public func didRegister(deviceToken: Data) async {
        guard mobileApp.setPushToken(PushToken.hex(deviceToken)) else { return }
        await mobileApp.sync()
    }

    /// Signing out: clear Home Assistant's push details for this phone (before the refresh token is revoked).
    func sessionEnded() async {
        server = nil
        pendingRequest = nil
        await mobileApp.sessionEnded()
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
                try? await mobileApp.fireAction(PushActionEvent(action: id, tag: payload.tag, replyText: replyText))
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

    /// A tap on the Home Live Activity (`fentonhome://liveactivity?url=…`): opens the focused job's page.
    /// - Returns: Whether the URL was a Live Activity link.
    @discardableResult
    public func openLiveActivity(_ url: URL) -> Bool {
        guard let link = ActivityDeepLink.link(from: url) else { return false }
        open(link: link)
        return true
    }

    /// Opens a page of the app from outside it: a Spotlight result or an App Shortcut. The shell opens it the way it
    /// opens a notification's page (``pendingRequest``), including a launch the tap itself caused.
    /// - Parameter destination: The page.
    public func open(_ destination: PushDestination) {
        requestID += 1
        pendingRequest = PushNavigationRequest(id: requestID, destination: destination)
    }

    /// Opens the page a tapped Spotlight result stands for.
    /// - Parameter userInfo: The `NSUserActivity` for `CSSearchableItemActionType`.
    /// - Returns: Whether the result was one of the app's pages.
    @discardableResult
    public func open(spotlightUserInfo userInfo: [AnyHashable: Any]?) -> Bool {
        guard let identifier = SpotlightLink.identifier(in: userInfo),
              let destination = SpotlightCatalog.destination(forIdentifier: identifier) else { return false }
        open(destination)
        return true
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
