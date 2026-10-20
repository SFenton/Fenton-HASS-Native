import HassDesign
import Observation
import SwiftUI

private struct ArrivalEffect: ViewModifier {
    var moment: Moment
    var kind: ArrivalKind
    var index: Int
    @Environment(\.homeArrival) private var arrival
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // Held back only while this moment's arrival is under way; at all other times the element is simply there.
        let shown = arrival.map { $0.moment != moment || $0.isRevealed } ?? true
        // Reduce Motion keeps the fade and drops the movement (HIG Motion).
        let held = reduceMotion || shown ? CGSize.zero : offset
        content
            .opacity(shown ? 1 : 0)
            .offset(held)
            .animation(animation, value: shown)
    }

    private var offset: CGSize {
        switch kind {
        case .rise: CGSize(width: 0, height: MotionTokens.Arrival.riseDistance)
        case .slideIn: CGSize(width: MotionTokens.Arrival.slideDistance, height: 0)
        }
    }

    private var animation: Animation {
        if reduceMotion { return MotionTokens.crossFade }
        switch kind {
        case .rise: return MotionTokens.standard.delay(HomeArrival.riseDelay(index: index))
        case .slideIn: return MotionTokens.standard.delay(MotionTokens.Arrival.slideDelay)
        }
    }
}

extension View {
    /// Plays `moment`'s entrance for this view while it is under way (`HomeArrival`): fades in and rises 16 pt, `index` places
    /// into the 60 ms stagger (`.rise`), or slides in from the right (`.slideIn`). Plain content when the moment is not playing
    /// (already played this session, a relaunch, a gallery); with Reduce Motion it only fades.
    func arrivalMotion(_ moment: Moment = .signInArrival, kind: ArrivalKind = .rise, index: Int = 0) -> some View {
        modifier(ArrivalEffect(moment: moment, kind: kind, index: index))
    }
}
