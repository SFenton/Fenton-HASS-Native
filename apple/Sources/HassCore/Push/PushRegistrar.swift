import Foundation

/// Keeps this phone's `mobile_app` registration in step with the signed-in user and the APNs token
/// (contract v1, rule 2).
///
/// - Launch and token change: reads the Fenton Push config, then sends `update_registration` on the user's saved
///   webhook, or registers when there is none or Home Assistant deleted it (410).
/// - Sign-out: sends `update_registration` with empty `app_data` before the refresh token is revoked, so Home
///   Assistant stops pushing to a signed-out phone. The webhook stays saved for the next sign-in as that user.
/// - Without the integration (404) nothing is registered: the app has no relay to receive pushes from, and a
///   registration would add a `mobile_app` device to Home Assistant for nothing.
public actor PushRegistrar {
    /// What a sync did.
    public enum Outcome: Equatable, Sendable {
        /// The integration is not installed; nothing was sent.
        case integrationMissing
        /// Registered a new device.
        case registered(PushRegistration, PushAppData)
        /// Updated the saved registration.
        case updated(PushRegistration, PushAppData)
    }

    private let server: HassServer
    private let client: HomeAssistantPushClient
    private let store: any PushRegistrationStore
    private let device: PushDevice

    /// Creates a registrar.
    /// - Parameters:
    ///   - server: The signed-in server.
    ///   - client: Home Assistant's push endpoints.
    ///   - store: Saved webhooks.
    ///   - device: This phone.
    public init(server: HassServer, client: HomeAssistantPushClient, store: any PushRegistrationStore, device: PushDevice) {
        self.server = server
        self.client = client
        self.store = store
        self.device = device
    }

    /// Registers or updates for a user.
    /// - Parameters:
    ///   - userID: The signed-in Home Assistant user.
    ///   - token: The APNs token as hex, if the system issued one (nil before permission or in a build without
    ///     the capability): the registration is then websocket-only.
    @discardableResult
    public func sync(userID: String, token: String?) async throws -> Outcome {
        guard var config = try await client.config() else { return .integrationMissing }
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
        let registration = PushRegistration(server: server, userID: userID, webhookID: webhookID)
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
