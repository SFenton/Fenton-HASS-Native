import HassCore
import HassDesign
import SwiftUI

/// The Home weather card (web `WeatherSummary`): condition, temperature, today's range and a 24-hour carousel.
/// Opens the Weather sheet. Spec: `.agents/pages/home/spec.md`; notes: `.agents/patterns/weather.md`.
///
/// The card owns the shared ``WeatherForecastStore`` wiring: it starts fetching when it appears, refetches when the
/// weather entity updates, pauses in the background and tells the store when the websocket is ready.
struct WeatherSummaryCard: View {
    /// Opens the sheet on appearance (gallery and UI tests).
    var startsOpen = false

    @Environment(EntityStore.self) private var entities
    @Environment(HassConnection.self) private var connection: HassConnection?
    @Environment(\.weatherForecastStore) private var injectedStore
    @Environment(\.weatherForecastCaller) private var callerOverride
    @Environment(\.scenePhase) private var scenePhase
    @State private var holder = WeatherStoreHolder()

    init(startsOpen: Bool = false) { self.startsOpen = startsOpen }

    var body: some View {
        let forecasts = injectedStore ?? holder.store(for: connection?.server)
        let weather = entities.entity(WeatherEntities.weather).state
        WeatherCardContent(forecasts: forecasts, startsOpen: startsOpen)
            .onAppear {
                if let caller = callerOverride ?? connection {
                    forecasts.activate(caller: caller, revision: WeatherForecastStore.revision(of: weather), connected: isConnected)
                }
            }
            .onDisappear { forecasts.deactivate() }
            .onChange(of: WeatherForecastStore.revision(of: weather)) { _, revision in forecasts.update(revision: revision) }
            .onChange(of: isConnected) { _, connected in forecasts.setConnected(connected) }
            .onChange(of: scenePhase) { _, phase in forecasts.setForeground(phase == .active) }
            .task(id: briefingKey(forecasts)) { await keepBriefingCurrent(forecasts) }
    }

    /// The websocket is ready. Without a connection (the gallery) forecasts come from the injected service.
    private var isConnected: Bool {
        guard let connection else { return true }
        if case .connected = connection.status { return true }
        return false
    }

    private func briefingKey(_ forecasts: WeatherForecastStore) -> [Date?] {
        [forecasts.daily.updatedAt, forecasts.hourly.updatedAt]
    }

    /// Writes the day's briefing when it is due and checks again every 30 s (web `useWeatherDayBriefing`).
    private func keepBriefingCurrent(_ forecasts: WeatherForecastStore) async {
        while !Task.isCancelled {
            let current = WeatherCurrent(entity: entities.entity(WeatherEntities.weather).state)
            let sun = WeatherSunInput(entity: entities.entity(WeatherEntities.sun).state)
            let aqi = entities.entity(WeatherEntities.airQuality).state?.state
            forecasts.updateBriefing(WeatherBriefingContext(current: current, aqiState: aqi, sun: sun))
            try? await Task.sleep(for: .seconds(30))
        }
    }
}

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
    /// Narrowest an hour may be at the current text size.
    @ScaledMetric(relativeTo: .caption2) private var hourWidth: CGFloat = 44

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
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
                count: 24, minItemWidth: hourWidth, label: WeatherCopy.text("carousel.forecast"), identifier: "home.weather"
            ) { _, _ in WeatherCardHourPlaceholder() }
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
                count: feed.forecasts.count, minItemWidth: hourWidth, label: WeatherCopy.text("carousel.forecast"), identifier: "home.weather"
            ) { index, _ in
                WeatherCardHour(forecast: feed.forecasts[index], index: index, current: current)
            }
        }
    }
}
