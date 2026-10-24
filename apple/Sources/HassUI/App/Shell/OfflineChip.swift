import HassCore
import HassDesign
import SwiftUI

/// The quiet offline chip: a still grey `icloud.slash` and the words "Offline. Showing last known values." (owner, 2026-10-17).
/// It says the values on screen may be stale and why; it never clears them. A connection that is only retrying shows the header's
/// arc instead (``ReconnectingArc``; owner, 2026-10-23).
struct OfflineChip: View {
    var body: some View {
        HStack(spacing: HassTokens.Spacing.s) {
            Image(systemName: "icloud.slash")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .accessibilityHidden(true)
            Text("Offline. Showing last known values.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, HassTokens.Spacing.m)
        .padding(.vertical, HassTokens.Spacing.s)
        .background(HassTokens.Surface.moduleDense, in: Capsule())
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Offline. Showing last known values.")
        .accessibilityIdentifier("offline.chip")
    }
}
