import AppKit
import Foundation
import HassCore
@testable import HassUI
import SwiftUI
import Testing

/// The Home weather card and sheet on fixture data: symbols, paging math, accessibility text, every state and mode
/// rendered, and the card's wiring to the forecast store in a live window.
@MainActor
struct WeatherViewTests {
    // MARK: - Fixtures

    private func entities(condition: String = "rainy", night: Bool = false, airQuality: Bool = true) -> EntityStore {
        let store = EntityStore()
        store.replaceAll(WeatherFixtures.states(condition: condition, night: night, airQuality: airQuality))
        return store
    }

    private func forecastStore(_ mode: WeatherFixtureCaller.Mode = .normal) async -> (WeatherForecastStore, WeatherFixtureCaller) {
        let caller = WeatherFixtureCaller(mode: mode)
        let store = WeatherForecastStore(requestTimeout: 3600)
        store.activate(caller: caller, revision: "a")
        if mode != .loading { await store.settle() }
        return (store, caller)
    }

    private func renders(_ view: some View, width: CGFloat = 390, height: CGFloat = 900) -> Bool {
        ImageRenderer(content: view.frame(width: width, height: height)).cgImage != nil
    }

    // MARK: - Symbols and paging

    @Test func everySymbolNameExistsInTheSystemSet() {
        for name in WeatherSymbols.allNames {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(name) is not an SF Symbol")
        }
        #expect(WeatherSymbols.condition("sunny", night: true) == "moon.stars.fill")
        #expect(WeatherSymbols.condition("partlycloudy", night: true) == "cloud.moon.fill")
        #expect(WeatherSymbols.condition("rainy", night: true) == "cloud.moon.rain.fill")
        #expect(WeatherSymbols.condition("mystery") == "cloud.fill")
        #expect(WeatherSymbols.highlight(.sun, sun: .sunrise) == "sunrise.fill")
        #expect(WeatherSymbols.highlight(.sun, sun: .sunset) == "sunset.fill")
        #expect(WeatherHourlyMode.allCases.map(WeatherSymbols.mode) == ["cloud.fill", "drop.fill", "wind"])
    }

    @Test func pagingSplitsItemsIntoWholePages() {
        let paging = WeatherCarouselPaging(count: 24, perPage: 6)
        #expect(paging.pageCount == 4)
        #expect(paging.overflows)
        #expect(paging.firstIndex(ofPage: 0) == 0)
        #expect(paging.firstIndex(ofPage: 3) == 18)
        #expect(paging.firstIndex(ofPage: 9) == 23)
        #expect(paging.firstIndex(ofPage: -2) == 0)
        #expect(paging.page(containing: 13) == 2)
        #expect(paging.page(containing: 99) == 3)
        #expect(paging.page(containing: nil) == 0)
        #expect(paging.clamped(7) == 3)
        #expect(paging.clamped(-1) == 0)
        #expect(paging.pageDescription(1) == "Page 2 of 4")
        #expect(paging.pageDescription(40) == "Page 4 of 4")
    }

    @Test func pagingHandlesPartialLastPagesAndTinyCounts() {
        let partial = WeatherCarouselPaging(count: 10, perPage: 6)
        #expect(partial.pageCount == 2)
        #expect(partial.firstIndex(ofPage: 1) == 6)
        let fits = WeatherCarouselPaging(count: 4, perPage: 6)
        #expect(fits.pageCount == 1)
        #expect(!fits.overflows)
        let empty = WeatherCarouselPaging(count: 0, perPage: 0)
        #expect(empty.perPage == 1)
        #expect(empty.pageCount == 1)
        #expect(empty.firstIndex(ofPage: 0) == 0)
        #expect(WeatherCarouselPaging(count: -3, perPage: 4).count == 0)
    }

