import Foundation
@testable import FentonActivityModel
import Testing

struct ActivityJobTests {
    private let now = ActivityFixtures.now

    @Test func timerRangeNeedsBothEndsAndAFirmEnd() throws {
        let job = ActivityFixtures.dishwasher()
        let range = try #require(job.timerRange)
        #expect(range.upperBound.timeIntervalSince(range.lowerBound) == 11_160)
        #expect(ActivityFixtures.dryer().timerRange == nil)
        #expect(ActivityJob(id: "x", kind: "x", title: "X", status: "", startTs: 10, endTs: nil).timerRange == nil)
        #expect(ActivityJob(id: "x", kind: "x", title: "X", status: "", startTs: 10, endTs: 10).timerRange == nil)
        #expect(ActivityJob(id: "x", kind: "x", title: "X", status: "", startTs: nil, endTs: 10).startDate == nil)
    }

    @Test func trailingByPhase() {
        let countdown = ActivityFixtures.dishwasher()
        if case .countdown = countdown.trailing {} else { Issue.record("expected a countdown") }
        #expect(ActivityFixtures.dishwasher(phase: .done).trailing == .done)
        #expect(ActivityFixtures.dishwasher(phase: .attention).trailing == .attention)
        #expect(ActivityFixtures.dishwasher(phase: .paused).trailing == .paused)
        #expect(ActivityFixtures.dryer().trailing == .approximately(now.addingTimeInterval(1_200)))
        var waiting = ActivityFixtures.dishwasher(phase: .waiting)
        waiting.endTs = now.timeIntervalSince1970 + 3_600
        #expect(waiting.trailing == .startsAt(now.addingTimeInterval(3_600)))
        waiting.endTs = nil
        #expect(waiting.trailing == .none)
        let percent = ActivityJob(id: "v", kind: "v", title: "V", status: "", progress: 0.4)
        #expect(percent.trailing == .percent(40))
        #expect(ActivityJob(id: "v", kind: "v", title: "V", status: "", progress: 7).trailing == .percent(100))
        #expect(ActivityJob(id: "v", kind: "v", title: "V", status: "").trailing == .none)
    }

    @Test func barFollowsThePhase() {
        if case .timer = ActivityFixtures.dishwasher().bar {} else { Issue.record("expected a timer bar") }
        #expect(ActivityFixtures.dishwasher(phase: .done).bar == .full)
        #expect(ActivityFixtures.dishwasher(phase: .attention).bar == .hidden)
        #expect(ActivityFixtures.dishwasher(phase: .waiting).bar == .hidden)
        #expect(ActivityFixtures.dishwasher(phase: .paused).bar == .hidden)
        #expect(ActivityJob(id: "v", kind: "v", title: "V", status: "", progress: -1).bar == .fraction(0))
        #expect(ActivityJob(id: "v", kind: "v", title: "V", status: "", progress: 0.25).bar == .fraction(0.25))
        #expect(ActivityJob(id: "v", kind: "v", title: "V", status: "").bar == .hidden)
    }

    @Test func spokenSummaryReadsDegreesAndTimeLeft() {
        let spoken = ActivityFixtures.dishwasher().spokenSummary(now: now)
        #expect(spoken == "Dishwasher, Eco 50 degrees, Drying, 2 hours 56 minutes left")
        #expect(ActivityFixtures.fan().spokenSummary(now: now) == "Master Bath Fan, Off in, 30 minutes left")
        #expect(ActivityFixtures.dishwasher(phase: .done).spokenSummary(now: now).hasSuffix(", done"))
        #expect(ActivityFixtures.dishwasher(phase: .attention).spokenSummary(now: now).hasSuffix("needs attention"))
        #expect(ActivityFixtures.dishwasher(phase: .paused).spokenSummary(now: now).hasSuffix("paused"))
        #expect(ActivityFixtures.dryer().spokenSummary(now: now).contains("about"))
        #expect(ActivityJob(id: "v", kind: "v", title: "V", status: "", progress: 0.4).spokenSummary() == "V, 40 percent")
        #expect(ActivityJob(id: "v", kind: "v", title: "V", status: "").spokenSummary() == "V")
        var waiting = ActivityFixtures.dishwasher(phase: .waiting)
        waiting.endTs = now.timeIntervalSince1970 + 3_600
        #expect(waiting.spokenSummary(now: now).contains("starts at"))
    }

    @Test func remainingSpeechRoundsUpAndPluralises() {
        func spoken(_ seconds: TimeInterval) -> String {
            ActivityJob.spokenRemaining(until: now.addingTimeInterval(seconds), now: now)
        }
        #expect(spoken(-5) == "done" && spoken(0) == "done")
        #expect(spoken(20) == "less than a minute left")
        #expect(spoken(60) == "1 minute left")
        #expect(spoken(61) == "2 minutes left")
        #expect(spoken(3_600) == "1 hour left")
        #expect(spoken(3_660) == "1 hour 1 minute left")
        #expect(spoken(7_500) == "2 hours 5 minutes left")
    }
}

