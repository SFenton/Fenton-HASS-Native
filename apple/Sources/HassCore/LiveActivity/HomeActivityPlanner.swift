import FentonActivityModel
import Foundation

/// What to do with the Home activity after the jobs changed.
public enum HomeActivityDecision: Equatable, Sendable {
    /// Nothing to change.
    case none
    /// Start the activity.
    case start(HomeActivityState, staleDate: Date?)
    /// Update its content.
    case update(HomeActivityState, staleDate: Date?)
    /// End it, with this last content, and take it off the Lock Screen as the dismissal says.
    case end(HomeActivityState, LiveActivityDismissal)
}

/// Decides when the app starts, updates and ends the Home activity locally while it is open (`live-activities.md` §6).
///
/// - Starts when a job is running, activities are allowed, none exists and the person has not swiped away this very
///   list of jobs (rule 8: it comes back only when a *new* job joins).
/// - Updates when a job, a phase, a control or an end time changes; the focus the person paged to is kept while that
///   job is listed.
/// - When every job is done, ends it with the last content so the Lock Screen keeps the "Done" rows for the linger.
/// - When the last job disappears, ends it at once.
public struct HomeActivityPlanner: Sendable {
    /// How long a finished job stays on the Lock Screen (HIG: 15 to 30 minutes; owner question 7).
    public var linger: TimeInterval
    /// How long past the earliest end an activity may go without an update before the views read "Updating…".
    public var staleGrace: TimeInterval
    /// The stale date for a list with no end times.
    public var openEndedStale: TimeInterval

    /// Creates a planner.
    public init(linger: TimeInterval = 15 * 60, staleGrace: TimeInterval = 10 * 60, openEndedStale: TimeInterval = 30 * 60) {
        self.linger = linger
        self.staleGrace = staleGrace
        self.openEndedStale = openEndedStale
    }

    /// Decides.
    /// - Parameters:
    ///   - desired: The jobs running now.
    ///   - existing: The live Home activity, if there is one.
    ///   - suppressed: Jobs the person dismissed the activity over.
    ///   - enabled: Live Activities are allowed.
    ///   - now: The current time.
    public func decide(desired: [ActivityJob], existing: LiveActivityRecord?, suppressed: Set<String>, enabled: Bool,
                       now: Date) -> HomeActivityDecision {
        guard let existing, existing.lifecycle.isLive else {
            return startDecision(desired: desired, suppressed: suppressed, enabled: enabled, now: now)
        }
        guard !desired.isEmpty else { return .end(existing.state, .immediate) }
        let state = composed(desired, keepingFocusOf: existing.state)
        if state.isAllDone { return .end(state, .after(now.addingTimeInterval(linger))) }
        if state.jobs == existing.state.jobs && state.focus == existing.state.focus && state.url == existing.state.url {
            return .none
        }
        return .update(state, staleDate: staleDate(for: state, now: now))
    }

    private func startDecision(desired: [ActivityJob], suppressed: Set<String>, enabled: Bool, now: Date) -> HomeActivityDecision {
        guard enabled else { return .none }
        let active = desired.filter { $0.phase.isActive }
        guard active.contains(where: { !suppressed.contains($0.id) }) else { return .none }
        let state = composed(desired, keepingFocusOf: nil)
        return .start(state, staleDate: staleDate(for: state, now: now))
    }

    /// The state for `jobs`: the focus the person chose while it is still listed, else the first job; the tap
    /// target follows the focus.
    func composed(_ jobs: [ActivityJob], keepingFocusOf previous: HomeActivityState?) -> HomeActivityState {
        var state = HomeActivityState(jobs: jobs).fitted()
        if let focus = previous?.focus, state.jobs.contains(where: { $0.id == focus }) { state.focus = focus }
        state.url = state.focusedJob.map(HomeJobDeriver.url(for:))
        return state
    }

    /// Earliest end plus the grace, or a flat window when no job has an end (rule 6).
    func staleDate(for state: HomeActivityState, now: Date) -> Date {
        let ends = state.jobs.filter { $0.phase.isActive }.compactMap(\.endDate)
        if let earliest = ends.min() { return max(earliest, now).addingTimeInterval(staleGrace) }
        return now.addingTimeInterval(openEndedStale)
    }
}
