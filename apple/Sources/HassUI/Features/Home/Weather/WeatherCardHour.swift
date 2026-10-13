import HassCore
import HassDesign
import SwiftUI

/// One hour in the Home card's carousel: time, glyph and temperature (web hero hourly item).
struct WeatherCardHour: View {
    var forecast: WeatherForecast
    var index: Int
    var current: WeatherCurrent

    var body: some View {
        VStack(spacing: HassTokens.Spacing.xs) {
            Text(WeatherFormat.hourLabel(forecast.datetime, index: index))
                .font(.caption2.weight(.heavy))
                .multilineTextAlignment(.center)
            WeatherGlyph(condition: forecast.condition, size: 22)
            Text(WeatherFormat.degree(forecast.temperature))
                .font(.caption.weight(.bold))
                .monospacedDigit()
        }
        .foregroundStyle(HassTokens.Ink.onDark)
        .frame(maxWidth: .infinity, minHeight: 62)
        .padding(.vertical, HassTokens.Spacing.xs)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("home.weather.hour.\(index)")
    }

    /// The web's aria-label: `7 PM Rain 62°F`.
    var accessibilityText: String {
        let time = WeatherFormat.hourLabel(forecast.datetime, index: index)
        let condition = WeatherConditionInfo(forecast.condition).label
        return "\(time) \(condition) \(WeatherFormat.temperature(forecast.temperature, unit: current.temperatureUnit))"
    }
}
