import HassCore
import HassDesign
import SwiftUI

/// The quiet "Reconnecting…" chip: an orange dot that breathes, and the word (owner, 2026-10-17). It says the values on screen
/// may be stale; it never clears them. With Reduce Motion the dot holds still.
struct ReconnectingChip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.arcSpinnersPaused) private var paused

    /// The dot's orange (the warning ink on dark).
    private static let dot = Color(rgb: HassTokens.Palette.orange)

    /// The dot's opacity at `date`: a slow sine between 0.45 and 1, or fully lit with Reduce Motion.
    nonisolated static func dotOpacity(at date: Date, reduceMotion: Bool) -> Double {
        if reduceMotion { return 1 }
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
        return 0.725 + 0.275 * sin(phase * 2 * .pi)
    }

    var body: some View {
        HStack(spacing: HassTokens.Spacing.s) {
            TimelineView(.animation(paused: paused || reduceMotion)) { context in
                Circle()
                    .fill(Self.dot)
                    .opacity(Self.dotOpacity(at: context.date, reduceMotion: reduceMotion))
            }
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
            Text("Reconnecting…")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, HassTokens.Spacing.m)
        .padding(.vertical, HassTokens.Spacing.s)
        .background(HassTokens.Surface.moduleDense, in: Capsule())
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reconnecting to Home Assistant")
        .accessibilityIdentifier("reconnecting.chip")
    }
}
