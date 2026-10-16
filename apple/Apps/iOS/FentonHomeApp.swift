import HassCore
import HassUI
import SwiftUI
import UIKit
import UserNotifications

@main
struct FentonHomeApp: App {
    @UIApplicationDelegateAdaptor(FentonHomeAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView(session: appDelegate.session)
        }
    }
}

/// Supplies supported orientations (iPhone stays portrait in Info.plist, iPad keeps all four, and a device with a
/// hinge, iPhone Duo, rotates folded or unfolded; owner, 2026-10-10) and forwards push callbacks to
/// ``PushCoordinator`` (`.agents/platforms/apple/push.md`); creates location reporting at launch
/// (`.agents/platforms/apple/location.md`).
final class FentonHomeAppDelegate: NSObject, UIApplicationDelegate {
    /// The app's push coordinator; the root view's session uses this one so system callbacks reach it. Journeys
    /// that don't register keep their webhooks in memory, so a test sign-out never touches a real registration.
    let push = PushLaunchPolicy.isEnabled()
        ? PushCoordinator(platform: .system)
        : PushCoordinator(platform: .system, store: InMemoryMobileAppRegistrationStore(), isEnabled: false)

    /// Location reporting on phones (shadow mode); nil on iPad. Created with the delegate, before launch finishes,
    /// so a relaunch for a zone event reopens the zone monitor.
    private(set) lazy var location: LocationCoordinator? =
        LocationLaunchPolicy.isEnabled(isPresenceDevice: LocationReporter.deviceIsPresenceDevice)
            ? LocationCoordinator.system(mobileApp: push.mobileApp) : nil

    /// The app's one session (sign-in, connection, route). Made once here: `FentonHomeApp.body` and `RootView.init`
    /// run again whenever SwiftUI rebuilds the scene.
    @MainActor lazy var session = AppSession(push: push, location: location)

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Set before launch finishes, so a tap that launched the app is delivered.
        UNUserNotificationCenter.current().delegate = self
        if let location { Task { await location.resume() } }
        #if DEBUG
        PushPreview.scheduleIfRequested()
        if let command = PushPreview.command() {
            Task {
                try? await Task.sleep(for: .seconds(2))
                await push.handleBackground(userInfo: command)
            }
        }
        #endif
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        FentonOrientationSupport.mask(for: window)
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await push.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        // Without a token the registration stays websocket-only; the next launch tries again.
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await push.handleBackground(userInfo: userInfo) ? .newData : .noData
    }
}

// MARK: - Notification center

extension FentonHomeAppDelegate: @preconcurrency UNUserNotificationCenterDelegate {
    /// Shows a notification that arrives while the app is open, like the system does when it is not
    /// (HIG Notifications: people expect the same alert either way).
    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let action: NotificationResponse = switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier: .open
        case UNNotificationDismissActionIdentifier: .dismiss
        default: .action(response.actionIdentifier, replyText: (response as? UNTextInputNotificationResponse)?.userText)
        }
        Task {
            await push.handle(action, userInfo: userInfo)
            completionHandler()
        }
    }
}
