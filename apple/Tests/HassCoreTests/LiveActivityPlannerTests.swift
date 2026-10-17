import FentonActivityModel
import Foundation
@testable import HassCore
import Testing

struct HomeActivityPlannerTests {
    private let now = LiveActivityFixtures.now
    private let planner = HomeActivityPlanner()

    private func jobs(_ states: [EntityState]) -> [ActivityJob] {
        HomeJobDeriver().jobs(entity: LiveActivityFixtures.reader(states), now: now)
    }

    private func record(_ desired: [ActivityJob], focus: String? = nil, lifecycle: LiveActivityLifecycle = .active) -> LiveActivityRecord {
        var state = planner.composed(desired, keepingFocusOf: nil)
        state.focus = focus
        return LiveActivityRecord(id: "a1", attributes: HomeActivityAttributes(), state: state, lifecycle: lifecycle)
    }

    @Test func startsWhenAJobRunsAndActivitiesAreAllowed() {
        let desired = jobs(LiveActivityFixtures.dishwasher())
        guard case let .start(state, staleDate) = planner.decide(desired: desired, existing: nil, suppressed: [], enabled: true, now: now) else {
            Issue.record("expected a start")
            return
        }
        #expect(state.jobs == desired && state.url == "/sfenton-react-dash/home?path=kitchen")
        #expect(staleDate == now.addingTimeInterval(2_400 + 600), "the earliest end plus ten minutes")
    }

    @Test func doesNotStartWhenOffEmptyOnlyDoneOrSwipedAway() {
        let running = jobs(LiveActivityFixtures.dishwasher())
        #expect(planner.decide(desired: running, existing: nil, suppressed: [], enabled: false, now: now) == .none)
        #expect(planner.decide(desired: [], existing: nil, suppressed: [], enabled: true, now: now) == .none)
        let finished = jobs(LiveActivityFixtures.dishwasher(operation: "finished"))
        #expect(planner.decide(desired: finished, existing: nil, suppressed: [], enabled: true, now: now) == .none)
        #expect(planner.decide(desired: running, existing: nil, suppressed: ["dishwasher"], enabled: true, now: now) == .none)
        // A new job joining brings it back.
        let both = jobs(LiveActivityFixtures.dishwasher() + LiveActivityFixtures.fan())
        if case .start = planner.decide(desired: both, existing: nil, suppressed: ["dishwasher"], enabled: true, now: now) {} else {
            Issue.record("a new job should start the activity again")
        }
    }

    @Test func anEndedActivityDoesNotCountAsExisting() {
        let running = jobs(LiveActivityFixtures.dishwasher())
        let ended = record(running, lifecycle: .ended)
        if case .start = planner.decide(desired: running, existing: ended, suppressed: [], enabled: true, now: now) {} else {
            Issue.record("a new activity starts next to an ended one")
        }
    }

    @Test func updatesOnlyWhenSomethingChanged() {
        let running = jobs(LiveActivityFixtures.dishwasher())
        let existing = record(running)
        #expect(planner.decide(desired: running, existing: existing, suppressed: [], enabled: true, now: now) == .none)
        let paused = jobs(LiveActivityFixtures.dishwasher(operation: "pause"))
        guard case let .update(state, _) = planner.decide(desired: paused, existing: existing, suppressed: [], enabled: true, now: now) else {
            Issue.record("expected an update")
            return
        }
        #expect(state.jobs[0].phase == .paused)
    }

    @Test func thePagedFocusSurvivesUpdatesWhileListed() {
        let both = jobs(LiveActivityFixtures.dishwasher(finishesIn: 3_000) + LiveActivityFixtures.fan("master", minutes: 10))
        let existing = record(both, focus: "dishwasher")
        let changed = jobs(LiveActivityFixtures.dishwasher(finishesIn: 3_100) + LiveActivityFixtures.fan("master", minutes: 10))
        guard case let .update(state, _) = planner.decide(desired: changed, existing: existing, suppressed: [], enabled: true, now: now) else {
            Issue.record("expected an update")
            return
        }
        #expect(state.focus == "dishwasher" && state.url == "/sfenton-react-dash/home?path=kitchen")
        // The focused job leaves: the first remaining job is focused and the tap follows it.
        let fanOnly = jobs(LiveActivityFixtures.fan("master", minutes: 10))
        guard case let .update(after, _) = planner.decide(desired: fanOnly, existing: existing, suppressed: [], enabled: true, now: now) else {
            Issue.record("expected an update")
            return
        }
        #expect(after.focus == nil && after.url == "/sfenton-react-dash/home?path=master-bathroom")
    }

    @Test func endsAtOnceWhenTheLastJobVanishesAndLingersWhenAllAreDone() {
        let existing = record(jobs(LiveActivityFixtures.dishwasher()))
        guard case let .end(_, dismissal) = planner.decide(desired: [], existing: existing, suppressed: [], enabled: true, now: now) else {
            Issue.record("expected an end")
            return
        }
        #expect(dismissal == .immediate)
        let finished = jobs(LiveActivityFixtures.dishwasher(operation: "finished"))
        guard case let .end(state, linger) = planner.decide(desired: finished, existing: existing, suppressed: [], enabled: true, now: now) else {
            Issue.record("expected an end")
            return
        }
        #expect(state.isAllDone && linger == .after(now.addingTimeInterval(15 * 60)))
    }

    @Test func staleDatesFollowTheEarliestEndOrAFlatWindow() {
        let state = planner.composed(jobs(LiveActivityFixtures.dishwasher(finishesIn: 3_000) + LiveActivityFixtures.fan(minutes: 10)), keepingFocusOf: nil)
        #expect(planner.staleDate(for: state, now: now) == now.addingTimeInterval(600 + 600))
        let open = HomeActivityState(jobs: [ActivityJob(id: "x", kind: "x", title: "X", status: "")])
        #expect(planner.staleDate(for: open, now: now) == now.addingTimeInterval(30 * 60))
        let past = HomeActivityState(jobs: [ActivityJob(id: "x", kind: "x", title: "X", status: "", endTs: now.timeIntervalSince1970 - 99)])
        #expect(planner.staleDate(for: past, now: now) == now.addingTimeInterval(600), "never before now")
    }
}
