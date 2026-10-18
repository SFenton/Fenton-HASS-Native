import HassDesign
import SwiftUI

/// What an arrival item does, decided from three facts (pure, so it is unit-tested apart from the drawing).
struct ArrivalMotionPlan: Equatable {
    /// How the item shows.
    enum Style: Equatable {
        /// It is there from the first frame: the moment has played, or the item is past the stagger cap.
        case instant
        /// It fades in and rises, after `delay` seconds.
        case riseAndFade(delay: Double)
        /// Reduce Motion: a cross-fade only, no rise, no stagger.
        case crossFade
    }

    /// - Parameters:
    ///   - hasPlayed: The moment has played this session (or there is no session policy to play it).
    ///   - reduceMotion: Reduce Motion is on.
    ///   - index: The item's position in the moment, from 0.
    static func resolve(hasPlayed: Bool, reduceMotion: Bool, index: Int) -> Style {
        guard !hasPlayed else { return .instant }
        if reduceMotion { return .crossFade }
        guard let delay = MotionTokens.arrivalDelay(index: index) else { return .instant }
        return .riseAndFade(delay: delay)
    }

    /// The animation for a style, or nil for an instant item.
    static func animation(for style: Style) -> Animation? {
        switch style {
        case .instant: nil
        case let .riseAndFade(delay): MotionTokens.arrival.delay(delay)
        case .crossFade: MotionTokens.reducedMoment
        }
    }
}

public extension View {
    /// Plays this view's part of a one-time moment: it fades in and rises 8 pt, staggered 60 ms per `index` (design:
    /// `.agents/design/motion.md` §3, §7).
    ///
    /// It plays only while the session's ``MotionPolicy`` says `moment` has not played; afterwards, and for any item past
    /// the stagger cap, the view is simply there. Under Reduce Motion it cross-fades with no rise and no stagger. The moment's
    /// owner calls ``MotionPolicy/markPlayed(_:)`` once its last item has arrived.
    ///
    /// The signature matches the sign-in lane's (`claude/signin-and-launch-motion`), so the call sites it wrote compile with
    /// either implementation: its `HomeArrival`-driven version replaces this one for Home's arrival.
    /// - Parameters:
    ///   - moment: The moment this view belongs to.
    ///   - kind: `.rise` fades in and rises; `.slideIn` (the status chips) slides in from the right.
    ///   - index: The view's position in the moment's sequence (the first screenful only; later indexes appear at once).
    func arrivalMotion(_ moment: Moment = .signInArrival, kind: ArrivalKind = .rise, index: Int = 0) -> some View {
        modifier(ArrivalMotion(moment: moment, kind: kind, index: index))
    }
}

/// Implementation of ``SwiftUICore/View/arrivalMotion(_:kind:index:)``.
private struct ArrivalMotion: ViewModifier {
    var moment: Moment
    var kind: ArrivalKind
    var index: Int
    @Environment(MotionPolicy.self) private var policy: MotionPolicy?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Flips once, on first appearance; the view is hidden until then when the moment is playing.
    @State private var arrived = false

    func body(content: Content) -> some View {
        // Without a session (the gallery, hosted views) there is nothing to play.
        let style = ArrivalMotionPlan.resolve(hasPlayed: policy?.hasPlayed(moment) ?? true, reduceMotion: reduceMotion, index: index)
        let pending = style != .instant && !arrived
        content
            .opacity(pending ? 0 : 1)
            .offset(pending && style != .crossFade ? offset : .zero)
            // Scoped to `arrived`: nothing else in the view rides this animation, and a tap goes through at any point.
            .animation(ArrivalMotionPlan.animation(for: style), value: arrived)
            .onAppear {
                if style != .instant { arrived = true }
            }
    }

    private var offset: CGSize {
        switch kind {
        case .rise: CGSize(width: 0, height: MotionTokens.arrivalRise)
        case .slideIn: CGSize(width: MotionTokens.Arrival.slideDistance, height: 0)
        }
    }
}
