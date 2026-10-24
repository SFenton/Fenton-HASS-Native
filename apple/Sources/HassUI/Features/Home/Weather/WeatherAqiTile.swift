import HassCore
import HassDesign
import SwiftUI

/// The US AQI tile (web `WeatherAqiTile`).
struct WeatherAqiTile: View {
    var tile: WeatherHighlight

    var body: some View {
        WeatherTile(
            title: tile.title, symbol: WeatherSymbols.highlight(.aqi), label: tile.accessibilityLabel,
            identifier: "weather.highlight.aqi", value: nil
        ) {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                HStack(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.s) {
                    Text(tile.value).font(.title.bold()).monospacedDigit()
                    Text(tile.status ?? "").font(.subheadline).foregroundStyle(HassTokens.Ink.onDarkSecondary)
                }
                WeatherRail(tone: .aqi, range: WeatherRailRange(markerPercent: tile.percent))
            }
        }
    }
}

// MARK: - Charts
