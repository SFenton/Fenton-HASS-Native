import FentonActivityModel
import Foundation
import HassCore
import Observation

/// The Home Live Activity for the signed-in session (`.agents/platforms/apple/live-activities.md`).
///
/// - **Tokens**: reports the push-to-start token with the registration and each activity's update token to Home
///   Assistant (``LiveActivityTokenReporter``), so the server can start and update the activity while the app is closed.
/// - **Foreground**: while the app is open, watches the dishwasher and bathroom fan timer entities through
///   ``EntityStore`` and starts, updates and ends the activity locally (``HomeActivityDirector``). One state path:
///   the entities come from the store the whole app reads, never a second socket.
///
/// Created with the app delegate and started with each session; ended with the sign-out so nothing of the signed-in
/// person stays on a Lock Screen.
@MainActor
@Observable
public final class LiveActivityCoordinator {
    /// Whether the feature runs in this launch (``LiveActivityLaunchPolicy``).
    public let isEnabled: Bool

    @ObservationIgnored private let client: any LiveActivityClient
    @ObservationIgnored private let mobileApp: MobileAppCoordinator
    @ObservationIgnored private let director: HomeActivityDirector
    @ObservationIgnored private let reporter: LiveActivityTokenReporter
    @ObservationIgnored private var store: EntityStore?
    @ObservationIgnored private var generation = 0

    /// Creates a coordinator.
    /// - Parameters:
    ///   - client: ActivityKit, or a fake in tests.
    ///   - mobileApp: The shared registration, which carries the push-to-start token and the webhook.
    ///   - isEnabled: Run at all; off for journeys signed in with a test token.
    ///   - now: The clock.
    public init(client: any LiveActivityClient, mobileApp: MobileAppCoordinator, isEnabled: Bool = true,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.mobileApp = mobileApp
        self.isEnabled = isEnabled
        director = HomeActivityDirector(client: client, now: now)
        reporter = LiveActivityTokenReporter(
            client: client, webhook: mobileApp.activityWebhookProvider(),
            registerStartToken: { [mobileApp] token in await mobileApp.registerStartActivityToken(token) }, now: now)
    }

    /// A coordinator that never starts anything.
    public static func inert(mobileApp: MobileAppCoordinator) -> LiveActivityCoordinator {
        LiveActivityCoordinator(client: InertLiveActivityClient(), mobileApp: mobileApp, isEnabled: false)
    }

    /// The handler for the activity's buttons (installed at launch with ``LiveActivityIntentRuntime/install(_:)``).
    public var intentHandler: any LiveActivityIntentRuntime.Handler {
        HomeActivityActionHandler(client: client, webhook: mobileApp.activityWebhookProvider())
    }

    // MARK: - Session

    /// A session started: report tokens, and follow the entities.
    /// - Parameter store: The session's entity store.
    public func sessionStarted(store: EntityStore) {
        guard isEnabled else { return }
        self.store = store
        generation += 1
        reporter.start()
        observe(generation: generation)
        Task { [director] in
            for record in await client.current() { director.adopt(record) }
        }
        reconcileIfLive()
    }

    /// Signing out: stop reporting and end the activity.
    public func sessionEnded() async {
        generation += 1
        store = nil
        reporter.stop()
        await director.endAll()
    }

    // MARK: - Following the entities

    /// Re-evaluates once the store holds live data; the disk snapshot a cold launch restores must not start an
    /// activity for a dishwasher that finished hours ago.
    func reconcileIfLive() {
        guard let store, store.freshness == .live else { return }
        Task { [director, weak store] in
            guard let store else { return }
            await director.reconcile(entity: { store.value($0) })
        }
    }

    private func observe(generation: Int) {
        guard let store else { return }
        let ids = director.watchedEntityIDs
        withObservationTracking {
            _ = store.freshness
            for id in ids { _ = store.entity(id).state }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                self.reconcileIfLive()
                self.observe(generation: generation)
            }
        }
    }
}

/// Whether Live Activities run in this launch.
public enum LiveActivityLaunchPolicy {
    /// Off for debug UI journeys (a test token, a reset launch, or the component gallery) unless
    /// `FENTON_LIVE_ACTIVITY` is set, so a journey never starts activities from the real house's dishwasher.
    public static func isEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        #if DEBUG
        if !(environment["FENTON_LIVE_ACTIVITY"] ?? "").isEmpty { return true }
        let journey = ["FENTON_HASS_TOKEN", "FENTON_UITEST_RESET", "FENTON_GALLERY"].contains { !(environment[$0] ?? "").isEmpty }
        return !journey
        #else
        return true
        #endif
    }
}
