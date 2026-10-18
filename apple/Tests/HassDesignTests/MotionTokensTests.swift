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
}
