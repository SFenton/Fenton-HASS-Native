import HassCore
import HassDesign
import SwiftUI

/// The "Next Seven Days" panel (web `forecastPanel`): one row per day, in the mode picked in the Conditions panel.
struct WeatherDailyPanel: View {
    var feed: WeatherForecastFeed
    var current: WeatherCurrent
    var mode: WeatherHourlyMode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            Text("Next Seven Days")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if feed.showsPlaceholders {
                VStack(spacing: HassTokens.Spacing.s) {
                    ForEach(0..<7, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous)
                            .fill(HassTokens.Ink.onDark.opacity(0.1))
                            .frame(height: 44)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Loading seven-day weather forecast")
            } else if feed.forecasts.isEmpty {
                Text(feed.error ?? WeatherCopy.text("forecast.dailyEmpty"))
                    .font(.subheadline)
                    .foregroundStyle(HassTokens.Ink.onDarkSecondary)
                    .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
                    .accessibilityIdentifier("weather.daily.message")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(feed.forecasts.enumerated()), id: \.offset) { index, forecast in
                        if index > 0 { Divider().overlay(HassTokens.Ink.onDark.opacity(0.14)) }
                        WeatherDayRow(forecast: forecast, index: index, all: feed.forecasts, current: current, mode: mode)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: mode)
            }
        }
        .weatherSurface()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Seven-day weather forecast")
        .accessibilityIdentifier("weather.daily")
    }
}
