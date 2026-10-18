import SwiftUI

/// The only animation values in the app (design: `.agents/design/motion.md` §7; pattern: `.agents/patterns/motion.md`).
///
/// Call sites never write a duration: they pick a token and pass it to ``SwiftUICore/View/motionSafeAnimation(_:reduced:value:)``
/// or `withAnimation`. Navigation (push, sheet, zoom, tab) uses the system's own motion and has no token.
/// ``ContentGateModel`` keeps its own profile constants (`.agents/patterns/content-gate.md`).
public enum MotionTokens {
    /// Numbers, small fades and button state: `easeOut`, 0.2 s.
    public static let quick: Animation = .easeOut(duration: 0.2)
    /// Every background, fill, tint and rim colour that changes with state: `easeInOut`, 0.6 s, the status chip's timing the
    /// owner approved. Nothing moves in a colour fade, so its length never delays a tap. Use ``stateReduced`` under Reduce
    /// Motion (``SwiftUICore/View/stateColorTransition(_:value:)`` does).
    public static let state: Animation = .easeInOut(duration: 0.6)
    /// ``state`` under Reduce Motion: still a cross-fade (a colour change is not motion), shorter: 0.2 s.
    public static let stateReduced: Animation = .easeInOut(duration: 0.2)
    /// Layout a person caused (rows in or out, an expanding section, a pane): a smooth spring of 0.3 s with no bounce.
    public static let standard: Animation = .smooth(duration: 0.3)
    /// The house-and-heart mark in the intro, and nothing else.
    public static let emphasized: Animation = .spring(response: 0.5, dampingFraction: 0.8)

    /// Seconds between one arrival item and the next (the sign-in arrival's stagger).
    public static let arrivalStagger: Double = 0.06
    /// Items past this index appear at once: the stagger covers the first screenful only.
    public static let arrivalStaggerCap = 8
    /// How far an arrival item rises while it fades in, in points.
    public static let arrivalRise: CGFloat = 8
    /// What an arrival item uses to fade and rise (no bounce), before its stagger delay.
    public static let arrival: Animation = .smooth(duration: 0.3)
    /// A moment under Reduce Motion: a cross-fade of about 0.35 s, with no rise, scale, spring or stagger.
    public static let reducedMoment: Animation = .easeInOut(duration: 0.35)

    /// The delay before arrival item `index` starts, or nil when the item is past the cap and shows at once.
    /// - Parameter index: The item's position in the arrival, from 0.
    public static func arrivalDelay(index: Int) -> Double? {
        guard index >= 0, index < arrivalStaggerCap else { return nil }
        return Double(index) * arrivalStagger
    }
}
