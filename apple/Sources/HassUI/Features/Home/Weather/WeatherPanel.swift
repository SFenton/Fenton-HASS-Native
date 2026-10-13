import HassDesign
import SwiftUI

/// The translucent-dark surface behind the sheet's sections and highlight tiles (web `.currentPanel`, `.highlightTile`).
///
/// A darkening wash rather than a light frosted fill: it keeps white text above 4.5:1 on every scene and needs no
/// blur, so Reduce Transparency changes nothing. HIG: Materials, Color.
struct WeatherSurface: ViewModifier {
    var padding: CGFloat = HassTokens.Spacing.l

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous)
                    .strokeBorder(HassTokens.Ink.onDark.opacity(0.14))
            }
            .foregroundStyle(HassTokens.Ink.onDark)
    }
}

extension View {
    /// Wraps content in the weather sheet's panel surface.
    func weatherSurface(padding: CGFloat = HassTokens.Spacing.l) -> some View {
        modifier(WeatherSurface(padding: padding))
    }
}

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
