import HassDesign
import SwiftUI

/// The words the notification permission prompts use (HIG Notifications: say what the alerts are for before the
/// system alert). Owner decision 2026-10-23, `.agents/design/mockups/proposals/widgets-push-siri-watch`.
enum NotificationPermissionCopy {
    static let title = "Get door and camera alerts"
    static let message = "S+H can tell you when a door is left open or someone rings."
    static let turnOn = "Turn On Notifications"
    static let notNow = "Not Now"
}

/// The one-time Home banner that explains notifications and asks on a tap. It shows only while the person has
/// never been asked and has not chosen Not Now; the Settings row stays either way.
struct NotificationPermissionBanner: View {
    @Environment(PushCoordinator.self) private var push: PushCoordinator?

    var body: some View {
        if let push, push.showsPermissionBanner {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                    Label(NotificationPermissionCopy.title, systemImage: "bell.badge.fill")
                        .font(.headline)
                        .foregroundStyle(HassTokens.Ink.onDark)
                    Text(NotificationPermissionCopy.message)
                        .font(.subheadline)
                        .foregroundStyle(HassTokens.Ink.onDarkSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("push.banner.text")
                Button(NotificationPermissionCopy.turnOn) { Task { await push.enableNotifications() } }
                    .buttonStyle(.borderedProminent)
                    .tint(HassTokens.Ink.actionFill)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("push.banner.turnOn")
                Button(NotificationPermissionCopy.notNow) { push.dismissPermissionBanner() }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("push.banner.notNow")
            }
            .padding(HassTokens.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HassTokens.Surface.moduleThin, in: RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("push.banner")
        }
    }
}

/// Settings → Notifications: the same ask as the Home banner, and a way to Settings once it was refused.
struct NotificationsSettingsSection: View {
    @Environment(PushCoordinator.self) private var push: PushCoordinator?
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let push {
            Section {
                switch push.authorization {
                case .notDetermined:
                    Button(NotificationPermissionCopy.turnOn) { Task { await push.enableNotifications() } }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("settings.notifications.turnOn")
                case .granted:
                    Label("Notifications are on", systemImage: "bell.fill")
                        .accessibilityIdentifier("settings.notifications.on")
                case .denied:
                    Button("Open Settings to allow notifications") { openSystemSettings() }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("settings.notifications.openSettings")
                }
            } header: {
                SettingsSectionHeader("Notifications")
            } footer: {
                Text(NotificationPermissionCopy.message)
            }
        }
    }

    private func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        #endif
    }
}
