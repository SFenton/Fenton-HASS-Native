import Foundation
import HassTelemetry
@testable import HassUI
import Testing

/// ``MotionPolicy``: which moments have played this session, Reduce Motion, and the one-line measurements
/// (design: `.agents/design/motion.md` §3, §8; pattern: `.agents/patterns/motion.md`).
@MainActor
struct MotionPolicyTests {
    @Test func aMomentPlaysOnceThenIsRemembered() {
        let policy = MotionPolicy(reduceMotion: { false })
        #expect(Moment.allCases == [.intro, .signInArrival])
        for moment in Moment.allCases { #expect(!policy.hasPlayed(moment)) }
        policy.markPlayed(.signInArrival)
        #expect(policy.hasPlayed(.signInArrival))
        #expect(!policy.hasPlayed(.intro))
        policy.markPlayed(.signInArrival) // Idempotent.
        #expect(policy.played == [.signInArrival])
    }

    @Test func resetForgetsEveryMomentSoASecondSignInPlaysAgain() {
        let policy = MotionPolicy(reduceMotion: { false })
        policy.markPlayed(.intro)
        policy.markPlayed(.signInArrival)
        policy.reset()
        #expect(policy.played.isEmpty)
        for moment in Moment.allCases { #expect(!policy.hasPlayed(moment)) }
    }

    @Test func reduceMotionFollowsTheSourceWhenRefreshed() {
        var reduced = false
        let policy = MotionPolicy(reduceMotion: { reduced })
        #expect(!policy.reduceMotion)
        reduced = true
        #expect(!policy.reduceMotion) // Updated by the system notification, or by a refresh.
        policy.refreshReduceMotion()
        #expect(policy.reduceMotion)
        policy.refreshReduceMotion() // No change.
        reduced = false
        policy.refreshReduceMotion()
        #expect(!policy.reduceMotion)
    }

    @Test func theSystemSettingReadsWithoutCrashing() {
        _ = MotionPolicy.systemReduceMotion()
        _ = MotionPolicy().reduceMotion
    }

    @Test func measureStartsATimedTransition() {
        let wasEnabled = Telemetry.isEnabled
        defer { Telemetry.isEnabled = wasEnabled }
        Telemetry.isEnabled = true
        let policy = MotionPolicy(reduceMotion: { false })
        let page = "policy-\(UUID().uuidString)"
        let measurement = policy.measure(.push(page))
        #expect(measurement.surface == .push && measurement.page == page)
        measurement.settled()
        #expect(Telemetry.log.records.contains { $0.page == page && $0.detail == "settled" })
    }

    @Test func measureCutSettlesOnTheNextFrame() async throws {
        let wasEnabled = Telemetry.isEnabled
        defer { Telemetry.isEnabled = wasEnabled }
        Telemetry.isEnabled = true
        let page = "cut-\(UUID().uuidString)"
        MotionPolicy(reduceMotion: { false }).measureCut(.tabSwitch(page))
        // Bounded by the clock, not a count: a busy main actor delays the display tick.
        let deadline = ContinuousClock.now + .seconds(30)
        while ContinuousClock.now < deadline, !Telemetry.log.records.contains(where: { $0.page == page && $0.detail == "settled" }) {
            Telemetry.isEnabled = true
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(Telemetry.log.records.contains { $0.page == page && $0.detail == "settled" && $0.kind == "TabSwitch" })
    }

    @Test func transitionsNameTheirSurfaceAndPage() {
        let all: [NavigationTransition] = [.tabSwitch("a"), .push("b"), .pop("c"), .sheetPresent("d"), .sheetDismiss("e"), .zoomOpen("f"), .zoomClose("g")]
        #expect(all.map(\.page) == ["a", "b", "c", "d", "e", "f", "g"])
        #expect(all.map(\.surface) == NavigationMeasurement.Surface.allCases)
    }
}
