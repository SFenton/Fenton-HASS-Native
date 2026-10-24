import Foundation
import HassCore
@testable import HassUI
import SwiftUI
import Testing

/// The Home banner and the Settings row render in every state and at the largest text size; their tap logic is in
/// `PushCoordinatorTests`.
@MainActor
struct NotificationPermissionViewTests {
    private func coordinator(_ status: PushAuthorization) async -> PushCoordinator {
        let platform = PushPlatform(
            device: { MobileAppDevice(marketingVersion: "1", build: "1", name: "T", model: "iPhone18,1", osVersion: "27",
                                 deviceID: "d", apnsEnvironment: .sandbox) },
            authorization: { status }, requestAuthorization: { true }, registerForRemoteNotifications: {},
            deliveredNotifications: { [] }, removeDelivered: { _ in }, openExternal: { _ in })
        let suite = "perm-view-\(UUID().uuidString)"
        let push = PushCoordinator(platform: platform, store: InMemoryMobileAppRegistrationStore(),
                                   defaults: UserDefaults(suiteName: suite)!)
        await push.didConnect(userID: "u")
        return push
    }

    @Test(arguments: [PushAuthorization.notDetermined, .granted, .denied])
    func bannerAndRowRenderAtDefaultAndAX5(status: PushAuthorization) async {
        let push = await coordinator(status)
        #expect(push.showsPermissionBanner == (status == .notDetermined))
        for size in [DynamicTypeSize.large, .accessibility5] {
            let banner = NotificationPermissionBanner().environment(push).dynamicTypeSize(size).frame(width: 390)
            #expect(ImageRenderer(content: banner).cgImage != nil)
            let list = List { NotificationsSettingsSection() }.environment(push).dynamicTypeSize(size).frame(width: 390, height: 600)
            #expect(ImageRenderer(content: list).cgImage != nil)
        }
    }
}
