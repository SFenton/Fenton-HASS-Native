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

    // MARK: The sign-in lane's names

    // The sign-in lane (`claude/signin-and-launch-motion`) wrote its tokens first; its call sites use these names, so they stay.
    // `state` is the one value that differs from its draft: the owner set it to the status chip's 0.6 s on 2026-10-18.

    /// ``quick``'s duration, in seconds.
    public static let quickDuration: TimeInterval = 0.2
    /// ``state``'s duration, in seconds.
    public static let stateDuration: TimeInterval = 0.6
    /// ``standard``'s duration, in seconds.
    public static let standardDuration: TimeInterval = 0.3
    /// What Reduce Motion allows instead of movement in a moment: a cross-fade of about a third of a second (``reducedMoment``).
    public static let crossFadeDuration: TimeInterval = 0.35
    public static var crossFade: Animation { reducedMoment }
    /// A button shrinking under a finger.
    public static var press: Animation { .easeOut(duration: 0.12) }

    /// The launch sequence on the sign-in screen, about 1.2 s in all (a moment: the one place motion may run past 0.4 s).
    public enum Intro {
        /// The glow fading up from the plain launch ground.
        public static var glow: Animation { .easeOut(duration: 0.5) }
        /// Seconds before the mark starts, then the mark's rise to its peak (0.86 to 1.03).
        public static let markDelay: TimeInterval = 0.15
        public static let markRiseDuration: TimeInterval = 0.28
        public static var markRise: Animation { .easeOut(duration: markRiseDuration) }
        public static let markStart: CGFloat = 0.86
        public static let markPeak: CGFloat = 1.03
        /// The title and subtitle fading up by 10 pt, starting 0.46 s in (as the mark's rise ends).
        public static let titleDelay: TimeInterval = 0.46
        public static var title: Animation { .easeOut(duration: 0.4) }
        public static let titleRise: CGFloat = 10
        /// The form rising 28 pt, starting 0.71 s in, so the whole sequence ends at 1.16 s.
        public static let formDelay: TimeInterval = 0.71
        public static var form: Animation { .easeOut(duration: 0.45) }
        public static let formRise: CGFloat = 28
    }

    /// Home arriving after a sign-in, about 0.9 s in all.
    public enum Arrival {
        /// The sign-in layer lifting away.
        public static let liftDistance: CGFloat = -18
        public static let liftScale: CGFloat = 0.97
        public static var lift: Animation { .easeOut(duration: 0.4) }
        /// The house backdrop settling from 1.06 to 1.
        public static let backdropScale: CGFloat = 1.06
        public static var backdrop: Animation { .easeOut(duration: 0.6) }
        /// Cards rising 16 pt and chips sliding 30 pt, staggered ``MotionTokens/arrivalStagger`` apart from 0.2 s.
        public static let riseDistance: CGFloat = 16
        public static let slideDistance: CGFloat = 30
        public static let slideDelay: TimeInterval = 0.12
        public static let firstDelay: TimeInterval = 0.20
        /// Elements past this index come in with the last staggered one: the stagger is for the first screenful.
        public static let staggerLimit = 5
    }
}
