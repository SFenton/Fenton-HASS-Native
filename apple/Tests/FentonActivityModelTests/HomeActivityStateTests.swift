import Foundation
@testable import FentonActivityModel
import Testing

/// Fixtures the tests share: the same shapes the relay sends.
enum ActivityFixtures {
    /// A fixed "now" (2026-10-17 15:00:00 UTC) so countdown tests are deterministic.
    static let now = Date(timeIntervalSince1970: 1_792_249_200)

    static func dishwasher(end: TimeInterval = 10_560, phase: JobPhase = .running) -> ActivityJob {
        ActivityJob(id: "dishwasher", kind: "dishwasher", title: "Dishwasher", status: "Eco 50° · Drying", phase: phase,
                    startTs: now.timeIntervalSince1970 - 600, endTs: now.timeIntervalSince1970 + end, progress: 0.62,
                    symbol: "dishwasher", tint: "cleaning",
                    controls: [ActivityControl(id: "stop", title: "Stop", role: .destructive)])
    }

    static func fan(_ room: String = "master", end: TimeInterval = 1_800) -> ActivityJob {
        ActivityJob(id: "fan.\(room)", kind: "bathroom_fan", title: "\(room.capitalized) Bath Fan", status: "Off in",
                    startTs: now.timeIntervalSince1970 - 300, endTs: now.timeIntervalSince1970 + end,
                    symbol: "fan", tint: "air", controls: [ActivityControl(id: "cancel_timer", title: "Cancel Timer")])
    }

    static func dryer() -> ActivityJob {
        ActivityJob(id: "dryer", kind: "dryer", title: "Dryer", status: "Running",
                    endTs: now.timeIntervalSince1970 + 1_200, estimated: true, symbol: "dryer", tint: "cleaning")
    }

    static func state(_ jobs: [ActivityJob], focus: String? = nil) -> HomeActivityState {
        HomeActivityState(focus: focus, url: "/sfenton-react-dash/home?path=kitchen", jobs: jobs)
    }
}

struct HomeActivityStateTests {
    @Test func focusFallsBackToTheFirstJobWhenUnlistedOrUnset() {
        let state = ActivityFixtures.state([ActivityFixtures.dishwasher(), ActivityFixtures.fan()])
        #expect(state.focusedJob?.id == "dishwasher")
        #expect(state.focusing("fan.master").focusedJob?.id == "fan.master")
        #expect(state.focusing("nope").focus == nil)
        var gone = state
        gone.focus = "removed"
        #expect(gone.focusedJob?.id == "dishwasher")
        #expect(HomeActivityState(jobs: []).focusedJob == nil)
    }

    @Test func runningCountExcludesDoneJobs() {
        let state = ActivityFixtures.state([ActivityFixtures.dishwasher(phase: .done), ActivityFixtures.fan()])
        #expect(state.runningCount == 1)
        #expect(!state.isAllDone)
        #expect(ActivityFixtures.state([ActivityFixtures.dishwasher(phase: .done)]).isAllDone)
        #expect(!HomeActivityState(jobs: []).isAllDone)
    }

    @Test func pagerWrapsAroundAndNeedsTwoJobs() throws {
        #expect(ActivityFixtures.state([ActivityFixtures.dishwasher()]).pager == nil)
        let jobs = [ActivityFixtures.dishwasher(), ActivityFixtures.fan("guest"), ActivityFixtures.fan("master")]
        let first = try #require(ActivityFixtures.state(jobs).pager)
        #expect(first.position == 1 && first.count == 3)
        #expect(first.previous == "fan.master" && first.next == "fan.guest")
        #expect(first.label == "1 of 3")
        let last = try #require(ActivityFixtures.state(jobs, focus: "fan.master").pager)
        #expect(last.position == 3 && last.next == "dishwasher" && last.previous == "fan.guest")
    }

