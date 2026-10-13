import HassCore
import HassDesign
import SwiftUI

/// Cumulative precipitation over the next six hours.
struct WeatherAccumulationTile: View {
    var forecasts: [WeatherForecast]
    var unit: String

    var body: some View {
        let points = WeatherPrecipitationTimeline.points(forecasts, limit: 6)
        let total = WeatherPrecipitationTimeline.total(points)
        let axis = WeatherPrecipitationTimeline.amountAxis(total: total, unit: unit)
        let labels = WeatherChartText.hourLabels(points)
        let series = zip(labels, points).map { "\($0) \(WeatherChartText.amount($1.cumulative, unit: unit))" }.joined(separator: ", ")
        WeatherTile(
            title: WeatherCopy.text("precipitation.cumulativeHeading"), symbol: WeatherSymbols.precipitation,
            label: WeatherCopy.text("precipitation.cumulativeChartAriaLabel", ["hours": String(points.count), "total": WeatherChartText.amount(total, unit: unit)]),
            identifier: "weather.highlight.accumulation", value: series
        ) {
            if total != nil {
                WeatherBarChart(
                    values: points.map(\.cumulative), domain: axis.domain,
                    axisLabels: (axisText(axis.domain, axis), axisText(axis.step, axis), axisText(0, axis)), hourLabels: labels,
                    tint: Color(red: 0.55, green: 0.85, blue: 1.0)
                )
            } else {
                Text(WeatherCopy.text("unavailable")).font(.subheadline).foregroundStyle(HassTokens.Ink.onDarkSecondary)
            }
        }
    }

    private func axisText(_ value: Double, _ axis: PrecipitationAmountAxis) -> String {
        let normalized = unit.trimmingCharacters(in: .whitespaces).isEmpty ? "in" : unit
        let text = WeatherFormat.number(value, digits: axis.maximumFractionDigits) ?? "--"
        return "\(text) \(normalized)"
    }
}
