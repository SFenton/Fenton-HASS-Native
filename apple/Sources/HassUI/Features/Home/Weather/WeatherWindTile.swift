import HassCore
import HassDesign
import SwiftUI

/// The wide wind tile: speed, gust and direction beside the compass (web `WindHighlightTile`).
struct WeatherWindTile: View {
    var tile: WeatherHighlight
    var wind: WeatherHighlight.Wind

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .footnote) private var compassSize: CGFloat = 104

    var body: some View {
        WeatherTile(
            title: tile.title, symbol: WeatherSymbols.highlight(.wind), label: tile.accessibilityLabel,
            identifier: "weather.highlight.wind", value: nil
        ) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: HassTokens.Spacing.m) { readout; compass }
            } else {
                HStack(alignment: .center, spacing: HassTokens.Spacing.m) { readout; Spacer(minLength: 0); compass }
            }
        }
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            row(wind.speedLabel, wind.speedValue)
            row(wind.gustLabel, wind.gustValue)
            row(wind.directionLabel, wind.directionValue)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.footnote).foregroundStyle(HassTokens.Ink.onDarkSecondary)
            Text(value).font(.headline).monospacedDigit()
        }
    }

    private var compass: some View {
        WeatherCompass(sourceDegrees: wind.showVector ? wind.bearingDegrees : nil)
            .frame(width: min(compassSize, 160), height: min(compassSize, 160))
    }
}
