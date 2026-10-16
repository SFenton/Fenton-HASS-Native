import Foundation

/// Keeps this phone's one `mobile_app` registration per Home Assistant user in step with the signed-in user and
/// the APNs token. Push, location and sensors share it, so each phone is one Home Assistant device
/// (`.agents/platforms/apple/mobile-app.md`; Fenton Push contract v1, rules 1-2).
///
/// - Launch and token change: reads the Fenton Push config, then sends `update_registration` on the user's saved
///   webhook, or registers when there is none or Home Assistant deleted it (410).
/// - Without the integration (404) or with `available: false`, the phone still registers, without push details
///   (websocket-only), so location and sensors work on a server without Fenton Push. A later sync adds the push
///   details once the integration answers.
/// - Sign-out: sends `update_registration` with empty `app_data` before the refresh token is revoked, so Home
///   Assistant stops pushing to a signed-out phone. The webhook stays saved for the next sign-in as that user.
/// - Simulator: never registers or updates (``MobileAppRegistrationPolicy``), so a simulator never becomes one of
///   the signed-in person's devices; journeys that need a registration use stubs.
public actor MobileAppRegistrar {
    /// Why a sync did nothing.
    public enum Refusal: Error, Equatable, Sendable {
        /// This build runs in the simulator without `FENTON_MOBILE_APP_REGISTER=1`.
        case simulator
    }

    /// What a sync did.
    public enum Outcome: Equatable, Sendable {
        /// Registered a new device.
        case registered(MobileAppRegistration, PushAppData)
        /// Updated the saved registration.
        case updated(MobileAppRegistration, PushAppData)

        /// The registration synced.
        public var registration: MobileAppRegistration {
            switch self {
            case let .registered(registration, _), let .updated(registration, _): registration
            }
        }
    }

    private let server: HassServer
    private let client: HomeAssistantPushClient
    private let store: any MobileAppRegistrationStore
    private let device: MobileAppDevice
    private let allowsRegistration: Bool

    /// Creates a registrar.
    /// - Parameters:
    ///   - server: The signed-in server.
    ///   - client: The Fenton Push config and Home Assistant's registration endpoints.
    ///   - store: Saved webhooks.
    ///   - device: This phone.
    ///   - allowsRegistration: Register and update at all; off in the simulator
    ///     (``MobileAppRegistrationPolicy/allowsRegistration(environment:isSimulator:)``).
    public init(server: HassServer, client: HomeAssistantPushClient, store: any MobileAppRegistrationStore,
                device: MobileAppDevice, allowsRegistration: Bool = MobileAppRegistrationPolicy.allowsRegistration()) {
        self.server = server
        self.client = client
        self.store = store
        self.device = device
        self.allowsRegistration = allowsRegistration
    }

    /// Registers or updates for a user.
    /// - Parameters:
    ///   - userID: The signed-in Home Assistant user.
    ///   - userName: The user's display name, which names a phone the system reports only as "iPhone"
    ///     (``MobileAppDevice/owned(by:)``).
    ///   - token: The APNs token as hex, if the system issued one (nil before permission or in a build without
    ///     the capability): the registration is then websocket-only.
    /// - Throws: ``Refusal/simulator`` without sending anything when registration isn't allowed; a
    ///   ``PushClientError`` when Home Assistant fails.
    @discardableResult
    public func sync(userID: String, userName: String? = nil, token: String?) async throws -> Outcome {
        guard allowsRegistration else { throw Refusal.simulator }
        let device = device.owned(by: userName)
        // No integration (404) registers without push details, like `available: false`.
        var config = try await client.config() ?? PushConfig(available: false)
        if let bundle = config.bundleID, bundle != PushApp.appID { config.available = false }
        let appData = PushAppData.resolve(config: config, token: token, environment: device.apnsEnvironment)
        if let saved = store.registration(server: server, userID: userID) {
            do {
                try await client.updateRegistration(saved, device: device, appData: appData)
                store.setActive(saved)
                return .updated(saved, appData)
            } catch PushClientError.registrationGone {
                store.remove(server: server, userID: userID)
            }
        }
        let webhookID = try await client.register(device, appData: appData)
        let registration = MobileAppRegistration(server: server, userID: userID, webhookID: webhookID)
        store.save(registration)
        store.setActive(registration)
        return .registered(registration, appData)
    }

    /// Stops pushes to this phone for the signed-in user. Best effort: sign-out goes ahead when offline.
    public func signOut() async {
        guard let active = store.active, active.server == server else { return }
        store.setActive(nil)
        do {
            try await client.updateRegistration(active, device: device, appData: .cleared)
        } catch PushClientError.registrationGone {
            store.remove(server: active.server, userID: active.userID)
        } catch {}
    }

    /// Fires a notification button's event on the signed-in user's webhook.
    public func fireAction(_ event: PushActionEvent) async throws {
        guard let active = store.active else { throw PushClientError.signedOut }
        do {
            try await client.fireAction(active, event: event)
        } catch PushClientError.registrationGone {
            store.remove(server: active.server, userID: active.userID)
            throw PushClientError.registrationGone
        }
    }
}
