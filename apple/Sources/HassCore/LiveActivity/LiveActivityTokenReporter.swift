import FentonActivityModel
import Foundation

/// Tells Home Assistant how to reach this phone's Home activity: the push-to-start token that lets it start one while
/// the app is closed, and each activity's update token (`live-activities.md` §6, "Token registration").
///
/// - The start token rides in the registration's `app_data` (`start_live_activity_token`); a change asks the
///   registration to sync (`registerStartToken`). Turning Live Activities off in Settings removes it, and turning
///   them on again puts the last token back.
/// - For every activity the system reports, including one a push started while the app was closed, it sends the
///   update token as `live_activity_token` (valid for the activity's 8 hours), and `live_activity_dismissed` once
///   the activity ends or is swiped away, so `mobile_app` never pushes to a dead activity.
@MainActor
public final class LiveActivityTokenReporter {
    private let client: any LiveActivityClient
    private let webhook: @Sendable () -> (any LiveActivityWebhookSending)?
    private let registerStartToken: @MainActor @Sendable (String?) async -> Void
    private let now: @Sendable () -> Date
    private var tasks: [Task<Void, Never>] = []
    private var perActivity: [String: [Task<Void, Never>]] = [:]
    private var lastStartToken: String?
    private var enabled = true

    /// Creates a reporter.
    /// - Parameters:
    ///   - client: ActivityKit.
    ///   - webhook: The signed-in registration's webhook sender, read at send time; nil while unregistered (a report
    ///     is then skipped and the next token change or launch sends it again).
    ///   - registerStartToken: Hands the start token (nil to remove it) to the registration, which syncs.
    ///   - now: The clock.
    public init(client: any LiveActivityClient, webhook: @escaping @Sendable () -> (any LiveActivityWebhookSending)?,
                registerStartToken: @escaping @MainActor @Sendable (String?) async -> Void,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.webhook = webhook
        self.registerStartToken = registerStartToken
        self.now = now
    }

    /// Starts watching tokens, activities and the enablement setting.
    public func start() {
        guard tasks.isEmpty else { return }
        enabled = client.areActivitiesEnabled
        tasks = [
            Task { [weak self, client] in
                for await token in client.pushToStartTokens() { await self?.startTokenChanged(token) }
            },
            Task { [weak self, client] in
                for await record in client.activityUpdates() { self?.observe(record) }
            },
            Task { [weak self, client] in
                for await isEnabled in client.enablementUpdates() { await self?.enablementChanged(isEnabled) }
            },
        ]
        Task { [weak self, client] in
            for record in await client.current() where record.lifecycle.isLive { self?.observe(record) }
        }
    }

    /// Stops watching (sign-out).
    public func stop() {
        tasks.forEach { $0.cancel() }
        perActivity.values.joined().forEach { $0.cancel() }
        tasks = []
        perActivity = [:]
    }

    func startTokenChanged(_ token: String) async {
        lastStartToken = token
        if enabled { await registerStartToken(token) }
    }

    func enablementChanged(_ isEnabled: Bool) async {
        guard isEnabled != enabled else { return }
        enabled = isEnabled
        await registerStartToken(isEnabled ? lastStartToken : nil)
    }

    /// Follows one activity: its update token, and its end.
    func observe(_ record: LiveActivityRecord) {
        guard perActivity[record.id] == nil else { return }
        let tag = record.tag, id = record.id
        let jobs = record.state.jobs.map(\.id)
        perActivity[id] = [
            Task { [weak self, client] in
                for await token in client.pushTokenUpdates(id: id) { await self?.report(tag: tag, token: token) }
            },
            Task { [weak self, client] in
                for await lifecycle in client.lifecycleUpdates(id: id) where !lifecycle.isLive {
                    await self?.activityEnded(id: id, tag: tag, jobs: jobs, lifecycle: lifecycle)
                }
            },
        ]
    }

    private func report(tag: String, token: String) async {
        guard let webhook = webhook() else { return }
        try? await webhook.reportToken(tag: tag, token: token, expiresAt: now().addingTimeInterval(HomeActivityAttributes.maxLifetime))
    }

    private func activityEnded(id: String, tag: String, jobs: [String], lifecycle: LiveActivityLifecycle) async {
        // Sent before the watchers stop: this runs inside one of them, and a cancelled task cannot send.
        if let webhook = webhook() {
            try? await webhook.reportDismissed(tag: tag)
            if lifecycle == .dismissed {
                try? await webhook.fireEvent(LiveActivityEventType.dismissed, data: ["tag": tag, "jobs": jobs.joined(separator: ",")])
            }
        }
        perActivity[id]?.forEach { $0.cancel() }
        perActivity[id] = nil
    }
}