struct ActivityWireTests {
    /// The sample content-state of the spec (§3), the way the relay sends it.
    static let wire = """
    {"v":1,"focus":"dishwasher","url":"/sfenton-react-dash/home?path=kitchen","jobs":[
     {"id":"dishwasher","kind":"dishwasher","title":"Dishwasher","status":"Eco 50° · Drying","phase":"running",
      "start_ts":1792270800,"end_ts":1792281360,"estimated":false,"progress":0.62,"symbol":"dishwasher","tint":"cleaning",
      "controls":[{"id":"stop","title":"Stop","role":"destructive"}]},
     {"id":"fan.master","kind":"bathroom_fan","title":"Master Bath Fan","status":"Off in","phase":"running",
      "start_ts":1792279000,"end_ts":1792280800,"controls":[{"id":"cancel_timer","title":"Cancel Timer"}]}]}
    """

    @Test func decodesTheRelayJSONWithUnixSecondsNot2001() throws {
        let state = try HomeActivityState.decode(Data(Self.wire.utf8))
        let job = try #require(state.jobs.first)
        // The default decoder reads a Date as seconds since 2001; the model keeps doubles so 1.79e9 stays in 2026.
        #expect(Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: try #require(job.endDate)).year == 2026)
        #expect(job.startTs == 1_792_270_800 && job.endTs == 1_792_281_360)
        #expect(job.controls == [ActivityControl(id: "stop", title: "Stop", role: .destructive)])
        let fan = state.jobs[1]
        #expect(fan.estimated == false && fan.progress == nil && fan.symbol == "circle" && fan.tint == "neutral")
        #expect(fan.controls.first?.role == .normal)
        #expect(state.focus == "dishwasher" && state.version == 1)
    }

    @Test func unknownPhasesAndRolesDegradeInsteadOfFailing() throws {
        let json = #"{"jobs":[{"id":"a","title":"A","phase":"sprinting","controls":[{"id":"c","title":"C","role":"shiny"}]}]}"#
        let state = try HomeActivityState.decode(Data(json.utf8))
        #expect(state.jobs[0].phase == .running)
        #expect(state.jobs[0].controls[0].role == .normal)
        #expect(state.version == HomeActivityState.currentVersion)
        #expect(try HomeActivityState.decode(Data("{}".utf8)).jobs.isEmpty)
    }

    @Test func roundTripsAndOmitsEmptyOptionals() throws {
        let state = try HomeActivityState.decode(Data(Self.wire.utf8))
        let again = try HomeActivityState.decode(try state.encoded())
        #expect(again == state)
        let minimal = ActivityJob(id: "a", kind: "generic", title: "A", status: "")
        let text = String(decoding: try JSONEncoder().encode(minimal), as: UTF8.self)
        #expect(!text.contains("estimated") && !text.contains("controls") && !text.contains("start_ts"))
    }

    @Test func attributesDecodeWithDefaults() throws {
        let decoded = try JSONDecoder().decode(HomeActivityAttributes.self, from: Data(#"{"title":"Vacuum","tag":"vac"}"#.utf8))
        #expect(decoded.tag == "vac" && decoded.title == "Vacuum" && decoded.kind == "home")
        let empty = try JSONDecoder().decode(HomeActivityAttributes.self, from: Data("{}".utf8))
        #expect(empty == HomeActivityAttributes())
        #expect(HomeActivityAttributes.wireName == String(describing: HomeActivityAttributes.self))
    }
}

struct LiveActivityIntentRuntimeTests {
    private struct Recorder: LiveActivityIntentRuntime.Handler {
        let result: Bool
        func handle(_ action: LiveActivityAction) async -> Bool { result }
    }

    @Test func actionsKnowTheirActivity() {
        #expect(LiveActivityAction.focus(tag: "t", job: "j").tag == "t")
        #expect(LiveActivityAction.control(tag: "u", job: "j", control: "c").tag == "u")
    }

    @Test func pressesGoToTheInstalledHandlerOnly() async {
        LiveActivityIntentRuntime.install(nil)
        #expect(await LiveActivityIntentRuntime.perform(.focus(tag: "t", job: "j")) == false)
        LiveActivityIntentRuntime.install(Recorder(result: true))
        #expect(await LiveActivityIntentRuntime.perform(.focus(tag: "t", job: "j")) == true)
        LiveActivityIntentRuntime.install(Recorder(result: false))
        #expect(await LiveActivityIntentRuntime.perform(.control(tag: "t", job: "j", control: "c")) == false)
        LiveActivityIntentRuntime.install(nil)
    }
}
