import Foundation

/// One `mobile_app` registration: the webhook Home Assistant issued to this phone for one user on one server.
public struct PushRegistration: Codable, Equatable, Sendable {
    /// The server registered with.
    public var server: HassServer
    /// The Home Assistant user the registration belongs to.
    public var userID: String
    /// The webhook id; it addresses the registration, so it is kept in the Keychain like a credential.
    public var webhookID: String

    /// Creates a registration.
    public init(server: HassServer, userID: String, webhookID: String) {
        self.server = server
        self.userID = userID
        self.webhookID = webhookID
    }

    /// `POST` target for webhook commands.
    public var webhookURL: URL { server.url("/api/webhook/\(webhookID)") }
}
