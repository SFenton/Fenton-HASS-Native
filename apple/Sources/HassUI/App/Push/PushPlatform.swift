import Foundation
import HassCore
import Observation

/// The system services the coordinator uses; the app supplies UIKit and UserNotifications, tests supply stubs.
public struct PushPlatform: Sendable {
    /// This phone's registration facts.
    public var device: @MainActor @Sendable () -> PushDevice
    /// Asks for alert, sound and badge permission (once; later calls return the stored answer).
    public var requestAuthorization: @Sendable () async -> Bool
    /// `UIApplication.registerForRemoteNotifications()`.
    public var registerForRemoteNotifications: @MainActor @Sendable () -> Void
    /// Notifications in Notification Center now.
    public var deliveredNotifications: @Sendable () async -> [DeliveredNotification]
    /// Removes notifications from Notification Center.
    public var removeDelivered: @Sendable ([String]) -> Void
    /// Opens a web address outside the app.
    public var openExternal: @MainActor @Sendable (URL) -> Void

    /// Creates a platform.
    public init(device: @escaping @MainActor @Sendable () -> PushDevice,
                requestAuthorization: @escaping @Sendable () async -> Bool,
                registerForRemoteNotifications: @escaping @MainActor @Sendable () -> Void,
                deliveredNotifications: @escaping @Sendable () async -> [DeliveredNotification],
                removeDelivered: @escaping @Sendable ([String]) -> Void,
                openExternal: @escaping @MainActor @Sendable (URL) -> Void) {
        self.device = device
        self.requestAuthorization = requestAuthorization
        self.registerForRemoteNotifications = registerForRemoteNotifications
        self.deliveredNotifications = deliveredNotifications
        self.removeDelivered = removeDelivered
        self.openExternal = openExternal
    }

    /// A platform that does nothing (previews, the debug gallery, and UI journeys that must not prompt).
    public static let inert = PushPlatform(
        device: { PushDevice(marketingVersion: "0", build: "0", name: "Preview", model: "Preview", osVersion: "0",
                             deviceID: "preview", apnsEnvironment: .sandbox) },
        requestAuthorization: { false },
        registerForRemoteNotifications: {},
        deliveredNotifications: { [] },
        removeDelivered: { _ in },
        openExternal: { _ in }
    )
}
