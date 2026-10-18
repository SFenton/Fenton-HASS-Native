import SwiftUI

/// The timing constants of S+H's motion, in one place (`.agents/design/motion.md` §7). The sign-in lane (launch intro, arrival into
/// Home, the reconnecting chip) uses these and adds the sequences of its two moments under ``Intro`` and ``Arrival``; nothing here
/// animates a tab, a push or a sheet.
///
/// Three curves cover the motion: ``quick`` for small state changes, ``standard`` for things that move or appear, and ``emphasized``
/// for the sign-in mark alone. Reduce Motion replaces every movement with ``crossFade``.
public enum MotionTokens {
    /// Numbers, small fades, button state, the launch ground going: 0.2 s ease-out.
    public static let quickDuration: TimeInterval = 0.2
    public static var quick: Animation { .easeOut(duration: quickDuration) }

    /// Tile and chip colour changes: 0.25 s ease-in-out.
    public static let stateDuration: TimeInterval = 0.25
    public static var state: Animation { .easeInOut(duration: stateDuration) }

    /// Layout a person caused, and anything that moves or appears: a smooth spring, no bounce, 0.3 s.
    public static let standardDuration: TimeInterval = 0.3
    public static var standard: Animation { .smooth(duration: standardDuration) }

    /// The sign-in mark settling after its overshoot, and nothing else: a spring that gives a little.
    public static var emphasized: Animation { .spring(response: 0.5, dampingFraction: 0.8) }

    /// The delay between one rising element and the next in the arrival, first screenful only.
    public static let arrivalStagger: TimeInterval = 0.06

    /// What Reduce Motion allows instead of movement: a cross-fade of about a third of a second.
    public static let crossFadeDuration: TimeInterval = 0.35
    public static var crossFade: Animation { .easeInOut(duration: crossFadeDuration) }

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
