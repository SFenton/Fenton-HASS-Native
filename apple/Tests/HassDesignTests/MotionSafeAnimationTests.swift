@testable import HassDesign
import SwiftUI
import Testing

@MainActor
struct MotionSafeAnimationTests {
    /// The environment value is read-only, so the Reduce Motion branch runs in the UI journeys that launch with it
    /// on (`AccessibilitySweepJourneyTests`); this checks that the modifier composes and renders.
    @Test func rendersWithBothAnimations() {
        let view = Color.red
            .frame(width: 40, height: 40)
            .motionSafeAnimation(.snappy, value: 1)
            .motionSafeAnimation(.snappy, reduced: .easeInOut(duration: 0.1), value: "x")
        #expect(ImageRenderer(content: view).cgImage != nil)
    }
}
