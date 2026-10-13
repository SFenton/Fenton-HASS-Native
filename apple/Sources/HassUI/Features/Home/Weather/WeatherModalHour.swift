import HassCore
import HassDesign
import SwiftUI

/// One hour in the sheet's carousel, in the active mode (web `HourlyConditionItem`).
struct WeatherModalHour: View {
    var forecast: WeatherForecast
    var index: Int
    var mode: WeatherHourlyMode
    var current: WeatherCurrent

    var body: some View {
        let time = WeatherFormat.hourLabel(forecast.datetime, index: index)
        VStack(spacing: HassTokens.Spacing.s) {
            Text(time)
                .font(.subheadline)
                .foregroundStyle(HassTokens.Ink.onDarkSecondary)
                .multilineTextAlignment(.center)
            visual
            values
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .top)
        .padding(.vertical, HassTokens.Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("weather.hour.\(index)")
    }

    @ViewBuilder
    private var visual: some View {
        switch mode {
        case .condition:
            WeatherGlyph(condition: forecast.condition, size: 30)
        case .precipitation:
            Image(systemName: WeatherSymbols.drop)
                .symbolRenderingMode(.multicolor)
                .foregroundStyle(Color(red: 0.45, green: 0.78, blue: 1.0))
                .font(.system(size: 26))
        case .wind:
            let bearing = WeatherPresentation.windBearing(forecast.windBearing)
            Image(systemName: bearing == nil ? WeatherSymbols.windFlag : WeatherSymbols.windArrow)
                .font(.system(size: 24, weight: .semibold))
                .rotationEffect(.degrees(bearing?.destinationDegrees ?? 0))
        }
    }

    @ViewBuilder
    private var values: some View {
        switch mode {
        case .condition:
            Text(WeatherFormat.temperature(forecast.temperature, unit: current.temperatureUnit))
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
        case .precipitation:
            VStack(spacing: 2) {
                Text(chance).font(.subheadline.weight(.bold)).monospacedDigit()
                if let amount { Text(amount).font(.caption).foregroundStyle(HassTokens.Ink.onDarkSecondary).monospacedDigit() }
            }
        case .wind:
            VStack(spacing: 2) {
                Text(windSpeed).font(.subheadline.weight(.bold)).monospacedDigit()
                if let gust { Text(gust).font(.caption).foregroundStyle(HassTokens.Ink.onDarkSecondary).monospacedDigit() }
            }
        }
    }

    private var chance: String { WeatherFormat.percent(forecast.precipitationProbability) ?? WeatherCopy.text("unavailable") }
    private var amount: String? { WeatherFormat.measure(forecast.precipitation, unit: current.precipitationUnit, digits: 2) }
    private var windSpeed: String { WeatherFormat.windMeasure(forecast.windSpeed, unit: current.windSpeedUnit)?.value ?? "--" }
    private var gust: String? { WeatherFormat.windMeasure(forecast.windGustSpeed, unit: current.windSpeedUnit)?.value }

    /// The web's aria-labels: `7 PM Rain 62°F`, `7 PM precipitation 40%`, `7 PM wind 9 mph gusts 14 mph`.
    var accessibilityText: String {
        let time = WeatherFormat.hourLabel(forecast.datetime, index: index)
        return switch mode {
        case .condition:
            "\(time) \(WeatherConditionInfo(forecast.condition).label) \(WeatherFormat.temperature(forecast.temperature, unit: current.temperatureUnit))"
        case .precipitation:
            "\(time) precipitation \(chance)"
        case .wind:
            "\(time) wind \(windSpeed)\(gust.map { " gusts \($0)" } ?? "")"
        }
    }
}
