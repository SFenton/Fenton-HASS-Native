import FentonActivityModel
import Foundation
@testable import HassCore
import Testing

@MainActor
struct HomeActivityDirectorTests {
    private let now = LiveActivityFixtures.now

    private func director(_ client: FakeLiveActivityClient) -> HomeActivityDirector {
        let now = now
        return HomeActivityDirector(client: client, now: { now })
    }

    @Test func startsUpdatesAndEndsFromEntityChanges() async {
        let client = FakeLiveActivityClient()
        let director = director(client)
        await director.reconcile(entity: LiveActivityFixtures.reader(LiveActivityFixtures.dishwasher()))
        #expect(client.activities.count == 1)
        guard case .request? = client.calls.first else { Issue.record("expected a request"); return }

        await director.reconcile(entity: LiveActivityFixtures.reader(LiveActivityFixtures.dishwasher(progress: "70")))
        guard case .update? = client.calls.last else { Issue.record("expected an update"); return }
        #expect(client.activities[0].state.jobs[0].status == "Eco 50° · 70%")

        let before = client.calls.count
        await director.reconcile(entity: LiveActivityFixtures.reader(LiveActivityFixtures.dishwasher(progress: "70")))
        #expect(client.calls.count == before, "nothing changed")

        await director.reconcile(entity: LiveActivityFixtures.reader(LiveActivityFixtures.dishwasher(operation: "finished")))
        guard case let .end(_, state, dismissal)? = client.calls.last else { Issue.record("expected an end"); return }
        #expect(state?.isAllDone == true && dismissal == .after(now.addingTimeInterval(15 * 60)))
        #expect(director.passCount == 4)
    }

    @Test func aChangeDuringAPassIsFoldedIntoOneMorePass() async {
        let client = FakeLiveActivityClient()
        let director = director(client)
        client.holdNextCurrent()
        let first = Task { await director.reconcile(entity: LiveActivityFixtures.reader(LiveActivityFixtures.dishwasher())) }
        #expect(await eventually { client.isHoldingCurrent })
        // Arrives mid-pass: it is folded into one more pass rather than racing the first.
        await director.reconcile(entity: LiveActivityFixtures.reader(LiveActivityFixtures.dishwasher(progress: "80")))
        client.releaseCurrent()
        await first.value
        #expect(director.passCount == 2)
        #expect(client.activities.count == 1)
        #expect(client.activities[0].state.jobs[0].status == "Eco 50° · 80%", "the latest entities win")
    }

    @Test func doesNothingWhenActivitiesAreOffOrAStartIsRefused() async {
        let off = FakeLiveActivityClient(enabled: false)
        await director(off).reconcile(entity: LiveActivityFixtures.reader(LiveActivityFixtures.dishwasher()))
        #expect(off.calls.isEmpty)
        let refused = FakeLiveActivityClient()
        refused.requestError = .refused("targetMaximumExceeded")
        await director(refused).reconcile(entity: LiveActivityFixtures.reader(LiveActivityFixtures.dishwasher()))
        #expect(refused.activities.isEmpty)
    }

    @Test func aSwipeAwayKeepsTheSameJobsFromBringingItBack() async {
        let client = FakeLiveActivityClient()
        let director = director(client)
        let running = LiveActivityFixtures.reader(LiveActivityFixtures.dishwasher())
        await director.reconcile(entity: running)
        #expect(await eventually { client.isWatchingLifecycle(of: "act-1") })
        client.emitLifecycle(id: "act-1", .dismissed)
        #expect(await eventually { director.suppressed.contains("dishwasher") })

        await director.reconcile(entity: running)
        #expect(client.activities.count == 1, "the dishwasher alone does not start it again")

        let both = LiveActivityFixtures.reader(LiveActivityFixtures.dishwasher() + LiveActivityFixtures.fan())
        await director.reconcile(entity: both)
        #expect(client.activities.count == 2, "a new job brings it back")

        // When nothing runs any more the memory is cleared, so the dishwasher can start it next time.
        await director.reconcile(entity: LiveActivityFixtures.reader([]))
        await director.reconcile(entity: running)
        #expect(client.activities.count == 3)
    }

    @Test func endAllEndsTheHomeActivityAndForgetsTheSession() async {
        let client = FakeLiveActivityClient()
        let director = director(client)
        await director.reconcile(entity: LiveActivityFixtures.reader(LiveActivityFixtures.dishwasher()))
        client.startFromPush(attributes: HomeActivityAttributes(tag: "other", title: "Other", kind: "generic"),
                             state: HomeActivityState(jobs: []))
        await director.endAll()
        guard case .end(id: "act-1", nil, .immediate)? = client.calls.last else { Issue.record("expected an immediate end"); return }
        #expect(client.activities[1].lifecycle == .active, "another activity's tag is left alone")
    }

    @Test func adoptsAPushStartedActivityOnlyForTheHomeTag() async {
        let client = FakeLiveActivityClient()
        let director = director(client)
        let state = HomeActivityState(jobs: [])
        director.adopt(LiveActivityRecord(id: "x", attributes: HomeActivityAttributes(tag: "other"), state: state))
        director.adopt(LiveActivityRecord(id: "y", attributes: HomeActivityAttributes(), state: state))
        director.adopt(LiveActivityRecord(id: "y", attributes: HomeActivityAttributes(), state: state))
        #expect(director.watchedEntityIDs.contains("sensor.dishwasher_operation_state"))
    }
}
