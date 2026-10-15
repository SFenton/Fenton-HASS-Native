import Foundation
import HassCore
import Observation

/// The signed-in session's one `mobile_app` registration, shared by push, location and sensors
/// (`.agents/platforms/apple/mobile-app.md`).
///
/// Owns the session's ``MobileAppRegistrar``, the user it registered for, and the APNs token. ``PushCoordinator``
/// starts the session, supplies the token and fires notification buttons through it; ``LocationCoordinator`` sends
/// through ``webhookSource`` and starts when ``registration`` appears.
@MainActor
@Observable
public final class MobileAppCoordinator {
    /// The registration this session synced; nil until the first sync succeeds, and after sign-out.
    public private(set) var registration: MobileAppRegistration?

    /// Register at all. Off for UI journeys signed in with a test token, so they never add `mobile_app` devices
    /// to the real server.
    public let isEnabled: Bool

    @ObservationIgnored private let device: @MainActor @Sendable () -> MobileAppDevice
    @ObservationIgnored private let store: any MobileAppRegistrationStore
    @ObservationIgnored private let transport: any FeedbackHTTPTransport
    @ObservationIgnored private var registrar: MobileAppRegistrar?
    @ObservationIgnored private(set) var userID: String?
    @ObservationIgnored private var userName: String?
    @ObservationIgnored private var token: String?
    /// The running sync, so a token arriving mid-sync waits for it instead of racing it.
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var listeners: [@MainActor (MobileAppRegistration?) -> Void] = []

    /// Creates a coordinator.
    /// - Parameters:
    ///   - device: This phone's registration facts.
    ///   - store: Saved webhooks.
    ///   - transport: HTTP to Home Assistant.
    ///   - isEnabled: Register at all.
    public init(device: @escaping @MainActor @Sendable () -> MobileAppDevice,
                store: any MobileAppRegistrationStore = KeychainMobileAppRegistrationStore(),
                transport: any FeedbackHTTPTransport = URLSessionFeedbackTransport(), isEnabled: Bool = true) {
        self.device = device
        self.store = store
        self.transport = transport
        self.isEnabled = isEnabled
    }

    /// Where location and sensor commands go: the signed-in user's webhook, read at send time.
    public var webhookSource: any MobileAppWebhookSource { store }

    /// The webhook saved by an earlier launch, so location can report before this launch's sync (a background
    /// relaunch for a zone event never reaches the shell).
    public var savedWebhookExists: Bool { isEnabled && store.active != nil }

    /// Calls `listener` whenever ``registration`` changes (location now; sensors later).
    public func onRegistrationChange(_ listener: @escaping @MainActor (MobileAppRegistration?) -> Void) {
        listeners.append(listener)
    }

    // MARK: - Session

    /// A session started on a server.
    /// - Parameters:
    ///   - server: The signed-in server.
    ///   - accessToken: Valid access tokens for it.
    func sessionStarted(server: HassServer, accessToken: @escaping @Sendable () async throws -> String) {
        userID = nil
        setRegistration(nil)
        let client = HomeAssistantPushClient(server: server, accessToken: accessToken, transport: transport)
        registrar = MobileAppRegistrar(server: server, client: client, store: store, device: device())
    }

    /// Takes the signed-in user, once per session.
    /// - Returns: Whether the user is new to this session (a reconnect as the same user returns false), so the
    ///   caller syncs; false too when disabled or before a session starts.
    func begin(userID: String, userName: String?) -> Bool {
        guard isEnabled, registrar != nil, self.userID != userID else { return false }
        self.userID = userID
        self.userName = userName
        return true
    }

    /// The system issued an APNs token (lowercase hex).
    /// - Returns: Whether it differs from the last one, so the caller syncs.
    func setPushToken(_ hex: String) -> Bool {
        guard hex != token else { return false }
        token = hex
        return true
    }

    /// Registers or updates for the session's user with the current token. Waits for a running sync first.
    public func sync() async {
        await syncTask?.value
        guard isEnabled, let registrar, let userID else { return }
        let token = token, userName = userName
        let task = Task { [weak self] in
            guard let outcome = try? await registrar.sync(userID: userID, userName: userName, token: token) else { return }
            self?.setRegistration(outcome.registration)
        }
        syncTask = task
        await task.value
    }

    /// Signing out: clear Home Assistant's push details for this phone (before the refresh token is revoked).
    func sessionEnded() async {
        let registrar = registrar
        self.registrar = nil
        userID = nil
        setRegistration(nil)
        await registrar?.signOut()
    }

    /// Fires a notification button's event on the signed-in user's webhook.
    func fireAction(_ event: PushActionEvent) async throws {
        guard let registrar else { throw PushClientError.signedOut }
        try await registrar.fireAction(event)
    }

    private func setRegistration(_ new: MobileAppRegistration?) {
        guard new != registration else { return }
        registration = new
        listeners.forEach { $0(new) }
    }
}
