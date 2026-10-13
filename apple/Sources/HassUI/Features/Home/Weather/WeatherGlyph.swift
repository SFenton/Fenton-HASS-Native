import HassCore
import SwiftUI

/// A condition glyph in multicolor SF Symbol rendering.
struct WeatherGlyph: View {
    var condition: String?
    var night = false
    /// Point size at the default text size; grows with Dynamic Type.
    var size: CGFloat
    @ScaledMetric private var scale: CGFloat = 1

    var body: some View {
        Image(systemName: WeatherSymbols.condition(condition, night: night))
            .symbolRenderingMode(.multicolor)
            .font(.system(size: size * min(scale, 2)))
            .accessibilityHidden(true)
    }
}
