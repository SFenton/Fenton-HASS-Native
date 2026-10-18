@testable import HassUI
import HassDesign
import SwiftUI
import Testing

/// ``ArrivalMotionPlan`` and the `.arrivalMotion` modifier: plays once per session, instant afterwards and past the stagger cap,
/// a cross-fade under Reduce Motion (design: `.agents/design/motion.md` §3, §7, §8).
@MainActor
struct ArrivalMotionTests {
    @Test func playsOnlyWhileTheMomentHasNotPlayed() {
        #expect(ArrivalMotionPlan.resolve(hasPlayed: true, reduceMotion: false, index: 0) == .instant)
        #expect(ArrivalMotionPlan.resolve(hasPlayed: true, reduceMotion: true, index: 3) == .instant)
        #expect(ArrivalMotionPlan.resolve(hasPlayed: false, reduceMotion: false, index: 0) == .riseAndFade(delay: 0))
    }

    @Test func staggersByIndexUpToTheCap() {
        for index in 0..<MotionTokens.arrivalStaggerCap {
            let style = ArrivalMotionPlan.resolve(hasPlayed: false, reduceMotion: false, index: index)
            #expect(style == .riseAndFade(delay: Double(index) * MotionTokens.arrivalStagger))
        }
        let last = ArrivalMotionPlan.resolve(hasPlayed: false, reduceMotion: false, index: 7)
        #expect(last == .riseAndFade(delay: 7 * 0.06))
        // Past the first screenful, or a nonsense index: there at once.
        #expect(ArrivalMotionPlan.resolve(hasPlayed: false, reduceMotion: false, index: MotionTokens.arrivalStaggerCap) == .instant)
        #expect(ArrivalMotionPlan.resolve(hasPlayed: false, reduceMotion: false, index: -1) == .instant)
    }

    @Test func reduceMotionIsACrossFadeWithNoStagger() {
        for index in [0, 4, 20] {
            #expect(ArrivalMotionPlan.resolve(hasPlayed: false, reduceMotion: true, index: index) == .crossFade)
        }
    }

    @Test func animationsFollowTheStyle() {
        #expect(ArrivalMotionPlan.animation(for: .instant) == nil)
        #expect(ArrivalMotionPlan.animation(for: .crossFade) == MotionTokens.reducedMoment)
        #expect(ArrivalMotionPlan.animation(for: .riseAndFade(delay: 0.12)) == MotionTokens.arrival.delay(0.12))
        #expect(MotionTokens.arrivalDelay(index: 3) == 3 * MotionTokens.arrivalStagger)
        #expect(MotionTokens.arrivalDelay(index: 8) == nil)
    }

    @Test func theModifierRendersWithAndWithoutAPolicy() {
        let view = Color.red.frame(width: 40, height: 40)
        // No session: nothing to play, the view is there.
        #expect(ImageRenderer(content: view.arrivalMotion(.signInArrival, index: 2)).cgImage != nil)
        #expect(ImageRenderer(content: view.arrivalMotion(kind: .slideIn)).cgImage != nil)
        let policy = MotionPolicy(reduceMotion: { false })
        #expect(ImageRenderer(content: view.arrivalMotion(.signInArrival).environment(policy)).cgImage != nil)
        #expect(ImageRenderer(content: view.arrivalMotion(kind: .slideIn).environment(policy)).cgImage != nil)
        policy.markPlayed(.signInArrival)
        #expect(ImageRenderer(content: view.arrivalMotion(.signInArrival).environment(policy)).cgImage != nil)
    }
}
