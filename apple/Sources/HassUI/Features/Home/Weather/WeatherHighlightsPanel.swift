import HassCore
import HassDesign
import SwiftUI

/// The "Highlights" grid (web `highlightsPanel`): air quality, precipitation and accumulation, humidity and cloud
/// cover, then feels like, UV, wind, sun, visibility and pressure. Laid out on ``DynamicGridLayout``: wide tiles
/// take two tracks, and at larger text sizes the grid drops to fewer columns instead of clipping.
struct WeatherHighlightsPanel: View {
    var forecasts: WeatherForecastStore
    var current: WeatherCurrent
    var sun: WeatherSunInput?

    @Environment(EntityStore.self) private var entities
    /// Narrowest a tile may be; grows with Dynamic Type so the grid reflows to fewer columns.
    @ScaledMetric(relativeTo: .footnote) private var tileWidth: CGFloat = 150

    var body: some View {
        let hourly = forecasts.hourly.forecasts
        let tiles = WeatherHighlights.tiles(current: current, today: forecasts.daily.forecasts.first, sun: sun)
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            Text("Highlights")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            DynamicGridLayout(minCellWidth: tileWidth, maxColumns: 4) {
                if let aqiState = entities.entity(WeatherEntities.airQuality).state {
                    WeatherAqiTile(tile: WeatherHighlights.airQuality(state: aqiState.state)).gridSpan(2)
                }
                WeatherChanceTile(forecasts: hourly).gridSpan(2)
                WeatherAccumulationTile(forecasts: hourly, unit: current.precipitationUnit ?? WeatherUnits.defaultPrecipitationUnit).gridSpan(2)
                WeatherMetricTile(forecasts: hourly, metric: .humidity).gridSpan(2)
                WeatherMetricTile(forecasts: hourly, metric: .cloudCover).gridSpan(2)
                ForEach(tiles) { tile in
                    WeatherHighlightTile(tile: tile, sun: sun).gridSpan(tile.kind == .wind ? 2 : 1)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Weather highlights")
        .accessibilityIdentifier("weather.highlights")
    }
}

// MARK: - Air quality
