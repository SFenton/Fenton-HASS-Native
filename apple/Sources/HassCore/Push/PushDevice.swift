import Foundation

/// The app's `mobile_app` identity (contract v1, rule 2).
public enum PushApp {
    /// `app_id`: the app's bundle identifier.
    public static let appID = "com.sfenton.home"
    /// `app_name`.
    public static let appName = "Fenton Home"
    /// Suffix on every `device_name`, so Home Assistant names this app's notify service apart from the official
    /// companion app's on the same phone (`notify.mobile_app_<device>_fenton`).
    public static let deviceNameSuffix = " · Fenton"
}

/// The APNs environment a build's device token belongs to. The relay must send to the matching gateway.
public enum APNsEnvironment: String, Codable, Sendable {
    /// Xcode-installed builds and the simulator.
    case sandbox
    /// TestFlight and App Store builds.
    case production

    /// Reads the environment from the embedded provisioning profile's `aps-environment` entitlement. No profile
    /// means an App Store install (production) on a device, or the simulator (sandbox).
    /// - Parameters:
    ///   - provisioningProfile: `embedded.mobileprovision`, if the bundle has one.
    ///   - isSimulator: Running in the simulator.
    public static func detect(provisioningProfile: Data?, isSimulator: Bool) -> APNsEnvironment {
        if isSimulator { return .sandbox }
        guard let profile = provisioningProfile else { return .production }
        // The profile is a CMS envelope around a plain XML plist; the entitlement is readable as text.
        let text = String(decoding: profile, as: UTF8.self)
        guard let key = text.range(of: "<key>aps-environment</key>"),
              let open = text.range(of: "<string>", range: key.upperBound..<text.endIndex),
              let close = text.range(of: "</string>", range: open.upperBound..<text.endIndex)
        else { return .sandbox }
        return text[open.upperBound..<close.lowerBound] == "production" ? .production : .sandbox
    }
}

/// The device facts `mobile_app` registration sends (contract v1, rule 2).
public struct PushDevice: Equatable, Sendable {
    /// `app_version`: `"<marketing> (<build>)"`.
    public var appVersion: String
    /// `device_name`, already carrying ``PushApp/deviceNameSuffix``.
    public var deviceName: String
    /// `model`: the hardware identifier (`hw.machine`, e.g. `iPhone18,1`).
    public var model: String
    /// `os_version`.
    public var osVersion: String
    /// `device_id`: `identifierForVendor`.
    public var deviceID: String
    /// Which APNs gateway the token belongs to.
    public var apnsEnvironment: APNsEnvironment

    /// Creates a device description.
    /// - Parameters:
    ///   - marketingVersion: `CFBundleShortVersionString`.
    ///   - build: `CFBundleVersion`.
    ///   - name: The device's name (`UIDevice.name`); the Fenton suffix is added here.
    ///   - model: Hardware identifier.
    ///   - osVersion: System version.
    ///   - deviceID: `identifierForVendor`.
    ///   - apnsEnvironment: The token's gateway.
    public init(marketingVersion: String, build: String, name: String, model: String, osVersion: String,
                deviceID: String, apnsEnvironment: APNsEnvironment) {
        appVersion = "\(marketingVersion) (\(build))"
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        deviceName = (trimmed.isEmpty ? "iPhone" : trimmed) + PushApp.deviceNameSuffix
        self.model = model
        self.osVersion = osVersion
        self.deviceID = deviceID
        self.apnsEnvironment = apnsEnvironment
    }

    /// The registration body for `POST /api/mobile_app/registrations`.
    /// - Parameter appData: The push details to send.
    func registrationBody(appData: PushAppData) -> [String: Any] {
        [
            "app_id": PushApp.appID,
            "app_name": PushApp.appName,
            "app_version": appVersion,
            "device_name": deviceName,
            "manufacturer": "Apple",
            "model": model,
            "os_name": "iOS",
            "os_version": osVersion,
            "device_id": deviceID,
            "supports_encryption": false,
            "app_data": appData.json,
        ]
    }

    /// The `update_registration` webhook body.
    /// - Parameter appData: The push details to send; ``PushAppData/cleared`` on sign-out.
    func updateBody(appData: PushAppData) -> [String: Any] {
        [
            "type": "update_registration",
            "data": [
                "app_data": appData.json,
                "app_version": appVersion,
                "device_name": deviceName,
                "manufacturer": "Apple",
                "model": model,
                "os_version": osVersion,
            ] as [String: Any],
        ]
    }
}

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

/// Formats an APNs device token.
public enum PushToken {
    /// The token as lowercase hex, the form the relay expects.
    public static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }
}
