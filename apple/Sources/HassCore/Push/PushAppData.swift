import Foundation

/// `app_data` for registration and `update_registration` (contract v1, rule 2).
public struct PushAppData: Equatable, Sendable {
    /// The relay URL; nil registers for websocket pushes only.
    public var pushURL: URL?
    /// The APNs device token, lowercase hex.
    public var pushToken: String?
    /// The token's gateway.
    public var apnsEnvironment: APNsEnvironment?
    /// `push_websocket_channel`: Home Assistant may push over the open websocket while the app is connected.
    ///
    /// Off until the app subscribes to `mobile_app/push_notification_channel`: claiming it without listening makes
    /// a registration without an APNs token look reachable, and Home Assistant then drops its notifications.
    public var websocketChannel: Bool

    /// Creates app data.
    public init(pushURL: URL?, pushToken: String?, apnsEnvironment: APNsEnvironment?, websocketChannel: Bool = false) {
        self.pushURL = pushURL
        self.pushToken = pushToken
        self.apnsEnvironment = apnsEnvironment
        self.websocketChannel = websocketChannel
    }

    /// Empty `app_data`: sent on sign-out so Home Assistant stops pushing to a signed-out phone.
    public static let cleared = PushAppData(pushURL: nil, pushToken: nil, apnsEnvironment: nil, websocketChannel: false)

    /// Push details for a config and token. APNs delivery needs both the relay URL and a token; without them the
    /// registration carries no push details until a later `update_registration` adds them.
    /// - Parameters:
    ///   - config: The integration's config.
    ///   - token: The APNs token, if the system issued one.
    ///   - environment: The token's gateway.
    public static func resolve(config: PushConfig, token: String?, environment: APNsEnvironment) -> PushAppData {
        guard config.available, let url = config.pushURL, let token, !token.isEmpty else {
            return PushAppData(pushURL: nil, pushToken: nil, apnsEnvironment: nil)
        }
        return PushAppData(pushURL: url, pushToken: token, apnsEnvironment: environment)
    }

    /// The JSON object.
    var json: [String: Any] {
        var object: [String: Any] = [:]
        if websocketChannel { object["push_websocket_channel"] = true }
        if let pushURL, let pushToken {
            object["push_url"] = pushURL.absoluteString
            object["push_token"] = pushToken
            if let apnsEnvironment { object["apns_environment"] = apnsEnvironment.rawValue }
        }
        return object
    }
}
