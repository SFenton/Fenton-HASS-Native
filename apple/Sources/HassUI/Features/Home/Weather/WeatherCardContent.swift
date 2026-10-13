import HassCore
import HassDesign
import SwiftUI

/// The card's presentation: reads entities and the store, owns the sheet.
struct WeatherCardContent: View {
    var forecasts: WeatherForecastStore
    var startsOpen = false

    @Environment(EntityStore.self) private var entities
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var isPresented = false
    @State private var didAutoOpen = false
    /// The hero glyph grows with Dynamic Type.
    @ScaledMetric(relativeTo: .title) private var glyphSize: CGFloat = 40

    var body: some View {
        let current = WeatherCurrent(entity: entities.entity(WeatherEntities.weather).state)
        let sun = WeatherSunInput(entity: entities.entity(WeatherEntities.sun).state)
        let scene = WeatherScene(condition: current.drawnCondition, isNight: sun?.isNight ?? false)
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            Button { isPresented = true } label: { header(current: current, night: sun?.isNight ?? false) }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.openLabel(current))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("home.weather.card")
            todayRow(current: current)
            hourly(current: current)
        }
        .foregroundStyle(HassTokens.Ink.onDark)
        .padding(HassTokens.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            WeatherBackdrop(scene: scene, decorated: false)
                .clipShape(RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous))
        }
        .contentShape(.rect(cornerRadius: HassTokens.Radius.tile, style: .continuous))
        // The whole card opens the sheet; the hours scroll on their own (drags never reach this tap).
        .onTapGesture { isPresented = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.weather")
        .sheet(isPresented: $isPresented) {
            WeatherSheet(forecasts: forecasts)
                .hassSheet()
        }
        .onAppear {
            if startsOpen, !didAutoOpen {
                didAutoOpen = true
                isPresented = true
            }
        }
    }

    /// The web's aria-label for the card button.
    static func openLabel(_ current: WeatherCurrent) -> String {
        "Open seven-day weather forecast. \(current.conditionLabel), \(current.temperatureText)"
    }

    // MARK: - Header

    @ViewBuilder
    private func header(current: WeatherCurrent, night: Bool) -> some View {
        HStack(spacing: HassTokens.Spacing.m) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                    WeatherGlyph(condition: current.drawnCondition, night: night, size: glyphSize)
                    Text(current.conditionLabel).font(.title2.weight(.heavy))
                    Text(current.degreeText).font(.title2.weight(.heavy)).monospacedDigit()
                }
            } else {
                WeatherGlyph(condition: current.drawnCondition, night: night, size: glyphSize)
                Text(current.conditionLabel).font(.title2.weight(.heavy)).lineLimit(2)
                Spacer(minLength: HassTokens.Spacing.s)
                Text(current.degreeText).font(.title2.weight(.heavy)).monospacedDigit()
            }
            Image(systemName: WeatherSymbols.disclosure)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(HassTokens.Ink.onDarkSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
        .contentShape(.rect)
    }

    // MARK: - Today

    /// The web's aria-label for the Today row: `Today Rain H:70°  L:55°`.
    static func todayLabel(_ today: WeatherForecast) -> String {
        "Today \(WeatherConditionInfo(today.condition).label) \(WeatherFormat.compactHighLow(today))"
    }

    @ViewBuilder
    private func todayRow(current: WeatherCurrent) -> some View {
        if let today = forecasts.daily.forecasts.first {
            let rail = WeatherRails.hero(forecast: today, currentTemperature: current.temperature)
            let label = Self.todayLabel(today)
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                        HStack { WeatherGlyph(condition: today.condition, size: 24); Spacer() }
                        Text("Low \(WeatherFormat.degree(today.templow))").font(.subheadline.weight(.heavy))
                        WeatherRail(tone: .temperature, range: rail ?? WeatherRailRange())
                        Text("High \(WeatherFormat.degree(today.temperature))").font(.subheadline.weight(.heavy))
                    }
                } else {
                    HStack(spacing: HassTokens.Spacing.s) {
                        WeatherGlyph(condition: today.condition, size: 24).frame(width: 30)
                        Text(WeatherFormat.degree(today.templow)).font(.subheadline.weight(.heavy)).monospacedDigit()
                        WeatherRail(tone: .temperature, range: rail ?? WeatherRailRange())
                        Text(WeatherFormat.degree(today.temperature)).font(.subheadline.weight(.heavy)).monospacedDigit()
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityIdentifier("home.weather.today")
        } else {
            // Same height as the loaded row, so the card does not jump when the daily forecast arrives.
            HStack(spacing: HassTokens.Spacing.s) {
                Circle().frame(width: 22, height: 22)
                Capsule().frame(width: 28, height: 8)
                WeatherRail(tone: .temperature)
                Capsule().frame(width: 28, height: 8)
            }
            .foregroundStyle(HassTokens.Ink.onDark.opacity(0.18))
            .frame(minHeight: 30)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Hourly

    @ViewBuilder
    private func hourly(current: WeatherCurrent) -> some View {
        let feed = forecasts.hourly
        if feed.showsPlaceholders {
            WeatherPagedCarousel(
                count: 24, compactPerPage: 6, regularPerPage: 9, label: WeatherCopy.text("carousel.forecast"), identifier: "home.weather"
            ) { _ in WeatherCardHourPlaceholder() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Loading 24-hour weather forecast")
        } else if feed.forecasts.isEmpty {
            Text(feed.error ?? WeatherCopy.text("forecast.hourlyEmpty"))
                .font(.footnote)
                .foregroundStyle(HassTokens.Ink.onDarkSecondary)
                .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                .accessibilityIdentifier("home.weather.hourlyMessage")
        } else {
            WeatherPagedCarousel(
                count: feed.forecasts.count, compactPerPage: 6, regularPerPage: 9, label: WeatherCopy.text("carousel.forecast"), identifier: "home.weather"
            ) { index in
                WeatherCardHour(forecast: feed.forecasts[index], index: index, current: current)
            }
        }
    }
}
