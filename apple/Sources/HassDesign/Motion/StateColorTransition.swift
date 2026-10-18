import Foundation
import os
import SwiftUI

/// Background, fill, tint and rim colours that change with state always cross-fade with ``MotionTokens/state`` (0.6 s, or 0.2 s
/// under Reduce Motion), whether the house or the person caused the change (design: `.agents/design/motion.md` §6; every
/// component: `.agents/design/motion-components.md`).
///
/// Two scoped forms, so only colour animates and layout never rides along:
/// - ``SwiftUICore/View/stateColorTransition(_:value:)``: a value-bound animation on a colour layer (a fill, a ground, a
///   rim). Apply it to the layer, never to a whole component.
/// - ``SwiftUICore/View/stateColor(_:_:)`` and ``SwiftUICore/View/stateForeground(_:_:)``: an animation scoped to the modifiers
///   inside a closure (a foreground style, an opacity), for ink on content whose text or size may change in the same update.
///
/// Each records itself in ``MotionAudit`` (debug and test builds), so a unit test fails when a component stops animating.
public extension View {
    /// Cross-fades this colour layer when `value` changes (`.animation(MotionTokens.state, value:)`, through
    /// ``SwiftUICore/View/motionSafeAnimation(_:reduced:value:)``).
    /// - Parameters:
    ///   - component: The component's name, recorded by ``MotionAudit``.
    ///   - value: The input that decides the colour (a colour key, a tint, a tone, a selection).
    func stateColorTransition(_ component: String, value: some Equatable) -> some View {
        modifier(StateColorTransition(component: component, value: value))
    }

    /// Cross-fades a colour set inside `apply` when it changes, leaving everything else in this view unanimated.
    /// - Parameters:
    ///   - component: The component's name, recorded by ``MotionAudit``.
    ///   - apply: The colour modifiers, e.g. `{ $0.foregroundStyle(color) }`.
    func stateColor<Result: View>(_ component: String, _ apply: @escaping (PlaceholderContentView<Self>) -> Result) -> some View {
        StateColorScope(component: component, source: self, apply: apply)
    }

    /// Fades an opacity that follows state (a checkmark appearing, a disabled button, a pressed highlight) with
    /// ``MotionTokens/quick``, recorded in ``MotionAudit``. Apply it to the layer or glyph that fades.
    /// - Parameters:
    ///   - component: The component's name.
    ///   - value: The input that decides the opacity.
    ///   - instant: Skips the animation for this change (a press goes down at once and fades on release).
    func quickTransition(_ component: String, value: some Equatable, instant: Bool = false) -> some View {
        MotionAudit.noteStateColor(component)
        return animation(instant ? nil : MotionTokens.quick, value: value)
    }

    /// Cross-fades this view's foreground style when it changes (``stateColor(_:_:)``).
    func stateForeground(_ component: String, _ style: some ShapeStyle) -> some View {
        stateColor(component) { $0.foregroundStyle(style) }
    }
}

private struct StateColorTransition<Value: Equatable>: ViewModifier {
    var component: String
    var value: Value

    func body(content: Content) -> some View {
        MotionAudit.noteStateColor(component)
        // Reduce Motion keeps a fade (a colour change is not motion), shorter.
        return content.motionSafeAnimation(MotionTokens.state, reduced: MotionTokens.stateReduced, value: value)
    }
}

/// Wraps a view so the modifiers `apply` adds cross-fade (and nothing else does). A view, not a modifier, so it can read Reduce
/// Motion for the animation it picks.
private struct StateColorScope<Source: View, Result: View>: View {
    var component: String
    var source: Source
    var apply: (PlaceholderContentView<Source>) -> Result
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MotionAudit.noteStateColor(component)
        return source.animation(reduceMotion ? MotionTokens.stateReduced : MotionTokens.state, body: apply)
    }
}

/// A registry of the components that animate a state colour, read by tests (`StateColorTransitionTests`). It records in debug and
/// test builds only; in a release build every call is empty.
///
/// Recording is off unless a test (or `FENTON_MOTION_AUDIT=1`) turns it on. ``capture(_:)`` collects the components one render
/// draws, so a component that drops its animation fails its own test.
public enum MotionAudit {
    #if DEBUG
    private struct State {
        var enabled = ProcessInfo.processInfo.environment["FENTON_MOTION_AUDIT"] == "1"
        var names: Set<String> = []
        var captured: Set<String>?
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())
    #endif

    /// Starts recording every component for the process (``components``).
    public static func enable() {
        #if DEBUG
        state.withLock { $0.enabled = true }
        #endif
    }

    /// Notes that `component` drew a state colour animation.
    public static func noteStateColor(_ component: String) {
        #if DEBUG
        state.withLock { state in
            if state.enabled { state.names.insert(component) }
            state.captured?.insert(component)
        }
        #endif
    }

    /// The components seen since ``enable()``.
    public static var components: Set<String> {
        #if DEBUG
        state.withLock { $0.names }
        #else
        []
        #endif
    }

    /// The components that drew a state colour animation while `body` ran. Main actor only, so parallel tests that render
    /// views cannot overlap.
    @MainActor
    public static func capture(_ body: () -> Void) -> Set<String> {
        #if DEBUG
        state.withLock { $0.captured = [] }
        body()
        return state.withLock { state in
            defer { state.captured = nil }
            return state.captured ?? []
        }
        #else
        body()
        return []
        #endif
    }
}
