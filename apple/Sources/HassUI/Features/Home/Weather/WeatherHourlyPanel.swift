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
    /// Narrowest an hour may be at the current text size.
    @ScaledMetric(relativeTo: .subheadline) private var hourWidth: CGFloat = 62

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
            WeatherPagedCarousel(count: 24, minItemWidth: hourWidth, label: WeatherCopy.text("carousel.conditions"), identifier: "weather.hour") { _, _ in
                WeatherModalHourPlaceholder()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading 24-hour conditions")
        } else if feed.forecasts.isEmpty {
            message(feed.error ?? WeatherCopy.text("forecast.hourlyEmpty"))
        } else {
            WeatherPagedCarousel(
                count: feed.forecasts.count, minItemWidth: hourWidth, label: WeatherCopy.text("carousel.conditions"), identifier: "weather.hour"
            ) { index, _ in
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

/// The skeleton of a sheet hour while the forecast loads.
struct WeatherModalHourPlaceholder: View {
    var body: some View {
        VStack(spacing: HassTokens.Spacing.m) {
            Capsule().frame(width: 36, height: 10)
            Circle().frame(width: 30, height: 30)
            Capsule().frame(width: 32, height: 10)
        }
        .foregroundStyle(HassTokens.Ink.onDark.opacity(0.16))
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .top)
        .padding(.vertical, HassTokens.Spacing.xs)
    }
}
