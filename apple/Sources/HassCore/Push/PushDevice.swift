import Foundation

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
