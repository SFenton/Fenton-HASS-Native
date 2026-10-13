import HassCore
import HassDesign
import SwiftUI

/// The "Conditions" panel: a 24-hour carousel in three modes (conditions, precipitation, wind), switched with
/// icon buttons (web `HourlyConditionsPanel`).
struct WeatherHourlyPanel: View {
    var feed: WeatherForecastFeed
    var current: WeatherCurrent
    @Binding var mode: WeatherHourlyMode

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            header
            Text(subhead)
                .font(.footnote)
                .foregroundStyle(HassTokens.Ink.onDarkSecondary)
                .accessibilityIdentifier("weather.hourly.subhead")
            content
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: mode)
        }
        .weatherSurface()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(WeatherCopy.text("carousel.section"))
        .accessibilityIdentifier("weather.hourly")
    }

    // MARK: - Header and modes

    @ViewBuilder
    private var header: some View {
        let title = Text("Conditions").font(.headline).accessibilityAddTraits(.isHeader)
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) { title; modePicker }
        } else {
            HStack { title; Spacer(minLength: HassTokens.Spacing.s); modePicker }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(WeatherHourlyMode.allCases) { option in
                Button { mode = option } label: {
                    Image(systemName: WeatherSymbols.mode(option))
                        .font(.body.weight(.semibold))
                        .frame(width: HassTokens.minTarget, height: HassTokens.minTarget)
                        .background {
                            if option == mode {
                                Capsule().fill(HassTokens.Ink.onDark.opacity(0.24))
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(HassTokens.Ink.onDark)
                .accessibilityLabel(option.label)
                .accessibilityHint(option.hint)
                .accessibilityAddTraits(option == mode ? .isSelected : [])
                .accessibilityIdentifier("weather.mode.\(option.rawValue)")
            }
        }
        .background(Color.black.opacity(0.22), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Hourly detail")
    }

    private var subhead: String {
        switch mode {
        case .condition: "Temperature (\(WeatherFormat.unitWithoutDegree(current.temperatureUnit, fallback: "F")))"
        case .precipitation: "Precipitation chance (%)"
        case .wind: "Speed (\(current.windSpeedUnit ?? WeatherUnits.defaultWindSpeedUnit)) · Gusts"
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if feed.showsPlaceholders {
            WeatherPagedCarousel(count: 24, compactPerPage: 5, regularPerPage: 7, label: WeatherCopy.text("carousel.conditions"), identifier: "weather.hour") { _ in
                WeatherModalHourPlaceholder()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading 24-hour conditions")
        } else if feed.forecasts.isEmpty {
            message(feed.error ?? WeatherCopy.text("forecast.hourlyEmpty"))
        } else {
            WeatherPagedCarousel(
                count: feed.forecasts.count, compactPerPage: 5, regularPerPage: 7, label: WeatherCopy.text("carousel.conditions"), identifier: "weather.hour"
            ) { index in
                WeatherModalHour(forecast: feed.forecasts[index], index: index, mode: mode, current: current)
            }
            if let error = feed.error { message(error) }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(HassTokens.Ink.onDarkSecondary)
            .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
            .accessibilityIdentifier("weather.hourly.message")
    }
}
