import HassDesign
import SwiftUI

/// A titled section of the sheet.
struct WeatherPanel<Content: View>: View {
    var title: String
    var identifier: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .weatherSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
