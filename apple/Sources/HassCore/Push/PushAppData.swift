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
    public var websocketChannel: Bool

    /// Creates app data.
    public init(pushURL: URL?, pushToken: String?, apnsEnvironment: APNsEnvironment?, websocketChannel: Bool = true) {
        self.pushURL = pushURL
        self.pushToken = pushToken
        self.apnsEnvironment = apnsEnvironment
        self.websocketChannel = websocketChannel
    }

    /// Empty `app_data`: sent on sign-out so Home Assistant stops pushing to a signed-out phone.
    public static let cleared = PushAppData(pushURL: nil, pushToken: nil, apnsEnvironment: nil, websocketChannel: false)

    /// Push details for a config and token. APNs delivery needs both the relay URL and a token; otherwise the
    /// registration is websocket-only.
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
        if self == .cleared { return [:] }
        var object: [String: Any] = ["push_websocket_channel": websocketChannel]
        if let pushURL, let pushToken {
            object["push_url"] = pushURL.absoluteString
            object["push_token"] = pushToken
            if let apnsEnvironment { object["apns_environment"] = apnsEnvironment.rawValue }
        }
        return object
    }
}
