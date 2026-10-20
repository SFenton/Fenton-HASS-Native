import SwiftUI

public extension EnvironmentValues {
    /// Whether the values behind the tiles have not arrived yet: the first sign-in on a phone, before the disk snapshot
    /// exists and before Home Assistant has sent its first full set. Tiles keep their names and draw a soft
    /// ``PendingValueBar`` where the value goes (no full-screen spinner anywhere). False everywhere else, including a
    /// relaunch, which draws the snapshot's values at once.
    @Entry var valuesPending = false
}

/// The soft placeholder where a tile's value will go until live data lands (owner, 2026-10-17).
///
/// A rounded bar about the width of a short value that breathes between 35% and 100% of a soft white (1.4 s). It sizes itself to
/// the tile's value line (`footnote`), so the tile does not change height when the value arrives. With Reduce Motion it
/// holds still half way, because a loop of movement or light is what the setting asks to avoid. Hidden from
/// accessibility: the tile's value reads "Loading".
public struct PendingValueBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.arcSpinnersPaused) private var paused
    @ScaledMetric(relativeTo: .footnote) private var height: CGFloat = 12

    /// Seconds for the bar to breathe in and out.
    public nonisolated static let period: TimeInterval = 1.4

    /// Creates the bar.
    public init() {}

    /// The bar's own opacity at `date`: a sine between 0.35 and 1, or a fixed 0.65 with Reduce Motion
    /// (`.agents/design/motion.md` §5).
    nonisolated static func opacity(at date: Date, reduceMotion: Bool) -> Double {
        if reduceMotion { return 0.65 }
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return 0.675 + 0.325 * sin(phase * 2 * .pi)
    }

    public var body: some View {
        TimelineView(.animation(paused: paused || reduceMotion)) { context in
            Capsule().fill(.white.opacity(0.32)).opacity(Self.opacity(at: context.date, reduceMotion: reduceMotion))
        }
        .frame(width: 56, height: height, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}
