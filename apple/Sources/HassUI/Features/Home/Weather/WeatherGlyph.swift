import HassCore
import SwiftUI

/// A condition glyph in multicolor SF Symbol rendering. Its ink, not its frame, sits on the leading edge.
struct WeatherGlyph: View {
    var condition: String?
    var night = false
    /// Point size at the default text size; grows with Dynamic Type.
    var size: CGFloat
    @ScaledMetric private var scale: CGFloat = 1

    var body: some View {
        let symbol = WeatherSymbols.condition(condition, night: night)
        let pointSize = size * min(scale, 2)
        Image(systemName: symbol)
            .symbolRenderingMode(.multicolor)
            .font(.system(size: pointSize))
            // The symbol's own empty space on the left, so its ink lines up with the text below it.
            .padding(.leading, -WeatherSymbols.leadingInset(of: symbol) * pointSize)
            .accessibilityHidden(true)
    }
}
