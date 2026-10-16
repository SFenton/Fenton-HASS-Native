import HassCore
import HassDesign
import SwiftUI

/// The skeleton of an hour while the forecast loads: same height, so nothing jumps when data arrives.
struct WeatherCardHourPlaceholder: View {
    var body: some View {
        VStack(spacing: HassTokens.Spacing.s) {
            Capsule().frame(width: 28, height: 8)
            Circle().frame(width: 22, height: 22)
            Capsule().frame(width: 24, height: 8)
        }
        .foregroundStyle(HassTokens.Ink.onDark.opacity(0.18))
        .frame(maxWidth: .infinity, minHeight: 72)
        .padding(.vertical, HassTokens.Spacing.xs)
        .accessibilityHidden(true)
    }
}