    @Test func hoursPerPageFollowsSizeClassAndTextSize() {
        func hours(_ sizeClass: UserInterfaceSizeClass?, _ size: DynamicTypeSize) -> Int {
            WeatherCarouselPaging.hoursPerPage(compact: 6, regular: 9, sizeClass: sizeClass, typeSize: size)
        }
        #expect(hours(.compact, .large) == 6)
        #expect(hours(nil, .large) == 6)
        #expect(hours(.regular, .large) == 9)
        #expect(hours(.compact, .xxxLarge) == 5)
        #expect(hours(.compact, .accessibility1) == 3)
        #expect(hours(.compact, .accessibility5) == 2)
        #expect(hours(.regular, .accessibility5) == 3)
        // Never fewer than two hours on a page.
        #expect(WeatherCarouselPaging.hoursPerPage(compact: 3, regular: 3, sizeClass: .compact, typeSize: .accessibility5) == 2)
    }

    // MARK: - Accessibility text

    @Test func hoursAndDaysSpeakTheWebAriaLabels() {
        let current = WeatherCurrent(temperature: 72, temperatureUnit: "°F", windSpeedUnit: "mph", precipitationUnit: "in")
        let hour = WeatherForecast(
            datetime: "2026-09-05T19:00:00Z", condition: "rainy", temperature: 62, precipitation: 0.04, precipitationProbability: 40,
            windGustSpeed: 14, windSpeed: 9
        )
        #expect(WeatherCardHour(forecast: hour, index: 0, current: current).accessibilityText == "Now Rain 62°F")
        #expect(WeatherModalHour(forecast: hour, index: 0, mode: .condition, current: current).accessibilityText == "Now Rain 62°F")
        #expect(WeatherModalHour(forecast: hour, index: 0, mode: .precipitation, current: current).accessibilityText == "Now precipitation 40%")
        #expect(WeatherModalHour(forecast: hour, index: 0, mode: .wind, current: current).accessibilityText == "Now wind 9 mph gusts 14 mph")
        var calm = hour
        calm.windGustSpeed = nil
        calm.precipitationProbability = nil
        #expect(WeatherModalHour(forecast: calm, index: 0, mode: .wind, current: current).accessibilityText == "Now wind 9 mph")
        #expect(WeatherModalHour(forecast: calm, index: 0, mode: .precipitation, current: current).accessibilityText == "Now precipitation Unavailable")

        let day = WeatherForecast(datetime: "2026-09-05T00:00:00Z", condition: "sunny", temperature: 80, templow: 60, precipitation: 0.1, precipitationProbability: 40, windGustSpeed: 15, windSpeed: 8)
        #expect(WeatherDayRow(forecast: day, index: 0, all: [day], current: current, mode: .condition).accessibilityText == "Today Sunny H:80°  L:60°")
        #expect(WeatherDayRow(forecast: day, index: 0, all: [day], current: current, mode: .precipitation).accessibilityText == "Today precipitation 0.1 in 40%")
        #expect(WeatherDayRow(forecast: day, index: 0, all: [day], current: current, mode: .wind).accessibilityText == "Today wind 8-15 mph")
    }

    @Test func cardLabelsMatchTheWeb() {
        let current = WeatherCurrent(condition: "rainy", temperature: 72, temperatureUnit: "°F")
        #expect(WeatherCardContent.openLabel(current) == "Open seven-day weather forecast. Rain, 72°F")
        #expect(WeatherCardContent.openLabel(WeatherCurrent()) == "Open seven-day weather forecast. Weather Unavailable, --")
        #expect(WeatherCardContent.todayLabel(WeatherForecast(condition: "sunny", temperature: 80, templow: 60)) == "Today Sunny H:80°  L:60°")
    }

    @Test func modesHaveLabelsAndHints() {
        #expect(WeatherHourlyMode.allCases.map(\.label) == ["Conditions", "Precipitation", "Wind"])
        #expect(WeatherHourlyMode.allCases.allSatisfy { !$0.hint.isEmpty })
        #expect(Set(WeatherHourlyMode.allCases.map(\.id)).count == 3)
    }

    @Test func backdropsAreDarkEnoughForWhiteText() {
        for scene in WeatherScene.allCases {
            let (top, bottom) = WeatherBackdrop.colors(for: scene)
            for color in [top, bottom] {
                #expect(Self.contrastAgainstWhite(color) >= 4.5, "\(scene) has \(Self.contrastAgainstWhite(color)):1")
            }
        }
    }

