import SwiftUI

/// Implicit animation that honours Reduce Motion (HIG, Accessibility: Motion; `.agents/testing/apple/accessibility.md`).
///
/// With Reduce Motion off the view animates with `animation`. With it on, the view uses `reduced` (nil by
/// default: the change applies at once). Pass a short `.easeInOut` as `reduced` when the change is an opacity
/// cross-fade, which Reduce Motion allows; never let a slide, scale, spring or layout move through.
private struct MotionSafeAnimation<Value: Equatable>: ViewModifier {
    var animation: Animation?
    var reduced: Animation?
    var value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? reduced : animation, value: value)
    }
}

public extension View {
    /// Animates changes of `value` with `animation`, or with `reduced` (default none) when Reduce Motion is on.
    /// Use this instead of `.animation(_:value:)` for anything that moves, scales or resizes.
    func motionSafeAnimation(_ animation: Animation?, reduced: Animation? = nil, value: some Equatable) -> some View {
        modifier(MotionSafeAnimation(animation: animation, reduced: reduced, value: value))
    }
}
