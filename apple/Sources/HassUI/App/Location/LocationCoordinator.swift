import Foundation
import HassCore
import Observation
#if os(iOS)
import UIKit
#endif

/// Location reporting for the signed-in session (`.agents/platforms/apple/location.md`).
///
/// Phones only: the app creates one only when ``LocationLaunchPolicy`` allows it, never on iPad. It reports to the
/// app's own `mobile_app` device tracker through the shared registration; ``MobileAppCoordinator/linkPresence(user:api:)``
/// puts that tracker on the signed-in user's person.
///
/// - Starts the ``LocationReporter`` whenever a webhook exists (this session's sync, or one saved by an earlier
///   launch) and the permission allows it; there is no separate switch. Stops on sign-out.
/// - Offers the permission screen once per install, after sign-in.
/// - A deleted registration (410) syncs once more, which registers again, and reporting resumes on the new webhook.
@MainActor
@Observable
public final class LocationCoordinator {
    /// The reporter this session drives.
    public let reporter: LocationReporter
    /// Whether the permission screen shows.
    public var isPresentingPermission = false
    /// Whether the app already asked to upgrade to Always. iOS shows that alert once; afterwards the While Using
    /// stage sends people to Settings.
    public private(set) var hasAskedForAlways: Bool

    /// What the last attempt to put this phone on its person did, for Settings.
    public var mobileAppPresenceLink: PresenceLinkOutcome? { mobileApp.presenceLink }

    @ObservationIgnored private let mobileApp: MobileAppCoordinator
    @ObservationIgnored private let defaults: UserDefaults
    /// Set while a sync after a 410 runs, so one deleted registration re-registers at most once per start.
    @ObservationIgnored private var isRecovering = false

    /// `UserDefaults` key: the permission screen was offered after sign-in.
    static let offeredKey = "location.permissionOffered"
    /// `UserDefaults` key: the Always alert was shown.
    static let askedForAlwaysKey = "location.askedForAlways"

    /// Creates a coordinator.
    /// - Parameters:
    ///   - platform: Core Location, or a fake in tests.
    ///   - mobileApp: The shared registration.
    ///   - transport: HTTP to Home Assistant.
    ///   - batteryLevel: The battery percentage sent with each update.
    ///   - defaults: Where the once-per-install flags live.
    public init(platform: any LocationPlatform, mobileApp: MobileAppCoordinator,
                transport: any FeedbackHTTPTransport = URLSessionFeedbackTransport(),
                batteryLevel: @escaping @MainActor () -> Int? = { nil }, defaults: UserDefaults = .standard) {
        let client = MobileAppWebhookClient(source: mobileApp.webhookSource, transport: transport)
        reporter = LocationReporter(platform: platform, client: client, isPresenceDevice: true, batteryLevel: batteryLevel)
        self.mobileApp = mobileApp
        self.defaults = defaults
        hasAskedForAlways = defaults.bool(forKey: Self.askedForAlwaysKey)
        mobileApp.onRegistrationChange { [weak self] registration in
            Task { await self?.registrationChanged(registration) }
        }
        reporter.onPermissionChange = { [weak self] permission in
            Task { await self?.permissionChanged(permission) }
        }
    }

    // MARK: - Lifecycle

    /// The app launched (in the foreground or for a location event): report on the webhook saved by an earlier
    /// launch, without waiting for the websocket.
    public func resume() async {
        await startIfReady()
    }

    /// The app came to the foreground: send a fix (the only report While Using allows), or start if a webhook
    /// and permission arrived while it was away.
    public func didBecomeActive() async {
        if reporter.isRunning {
            await reporter.report(.launch)
            await recoverIfGone()
        } else {
            await startIfReady()
        }
    }

    /// Whether a webhook exists to send to.
    private var hasWebhook: Bool { mobileApp.registration != nil || mobileApp.savedWebhookExists }

    /// Off (denied, restricted, or no longer precise enough to say home): stop and take the phone off its person so
    /// it doesn't hold a stale "home". On: start at once (a fresh update, zones again) and put it back on.
    func permissionChanged(_ permission: LocationPermission) async {
        if permission.isAuthorized {
            await startIfReady()
            await mobileApp.locationRestored()
        } else {
            await reporter.stop()
            await mobileApp.locationWithdrawn()
        }
    }

    func startIfReady() async {
        guard hasWebhook, reporter.permission.isAuthorized, !reporter.isRunning else { return }
        await reporter.start()
        await recoverIfGone()
    }

    func registrationChanged(_ registration: MobileAppRegistration?) async {
        if registration == nil {
            await reporter.stop()
        } else {
            await startIfReady()
        }
    }

    /// After a 410 the reporter has stopped; one sync registers again, and the new registration restarts it.
    private func recoverIfGone() async {
        guard reporter.lastError == .registrationGone, !isRecovering else { return }
        isRecovering = true
        defer { isRecovering = false }
        await mobileApp.sync()
    }

    // MARK: - Permission

    /// Signed in and connected: shows the permission screen once per install while there is something to ask.
    public func offerPermissionIfNeeded() {
        guard !defaults.bool(forKey: Self.offeredKey) else { return }
        switch reporter.permission.stage {
        case .notDetermined: break
        case .whenInUse where !hasAskedForAlways: break
        default: return
        }
        defaults.set(true, forKey: Self.offeredKey)
        isPresentingPermission = true
    }

    /// Shows the next system alert, remembering the Always request (iOS shows it once).
    public func requestPermission() {
        if reporter.permission.authorization == .whenInUse {
            hasAskedForAlways = true
            defaults.set(true, forKey: Self.askedForAlwaysKey)
        }
        reporter.requestPermission()
    }

    /// Forgets the once-per-install flags (UI journeys that start from a reset).
    public static func resetOffers(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: offeredKey)
        defaults.removeObject(forKey: askedForAlwaysKey)
    }
}

#if os(iOS)
public extension LocationCoordinator {
    /// The app's coordinator on Core Location, sending the battery level with each update. Create it at launch, on
    /// the main thread, so a relaunch for a zone event reopens the zone monitor.
    static func system(mobileApp: MobileAppCoordinator) -> LocationCoordinator {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return LocationCoordinator(platform: CoreLocationPlatform(), mobileApp: mobileApp, batteryLevel: {
            let level = UIDevice.current.batteryLevel
            return level < 0 ? nil : Int((level * 100).rounded())
        })
    }
}
#endif
