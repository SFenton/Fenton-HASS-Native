import HassCore
import HassDesign
import SwiftUI

/// The skeleton of a sheet hour while the forecast loads.
struct WeatherModalHourPlaceholder: View {
    var body: some View {
        VStack(spacing: HassTokens.Spacing.m) {
            Capsule().frame(width: 36, height: 10)
            Circle().frame(width: 30, height: 30)
            Capsule().frame(width: 32, height: 10)
        }
        .foregroundStyle(HassTokens.Ink.onDark.opacity(0.16))
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .top)
        .padding(.vertical, HassTokens.Spacing.xs)
    }
}