    @Test func pagingWalksEveryJobAndComesBack() throws {
        var state = ActivityFixtures.state([ActivityFixtures.dishwasher(), ActivityFixtures.fan("guest"), ActivityFixtures.fan("master")])
        var seen: [String] = []
        for _ in 0..<3 {
            seen.append(try #require(state.focusedJob).id)
            state = state.focusing(try #require(state.pager).next)
        }
        #expect(seen == ["dishwasher", "fan.guest", "fan.master"])
        #expect(state.focusedJob?.id == "dishwasher")
    }

    @Test func lockScreenKeepsTheFocusedJobOnScreen() {
        let jobs = (1...5).map { ActivityJob(id: "j\($0)", kind: "generic", title: "Job \($0)", status: "") }
        let state = HomeActivityState(focus: "j5", jobs: jobs)
        #expect(state.lockScreenRows().map(\.id) == ["j1", "j2", "j5"])
        #expect(state.lockScreenRows(limit: 2).map(\.id) == ["j1", "j5"])
        #expect(state.overflowCount() == 2 && state.overflowCount(limit: 2) == 3)
        #expect(HomeActivityState(focus: "j1", jobs: jobs).lockScreenRows().map(\.id) == ["j1", "j2", "j3"])
        #expect(HomeActivityState(jobs: Array(jobs.prefix(2))).lockScreenRows().count == 2)
        #expect(state.lockScreenRows(limit: 0).count == 1)
    }

    @Test func stoppingHidesControlsAndRestoreBringsThemBack() throws {
        let original = ActivityFixtures.dishwasher()
        let state = ActivityFixtures.state([original, ActivityFixtures.fan()])
        let stopping = state.stopping("dishwasher")
        let job = try #require(stopping.jobs.first)
        #expect(job.phase == .stopping && job.controls.isEmpty)
        #expect(stopping.jobs.last == state.jobs.last)
        #expect(stopping.restoring(original) == state)
        #expect(state.stopping("missing") == state)
    }

    @Test func urgencyPutsAttentionThenSoonestEndThenOpenEndedThenDone() {
        let attention = ActivityJob(id: "a", kind: "x", title: "Zed", status: "", phase: .attention, endTs: 9_999)
        let soon = ActivityJob(id: "s", kind: "x", title: "Soon", status: "", endTs: 100)
        let later = ActivityJob(id: "l", kind: "x", title: "Later", status: "", endTs: 200)
        let open = ActivityJob(id: "o", kind: "x", title: "Open", status: "")
        let done = ActivityJob(id: "d", kind: "x", title: "Done", status: "", phase: .done, endTs: 1)
        let tie = ActivityJob(id: "t", kind: "x", title: "Aaa", status: "", endTs: 100)
        let ordered = HomeActivityState.urgencyOrdered([done, open, later, soon, attention, tie])
        #expect(ordered.map(\.id) == ["a", "t", "s", "l", "o", "d"])
        let sameTitle = HomeActivityState.urgencyOrdered([
            ActivityJob(id: "b", kind: "x", title: "Same", status: ""), ActivityJob(id: "a", kind: "x", title: "Same", status: ""),
        ])
        #expect(sameTitle.map(\.id) == ["a", "b"])
    }

    @Test func fittedTrimsToTheWireBudget() {
        let long = String(repeating: "x", count: 80)
        let controls = (1...4).map { ActivityControl(id: "c\($0)", title: "C\($0)") }
        let jobs = (1...9).map { ActivityJob(id: "j\($0)", kind: "generic", title: "Job \($0)", status: long, controls: controls) }
        let fitted = HomeActivityState(focus: "j9", jobs: jobs).fitted()
        #expect(fitted.jobs.count == HomeActivityState.maxJobs)
        #expect(fitted.jobs.contains { $0.id == "j9" })
        #expect(fitted.jobs.allSatisfy { $0.status.count == HomeActivityState.maxStatusLength && $0.status.hasSuffix("…") })
        #expect(fitted.jobs.allSatisfy { $0.controls.count == HomeActivityState.maxControlsPerJob })
        let small = ActivityFixtures.state([ActivityFixtures.dishwasher()])
        #expect(small.fitted() == small)
    }

    @Test func aFullStateStaysUnderTheFourKilobyteLimit() throws {
        let jobs = [ActivityFixtures.dishwasher(), ActivityFixtures.fan("guest"), ActivityFixtures.fan("master"), ActivityFixtures.dryer(),
                    ActivityJob(id: "washer", kind: "washer", title: "Washer", status: "Spinning", symbol: "washer", tint: "cleaning"),
                    ActivityJob(id: "vac", kind: "vacuum", title: "Upstairs Vacuum", status: "Kitchen · 2 of 5 rooms", progress: 0.4,
                                symbol: "fan", tint: "cleaning")]
        let state = HomeActivityState(focus: "dishwasher", url: "/sfenton-react-dash/home?path=kitchen", jobs: jobs).fitted()
        let attributes = try JSONEncoder().encode(HomeActivityAttributes())
        #expect(try state.encoded().count + attributes.count < HomeActivityState.maxPayloadBytes / 2)
    }
}
