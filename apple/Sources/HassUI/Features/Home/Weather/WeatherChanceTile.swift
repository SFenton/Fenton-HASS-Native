import HassCore
import HassDesign
import SwiftUI

/// Hourly precipitation chance over the next six hours.
struct WeatherChanceTile: View {
    var forecasts: [WeatherForecast]

    var body: some View {
        let points = WeatherPrecipitationTimeline.points(forecasts, limit: 6)
        let peak = WeatherPrecipitationTimeline.peakChance(points)
        let domain = WeatherPrecipitationTimeline.chanceDomain(peak: peak)
        let labels = WeatherChartText.hourLabels(points)
        let series = zip(labels, points).map { "\($0) \(WeatherChartText.percent($1.probability))" }.joined(separator: ", ")
        WeatherTile(
            title: WeatherCopy.text("precipitation.title"), symbol: WeatherSymbols.precipitation,
            label: WeatherCopy.text("precipitation.chanceChartAriaLabel", ["chance": WeatherChartText.percent(peak), "hours": String(points.count)]),
            identifier: "weather.highlight.precipitation", value: series
        ) {
            if peak != nil {
                WeatherBarChart(
                    values: points.map(\.probability), domain: domain,
                    axisLabels: (WeatherChartText.percent(domain), WeatherChartText.percent(domain / 2), WeatherChartText.percent(0)), hourLabels: labels,
                    tint: Color(red: 0.45, green: 0.78, blue: 1.0)
                )
            } else {
                unavailable
            }
        }
    }

    private var unavailable: some View {
        Text(WeatherCopy.text("unavailable")).font(.subheadline).foregroundStyle(HassTokens.Ink.onDarkSecondary)
    }
}
