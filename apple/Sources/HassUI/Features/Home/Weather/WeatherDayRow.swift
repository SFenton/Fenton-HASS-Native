import HassCore
import HassDesign
import SwiftUI

/// One day of the seven-day list, in the active mode (web `ForecastRow`).
struct WeatherDayRow: View {
    var forecast: WeatherForecast
    var index: Int
    var all: [WeatherForecast]
    var current: WeatherCurrent
    var mode: WeatherHourlyMode

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var dayWidth: CGFloat = 48
    @ScaledMetric(relativeTo: .subheadline) private var valueWidth: CGFloat = 40

    var body: some View {
        let day = WeatherFormat.dayLabel(forecast.datetime, index: index)
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                    Text(day).font(.subheadline.weight(.bold))
                    detail(stacked: true)
                }
            } else {
                HStack(spacing: HassTokens.Spacing.s) {
                    Text(day).font(.subheadline.weight(.bold)).frame(width: dayWidth, alignment: .leading)
                    detail(stacked: false)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
        .padding(.vertical, HassTokens.Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("weather.day.\(index)")
    }

    @ViewBuilder
    private func detail(stacked: Bool) -> some View {
        switch mode {
        case .condition:
            let rail = WeatherRails.week(forecast: forecast, all: all, currentTemperature: current.temperature, index: index) ?? WeatherRailRange()
            let shown = WeatherRailRange(markerPercent: index == 0 ? rail.markerPercent : nil, rangeSizePercent: rail.rangeSizePercent, rangeStartPercent: rail.rangeStartPercent)
            HStack(spacing: HassTokens.Spacing.s) {
                WeatherGlyph(condition: forecast.condition, size: 26).frame(width: 32)
                Text(WeatherFormat.degree(forecast.templow)).font(.subheadline.weight(.bold)).monospacedDigit().frame(minWidth: valueWidth, alignment: .trailing)
                WeatherRail(tone: .temperature, range: shown)
                Text(WeatherFormat.degree(forecast.temperature)).font(.subheadline.weight(.bold)).monospacedDigit().frame(minWidth: valueWidth, alignment: .trailing)
            }
        case .precipitation:
            let probability = forecast.precipitationProbability
            HStack(spacing: HassTokens.Spacing.s) {
                Image(systemName: WeatherSymbols.drop)
                    .symbolRenderingMode(.multicolor)
                    .foregroundStyle(Color(red: 0.45, green: 0.78, blue: 1.0))
                    .frame(width: 32)
                WeatherRail(tone: .precipitation, range: WeatherRailRange(
                    markerPercent: (probability ?? 0) > 0 ? probability : nil, rangeSizePercent: probability, rangeStartPercent: 0
                ))
                Text(amount).font(.subheadline).monospacedDigit().frame(minWidth: valueWidth + 14, alignment: .trailing)
                Text(chance).font(.subheadline.weight(.bold)).monospacedDigit().frame(minWidth: valueWidth, alignment: .trailing)
            }
        case .wind:
            let bearing = WeatherPresentation.windBearing(forecast.windBearing)
            HStack(spacing: HassTokens.Spacing.s) {
                Image(systemName: bearing == nil ? WeatherSymbols.windFlag : WeatherSymbols.windArrow)
                    .font(.system(size: 22, weight: .semibold))
                    .rotationEffect(.degrees(bearing?.destinationDegrees ?? 0))
                    .frame(width: 32)
                Text(windRange).font(.subheadline.weight(.bold)).monospacedDigit()
                Spacer(minLength: 0)
            }
        }
    }

    private var amount: String { WeatherFormat.measure(forecast.precipitation, unit: current.precipitationUnit, digits: 2) ?? WeatherCopy.text("unavailable") }
    private var chance: String { WeatherFormat.percent(forecast.precipitationProbability) ?? WeatherCopy.text("unavailable") }
    private var windRange: String { WeatherFormat.windRange(speed: forecast.windSpeed, gust: forecast.windGustSpeed, unit: current.windSpeedUnit) }

    /// The web's aria-labels: `Mon Rain H:70°  L:55°`, `Mon precipitation 0.10 in 40%`, `Mon wind 8-15 mph`.
    var accessibilityText: String {
        let day = WeatherFormat.dayLabel(forecast.datetime, index: index)
        return switch mode {
        case .condition: "\(day) \(WeatherConditionInfo(forecast.condition).label) \(WeatherFormat.compactHighLow(forecast))"
        case .precipitation: "\(day) precipitation \(amount) \(chance)"
        case .wind: "\(day) wind \(windRange)"
        }
    }
}
