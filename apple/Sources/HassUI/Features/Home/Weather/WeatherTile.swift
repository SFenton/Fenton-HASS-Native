import HassDesign
import SwiftUI

/// A highlight tile: small title with an icon, then the tile's content (web `WeatherHighlightTile`).
///
/// Read as one element with the web's aria-label, e.g. `Feels Like 75°F`.
struct WeatherTile<Content: View>: View {
    var title: String
    var symbol: String
    var label: String
    var identifier: String
    var value: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            Label {
                Text(title).font(.footnote.weight(.semibold))
            } icon: {
                Image(systemName: symbol)
            }
            .foregroundStyle(HassTokens.Ink.onDarkSecondary)
            content
        }
        .weatherSurface(padding: HassTokens.Spacing.m)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
        .accessibilityIdentifier(identifier)
    }
}
