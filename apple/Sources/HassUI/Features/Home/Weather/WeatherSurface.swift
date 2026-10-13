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
