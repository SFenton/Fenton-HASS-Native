import FentonActivityModel
import Foundation

/// Starts, updates and ends the Home activity while the app is open (Phase 1 foreground path, `live-activities.md` §6).
///
/// The coordinator calls ``reconcile(entity:)`` whenever a watched entity changes. The director derives the jobs
/// (``HomeJobDeriver``), asks the ``HomeActivityPlanner`` what to do, and does it through the ``LiveActivityClient``.
/// Passes never overlap: a change that arrives during one is folded into one more pass, so the activity always ends
/// up showing the latest entities and never an older state that finished writing last.
///
/// It also remembers a person's dismissal: when the activity is swiped away while jobs run, it stays away until a
/// new job joins (rule 8).
@MainActor
public final class HomeActivityDirector {
    private let client: any LiveActivityClient
    private let deriver: HomeJobDeriver
    private let planner: HomeActivityPlanner
    private let now: @Sendable () -> Date
    /// Jobs the person swiped the activity away over; tests read it.
    private(set) var suppressed: Set<String> = []
    private var lastEntity: ((String) -> EntityState?)?
    /// A pass is running; tests wait on it.
    private(set) var isReconciling = false
    private var needsPass = false
    private var watchedDismissals: Set<String> = []
    /// Activities this director ended itself: their dismissal is not the person's.
    private var endedByUs: Set<String> = []
    private var dismissalTasks: [Task<Void, Never>] = []

    /// Passes completed; tests wait on it.
    public private(set) var passCount = 0

    /// Creates a director.
    /// - Parameters:
    ///   - client: ActivityKit.
    ///   - deriver: Reads the jobs from entities.
    ///   - planner: Decides.
    ///   - now: The clock.
    public init(client: any LiveActivityClient, deriver: HomeJobDeriver = HomeJobDeriver(),
                planner: HomeActivityPlanner = HomeActivityPlanner(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.deriver = deriver
        self.planner = planner
        self.now = now
    }

    /// The entities to watch.
    public var watchedEntityIDs: [String] { deriver.watchedEntityIDs }

    /// Re-evaluates against the current entities.
    /// - Parameter entity: Reads an entity's current state.
    public func reconcile(entity: @escaping (String) -> EntityState?) async {
        lastEntity = entity
        needsPass = true
        guard !isReconciling else { return }
        isReconciling = true
        defer { isReconciling = false }
        while needsPass, let entity = lastEntity {
            needsPass = false
            await pass(entity: entity)
            passCount += 1
        }
    }

    /// Ends every Home activity at once (sign-out): nothing of the signed-in person may stay on a Lock Screen.
    public func endAll() async {
        dismissalTasks.forEach { $0.cancel() }
        dismissalTasks = []
        lastEntity = nil
        needsPass = false
        suppressed = []
        for record in await client.current() where record.attributes.tag == HomeActivityAttributes.homeTag && record.lifecycle.isLive {
            endedByUs.insert(record.id)
            await client.end(id: record.id, state: nil, dismissal: .immediate)
        }
    }

    private func pass(entity: (String) -> EntityState?) async {
        let current = now()
        let desired = deriver.jobs(entity: entity, now: current)
        let home = await client.current().first { $0.attributes.tag == HomeActivityAttributes.homeTag && $0.lifecycle.isLive }
        if desired.isEmpty { suppressed = [] }
        let decision = planner.decide(desired: desired, existing: home, suppressed: suppressed, enabled: client.areActivitiesEnabled, now: current)
        switch decision {
        case .none:
            break
        case let .start(state, staleDate):
            if let record = try? await client.request(attributes: HomeActivityAttributes(), state: state, staleDate: staleDate) {
                watchDismissal(of: record)
            }
        case let .update(state, staleDate):
            if let home { await client.update(id: home.id, state: state, staleDate: staleDate) }
        case let .end(state, dismissal):
            if let home {
                endedByUs.insert(home.id)
                await client.end(id: home.id, state: state, dismissal: dismissal)
            }
        }
    }

    /// Notes the jobs on screen when the person swipes the activity away, so the same jobs do not bring it back.
    private func watchDismissal(of record: LiveActivityRecord) {
        guard watchedDismissals.insert(record.id).inserted else { return }
        let id = record.id
        dismissalTasks.append(Task { [weak self, client] in
            for await lifecycle in client.lifecycleUpdates(id: id) where lifecycle == .dismissed {
                await self?.dismissedByPerson(id: id)
            }
        })
    }

    private func dismissedByPerson(id: String) async {
        guard !endedByUs.contains(id), let entity = lastEntity else { return }
        let jobs = deriver.jobs(entity: entity, now: now()).filter { $0.phase.isActive }.map(\.id)
        suppressed.formUnion(jobs)
    }

    /// Adopts an activity that already exists (a push started it while the app was closed) so a later swipe-away is
    /// noticed too.
    public func adopt(_ record: LiveActivityRecord) {
        if record.attributes.tag == HomeActivityAttributes.homeTag { watchDismissal(of: record) }
    }
}
