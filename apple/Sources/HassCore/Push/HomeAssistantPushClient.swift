import Foundation

/// Talks to Home Assistant for the Fenton Push config and the shared `mobile_app` registration (``MobileAppRegistrar``):
/// register, `update_registration`, and notification button events on its webhook.
///
/// Plain REST like ``HomeAssistantFeedbackClient``, over the same injectable ``FeedbackHTTPTransport`` seam:
/// registration is a one-off HTTP exchange, not state, so it stays off the websocket. Webhook calls carry no
/// token; the webhook id addresses them (Home Assistant's `mobile_app` design), which is why a button press works
/// before the app has refreshed its access token.
public struct HomeAssistantPushClient: Sendable {
    private let server: HassServer
    private let accessToken: @Sendable () async throws -> String
    private let transport: any FeedbackHTTPTransport

    /// Creates a client.
    /// - Parameters:
    ///   - server: The signed-in Home Assistant.
    ///   - accessToken: A valid access token (``TokenManager/validAccessToken()``).
    ///   - transport: The HTTP seam (tests use a stub).
    public init(server: HassServer, accessToken: @escaping @Sendable () async throws -> String,
                transport: any FeedbackHTTPTransport = URLSessionFeedbackTransport()) {
        self.server = server
        self.accessToken = accessToken
        self.transport = transport
    }

    static let configPath = "/api/fenton_push/config"
    static let registrationsPath = "/api/mobile_app/registrations"

    /// Reads the integration's config.
    /// - Returns: The config, or nil when the integration is not installed (404); the phone then registers without
    ///   push details.
    public func config() async throws -> PushConfig? {
        let (data, response) = try await send(try await authorized("GET", Self.configPath))
        if response.statusCode == 404 { return nil }
        guard (200..<300).contains(response.statusCode) else { throw PushClientError.status(response.statusCode) }
        return PushConfig(json: data)
    }

    /// Registers this phone with `mobile_app` as the token's user.
    /// - Returns: The new webhook id.
    public func register(_ device: MobileAppDevice, appData: PushAppData) async throws -> String {
        var request = try await authorized("POST", Self.registrationsPath)
        request.httpBody = try JSONSerialization.data(withJSONObject: device.registrationBody(appData: appData), options: [.sortedKeys])
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else { throw PushClientError.status(response.statusCode) }
        guard let id = object(data)?["webhook_id"] as? String, !id.isEmpty else { throw PushClientError.unexpectedResponse }
        return id
    }

    /// Sends `update_registration` (launch, token change, and ``PushAppData/cleared`` on sign-out).
    public func updateRegistration(_ registration: MobileAppRegistration, device: MobileAppDevice, appData: PushAppData) async throws {
        try await webhook(registration, body: device.updateBody(appData: appData))
    }

    /// Fires `mobile_app_notification_action` for a notification button (contract v1, rule 4).
    public func fireAction(_ registration: MobileAppRegistration, event: PushActionEvent) async throws {
        try await webhook(registration, body: event.webhookBody)
    }

    // MARK: - HTTP

    private func webhook(_ registration: MobileAppRegistration, body: [String: Any]) async throws {
        var request = URLRequest(url: registration.webhookURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let (_, response) = try await send(request)
        if response.statusCode == 410 { throw PushClientError.registrationGone }
        guard (200..<300).contains(response.statusCode) else { throw PushClientError.status(response.statusCode) }
    }

    private func authorized(_ method: String, _ path: String) async throws -> URLRequest {
        let token: String
        do {
            token = try await accessToken()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PushClientError.signedOut
        }
        var request = URLRequest(url: server.url(path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PushClientError.network
        }
    }

    private func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