    /// WCAG contrast of white text on a colour (sRGB).
    private static func contrastAgainstWhite(_ color: Color) -> Double {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .black
        func channel(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * channel(resolved.redComponent) + 0.7152 * channel(resolved.greenComponent) + 0.0722 * channel(resolved.blueComponent)
        return 1.05 / (luminance + 0.05)
    }

    // MARK: - Rendering

    @Test func cardRendersEveryFeedState() async {
        let ready = await forecastStore()
        let loading = await forecastStore(.loading)
        let failed = await forecastStore(.error)
        let empty = await forecastStore(.empty)
        for (store, _) in [ready, loading, failed, empty] {
            #expect(renders(WeatherCardContent(forecasts: store).environment(entities()), height: 320))
        }
        #expect(ready.0.hourly.forecasts.count == 24)
        #expect(ready.0.daily.forecasts.count == 7)
        #expect(loading.0.hourly.showsPlaceholders)
        #expect(failed.0.hourly.error == "Home Assistant could not reach Pirate Weather.")
        #expect(empty.0.hourly.phase == .empty)
    }

    @Test func cardRendersAtAccessibilityTextSizeAndOnEveryScene() async {
        let (store, _) = await forecastStore()
        let large = WeatherCardContent(forecasts: store).environment(entities()).environment(\.dynamicTypeSize, .accessibility5)
        #expect(renders(large, height: 700))
        for condition in ["sunny", "clear-night", "cloudy", "fog", "rainy", "lightning-rainy", "snowy", "windy", "exceptional", "mystery", "unavailable"] {
            #expect(renders(WeatherCardContent(forecasts: store).environment(entities(condition: condition)), height: 320), "\(condition)")
        }
        #expect(renders(WeatherCardContent(forecasts: store).environment(entities(night: true)), height: 320))
    }

    @Test func cardRendersWithoutAnyWeatherEntity() async {
        let (store, _) = await forecastStore(.loading)
        #expect(renders(WeatherCardContent(forecasts: store).environment(EntityStore()), height: 320))
    }

    @Test func sheetRendersReadyLoadingFailedAndEmpty() async {
        for mode in [WeatherFixtureCaller.Mode.normal, .loading, .error, .empty] {
            let (store, _) = await forecastStore(mode)
            store.updateBriefing(WeatherBriefingContext(temperatureUnit: "°F", windSpeedUnit: "mph"))
            #expect(renders(WeatherSheet(forecasts: store).environment(entities()), height: 1800), "\(mode)")
        }
    }

    @Test func sheetRendersAtAccessibilityTextSizeWithoutAirQuality() async {
        let (store, _) = await forecastStore()
        store.updateBriefing(WeatherBriefingContext())
        let sheet = WeatherSheet(forecasts: store).environment(entities(airQuality: false)).environment(\.dynamicTypeSize, .accessibility5)
        #expect(renders(sheet, height: 4000))
        #expect(store.briefing != nil)
    }

    @Test func panelsRenderInEveryMode() async {
        let (store, _) = await forecastStore()
        let current = WeatherCurrent(entity: entities().value(WeatherEntities.weather))
        for mode in WeatherHourlyMode.allCases {
            #expect(renders(WeatherHourlyPanel(feed: store.hourly, current: current, mode: .constant(mode)), height: 400), "\(mode)")
            #expect(renders(WeatherDailyPanel(feed: store.daily, current: current, mode: mode), height: 600), "\(mode)")
            let large = WeatherDailyPanel(feed: store.daily, current: current, mode: mode).environment(\.dynamicTypeSize, .accessibility3)
            #expect(renders(large, height: 1600), "\(mode)")
        }
    }

    @Test func highlightTilesRenderWithAndWithoutData() async {
        let (store, _) = await forecastStore()
        let live = entities()
        let current = WeatherCurrent(entity: live.value(WeatherEntities.weather))
        let sun = WeatherSunInput(entity: live.value(WeatherEntities.sun))
        #expect(renders(WeatherHighlightsPanel(forecasts: store, current: current, sun: sun).environment(live), height: 1200))
        let night = WeatherSunInput(state: "below_horizon", nextRising: "2026-09-06T13:00:00Z", nextSetting: "2026-09-06T02:00:00Z")
        #expect(renders(WeatherHighlightsPanel(forecasts: store, current: current, sun: night).environment(live), height: 1200))
        let (empty, _) = await forecastStore(.empty)
        #expect(renders(WeatherHighlightsPanel(forecasts: empty, current: WeatherCurrent(), sun: nil).environment(EntityStore()), height: 1200))
        let calm = WeatherCurrent(windSpeed: 0, windSpeedUnit: "mph")
        #expect(renders(WeatherHighlightsPanel(forecasts: empty, current: calm, sun: nil).environment(EntityStore()), height: 1200))
    }

    @Test func gaugesAndBackdropsRender() {
        #expect(renders(WeatherCompass(sourceDegrees: 250), width: 120, height: 120))
        #expect(renders(WeatherCompass(sourceDegrees: nil), width: 120, height: 120))
        #expect(renders(WeatherPressureGauge(percent: 60, value: "29.92", unit: "inHg"), width: 160, height: 120))
        #expect(renders(WeatherSunArc(percent: 40), width: 200, height: 100))
        #expect(renders(WeatherSunArc(percent: nil), width: 200, height: 100))
        for scene in WeatherScene.allCases {
            #expect(renders(WeatherBackdrop(scene: scene), height: 400), "\(scene)")
            #expect(renders(WeatherBackdrop(scene: scene, forceReduceMotion: true), height: 400), "\(scene)")
            #expect(renders(WeatherBackdrop(scene: scene, forceReduceTransparency: true), height: 400), "\(scene)")
        }
        for tone in [WeatherRail.Tone.aqi, .feels, .precipitation, .temperature, .uv, .visibility] {
            #expect(renders(WeatherRail(tone: tone, range: WeatherRailRange(markerPercent: 40, rangeSizePercent: 30, rangeStartPercent: 20)), height: 20))
            #expect(renders(WeatherRail(tone: tone), height: 20))
        }
    }

    @Test func chartsRenderWithUnknownValues() {
        let chart = WeatherBarChart(
            values: [10, nil, 40, 0, 100, 25], domain: 100, axisLabels: ("100%", "50%", "0%"),
            hourLabels: ["Now", "1 PM", "2 PM", "3 PM", "4 PM", "5 PM"], tint: .blue
        )
        #expect(renders(chart, width: 300, height: 140))
        #expect(renders(chart.environment(\.dynamicTypeSize, .accessibility5), width: 300, height: 400))
    }

    // MARK: - Wiring

    /// The card, in a live window, starts the store through the injected service and opens the sheet on request.
    @Test func cardActivatesTheStoreAndOpensTheSheet() async {
        let caller = WeatherFixtureCaller(mode: .normal)
        let forecasts = WeatherForecastStore(requestTimeout: 3600)
        let view = WeatherSummaryCard(startsOpen: true)
            .environment(entities())
            .environment(\.weatherForecastStore, forecasts)
            .environment(\.weatherForecastCaller, caller)
        let window = SheetHostWindow(view, size: CGSize(width: 420, height: 800))
        for _ in 0..<20 where forecasts.hourly.forecasts.isEmpty {
            window.settle(0.1)
            await forecasts.settle()
        }
        #expect(forecasts.daily.forecasts.count == 7)
        #expect(forecasts.hourly.forecasts.count == 24)
        #expect(caller.lastCall.hasPrefix("weather.get_forecasts"))
        window.settle(0.5)
        #expect(window.hasSheet)
        #expect(forecasts.briefing != nil)
    }

    @Test func cardCreatesItsOwnStoreFromTheConnectionWhenNoneIsInjected() {
        let holder = WeatherStoreHolder()
        let first = holder.store(for: nil)
        #expect(holder.store(for: nil) === first)
        #expect(holder.store(for: .fentonHome) === first)
    }

    @Test func galleryFixturesAreRelativeToNow() throws {
        let hourly = WeatherFixtures.hourly()
        #expect(hourly.count == 24)
        let first = try #require(hourly.first?["datetime"]?.string.flatMap(HassDates.iso8601))
        #expect(first <= Date() && Date().timeIntervalSince(first) < 3600)
        #expect(WeatherFixtures.daily().count == 7)
        #expect(WeatherFixtures.states(condition: "sunny", night: false, airQuality: false).count == 2)
        #expect(WeatherFixtures.states(condition: "sunny", night: true, airQuality: true).count == 3)
    }
}
