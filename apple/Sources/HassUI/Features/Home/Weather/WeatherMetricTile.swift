import HassCore
import HassDesign
import SwiftUI

/// Hourly humidity or cloud cover over the next six hours (web `WeatherHourlyMetricTiles`).
struct WeatherMetricTile: View {
    enum Metric {
        case humidity, cloudCover

        var titleKey: String { self == .humidity ? "hourlyMetrics.humidity" : "hourlyMetrics.cloudCover" }
        var symbol: String { self == .humidity ? WeatherSymbols.humidity : WeatherSymbols.cloudCover }
        var identifier: String { self == .humidity ? "weather.highlight.humidity" : "weather.highlight.cloud" }
        var tint: Color { self == .humidity ? Color(red: 0.40, green: 0.85, blue: 0.80) : Color(red: 0.80, green: 0.86, blue: 0.95) }
    }

    var forecasts: [WeatherForecast]
    var metric: Metric

    var body: some View {
        let points = WeatherHourlyMetrics.points(forecasts)
        let values: [Double?] = points.map { metric == .humidity ? $0.humidity : $0.cloudCover }
        let known = values.compactMap { $0 }
        let domain = WeatherPrecipitationTimeline.chanceDomain(peak: known.max())
        let title = WeatherCopy.text(metric.titleKey)
        let labels = points.enumerated().map { index, point in
            index == 0 ? WeatherCopy.text("precipitation.now") : point.time.map { WeatherDates.hour($0) } ?? "--"
        }
        let series = zip(labels, values).map { "\($0) \(WeatherChartText.percent($1))" }.joined(separator: ", ")
        WeatherTile(
            title: title, symbol: metric.symbol,
            label: WeatherCopy.text("hourlyMetrics.ariaLabel", [
                "hours": String(points.count), "maximum": WeatherChartText.percent(known.max()), "minimum": WeatherChartText.percent(known.min()), "title": title,
            ]),
            identifier: metric.identifier, value: series
        ) {
            if known.isEmpty {
                Text(WeatherCopy.text("unavailable")).font(.subheadline).foregroundStyle(HassTokens.Ink.onDarkSecondary)
            } else {
                WeatherBarChart(
                    values: values, domain: domain, axisLabels: (WeatherChartText.percent(domain), WeatherChartText.percent(domain / 2), WeatherChartText.percent(0)),
                    hourLabels: labels, tint: metric.tint
                )
            }
        }
    }
}

// MARK: - Current-condition tiles
