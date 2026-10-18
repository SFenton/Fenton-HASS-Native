@testable import HassDesign
import SwiftUI
import Testing

/// ``MotionTokens`` (design: `.agents/design/motion.md` §7).
struct MotionTokensTests {
    @Test func tokensHaveTheirSpecifiedValues() {
        #expect(MotionTokens.quick == .easeOut(duration: 0.2))
        #expect(MotionTokens.state == .easeInOut(duration: 0.6))
        #expect(MotionTokens.stateReduced == .easeInOut(duration: 0.2))
        #expect(MotionTokens.standard == .smooth(duration: 0.3))
        #expect(MotionTokens.emphasized == .spring(response: 0.5, dampingFraction: 0.8))
        #expect(MotionTokens.reducedMoment == .easeInOut(duration: 0.35))
        #expect(MotionTokens.arrivalStagger == 0.06)
        #expect(MotionTokens.arrivalStaggerCap == 8)
        #expect(MotionTokens.arrivalRise == 8)
    }

    @Test func reduceMotionColourFadeIsShorterButStillAFade() {
        #expect(MotionTokens.stateReduced != MotionTokens.state)
        #expect(MotionTokens.stateReduced == .easeInOut(duration: 0.2))
    }

    @Test func arrivalDelayStaggersTheFirstScreenfulOnly() {
        #expect(MotionTokens.arrivalDelay(index: 0) == 0)
        #expect(MotionTokens.arrivalDelay(index: 1) == 0.06)
        #expect(MotionTokens.arrivalDelay(index: 7) == 7 * 0.06)
        #expect(MotionTokens.arrivalDelay(index: 8) == nil)
        #expect(MotionTokens.arrivalDelay(index: -1) == nil)
    }

    @Test func theSignInLanesNamesAgreeWithTheTokens() {
        #expect(MotionTokens.quickDuration == 0.2 && MotionTokens.standardDuration == 0.3 && MotionTokens.stateDuration == 0.6)
        #expect(MotionTokens.crossFade == MotionTokens.reducedMoment && MotionTokens.crossFadeDuration == 0.35)
        #expect(MotionTokens.press == .easeOut(duration: 0.12))
        #expect(MotionTokens.Arrival.staggerLimit <= MotionTokens.arrivalStaggerCap)
        #expect(MotionTokens.Arrival.slideDistance == 30 && MotionTokens.Arrival.riseDistance == 16)
        #expect(MotionTokens.Intro.formDelay > MotionTokens.Intro.titleDelay && MotionTokens.Intro.titleDelay > MotionTokens.Intro.markDelay)
        #expect(MotionTokens.Intro.markPeak > 1 && MotionTokens.Intro.markStart < 1)
        let curves: [Animation] = [MotionTokens.Intro.glow, MotionTokens.Intro.markRise, MotionTokens.Intro.title, MotionTokens.Intro.form,
                                   MotionTokens.Arrival.lift, MotionTokens.Arrival.backdrop]
        #expect(curves.count == 6)
    }
}
