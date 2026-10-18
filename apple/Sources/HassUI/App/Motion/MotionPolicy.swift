import Observation
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// What the app's motion remembers for a session: which ``Moment``s have played (`.agents/patterns/motion.md`). The session owns
/// one; signing out resets it, so the next sign-in screen introduces itself again and the next sign-in arrives again.
///
/// This is the sign-in lane's minimal version, shaped to the motion spec (`hasPlayed`, `markPlayed`, `reset`, `reduceMotion`);
/// the motion system lane's `MotionPolicy` carries the rest (measurement, zoom helpers) and is to replace this file.
@MainActor
@Observable
public final class MotionPolicy {
    private var played: Set<Moment> = []

    /// Creates a policy with nothing played.
    public init() {}

    /// Whether `moment` has played this session.
    public func hasPlayed(_ moment: Moment) -> Bool { played.contains(moment) }

    /// Records that `moment` has played (or is playing).
    public func markPlayed(_ moment: Moment) { played.insert(moment) }

    /// Forgets everything that has played (sign-out).
    public func reset() { played.removeAll() }

    /// Whether the system's Reduce Motion is on, for code outside a view.
    public var reduceMotion: Bool {
        #if os(iOS)
        UIAccessibility.isReduceMotionEnabled
        #else
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #endif
    }
}
