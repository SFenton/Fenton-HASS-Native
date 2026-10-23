import HassCore
import HassDesign
import SwiftUI

/// The card's presentation: reads entities and the store, owns the sheet.
///
/// Direction G (`.agents/design/direction-g.md`, mockup n1 home): a thin module on the wallpaper with the glyph, the
/// condition and today's high and low on the left, the screen's one display numeral on the right (header: option D,
/// `.agents/design/weather-card-header.md`), then the day's first briefing sentence, then the hours.
struct WeatherCardContent: View {
    var forecasts: WeatherForecastStore
    var startsOpen = false

    @Environment(EntityStore.self) private var entities
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.weatherCardIsNarrow) private var isNarrow
    @Environment(\.sectionIsShowing) private var sectionIsShowing
    /// Header measurements for the stacked-layout decision (``rangeOverflows``).
    @State private var headerWidth: CGFloat = 0
    @State private var readingWidth: CGFloat = 0
    @State private var rangeWidth: CGFloat = 0
    @State private var isPresented = false
    @State private var didAutoOpen = false
    /// The hero glyph grows with Dynamic Type.
    @ScaledMetric(relativeTo: .title) private var glyphSize: CGFloat = 40
    /// The display numeral (direction G, Type: one per screen, Thin, monospaced digits).
    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 64
    /// The briefing's sentence while forecasts are missing (`WeatherDayBriefingGenerator`).
    static let unavailableKey = "briefing.unavailable"
    /// The numeral's largest size at accessibility text sizes.
    static let maxNumeralSize: CGFloat = 96

    var body: some View {
        let current = WeatherCurrent(entity: entities.entity(WeatherEntities.weather).state)
        let sun = WeatherSunInput(entity: entities.entity(WeatherEntities.sun).state)
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            header(current: current, night: sun?.isNight ?? false)
            separator
            if let line = Self.briefingLine(forecasts.briefing) {
                Text(line)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("home.weather.briefing")
                separator
            }
            hourly(current: current)
        }
        .foregroundStyle(HassTokens.Ink.onDark)
        .padding(HassTokens.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .module()
        .contentShape(.rect(cornerRadius: HassTokens.Radius.module, style: .continuous))
        // The whole card opens the sheet; the hours scroll on their own (drags never reach this tap).
        .onTapGesture { isPresented = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.weather")
        .sheet(isPresented: $isPresented) {
            WeatherSheet(forecasts: forecasts)
                .hassSheet(.page, height: .full, appearance: .dark) // Forecast over a condition gradient
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

    /// The card's one-line outlook: the first sentence of today's briefing, or nil before one is written. The
    /// "appears once … returns forecast data" placeholder sentence is left out: the hours already say so.
    static func briefingLine(_ briefing: WeatherDayBriefing?) -> String? {
        guard let first = briefing?.sentences.first, first.key != unavailableKey else { return nil }
        let line = WeatherBriefingRenderer.render(first)
        return line.isEmpty ? nil : line
    }

    private var separator: some View {
        Rectangle()
            .fill(HassTokens.Surface.separator)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    // MARK: - Header

    /// Option D (`.agents/design/weather-card-header.md`): the glyph, the condition and today's range in a left column, the
    /// numeral with its chevron on the right. The numeral never truncates; the condition scrolls as a ticker when it does not
    /// fit its column. At accessibility sizes, or when the range does not fit the column, the numeral takes the top row with the
    /// glyph and the condition and range stack under it at full width.
    @ViewBuilder
    private func header(current: WeatherCurrent, night: Bool) -> some View {
        let stacked = typeSize.isAccessibilitySize || rangeOverflows
        let glyph = WeatherGlyph(condition: current.drawnCondition, night: night, size: glyphSize)
        let reading = reading(current)
        let condition = TickerLabel(current.conditionLabel, font: .headline, wraps: typeSize.isAccessibilitySize, probe: "home.weather.condition")
            .foregroundStyle(HassTokens.Ink.onDark)
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                    HStack(alignment: .center, spacing: HassTokens.Spacing.m) {
                        glyph
                        Spacer(minLength: HassTokens.Spacing.s)
                        reading
                    }
                    condition
                    todayRange
                }
            } else {
                HStack(alignment: .center, spacing: HassTokens.Spacing.m) {
                    VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                        glyph
                        condition
                        todayRange
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    reading.layoutPriority(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { cardButton(current) }
        .background(alignment: .topLeading) { rangeMeasure(current) }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { headerWidth = $0 }
        .environment(\.tickerIsOnScreen, sectionIsShowing)
    }

    /// The numeral with the chevron beside it, centred on the numeral. Drawn only: the card's button (``cardButton(_:)``) names the
    /// condition and the reading.
    private func reading(_ current: WeatherCurrent) -> some View {
        HStack(alignment: .center, spacing: HassTokens.Spacing.xs) {
            Text(current.degreeText)
                // Capped: past this a three-digit reading no longer fits the folded Duo's card at AX5.
                .font(.system(size: min(numeralSize, Self.maxNumeralSize), weight: .thin))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .overlay { if TickerLabel.probeEnabled { numeralProbe } }
            Image(systemName: WeatherSymbols.disclosure)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(HassTokens.Surface.secondaryOnModule)
        }
        .frame(minHeight: HassTokens.minTarget)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { readingWidth = $0 }
        .accessibilityHidden(true)
    }

    /// The card's one button for assistive technology, behind the header so its frame covers the glyph, condition and reading it
    /// names (the audit finds no drawn text without an element); today's range stays its own element on top.
    private func cardButton(_ current: WeatherCurrent) -> some View {
        Button { isPresented = true } label: {
            Color.clear.contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.openLabel(current))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home.weather.card")
    }

    /// An invisible element with the numeral's frame, for UI tests (`FENTON_TICKER_PROBE=1`).
    private var numeralProbe: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel("numeral")
            .accessibilityIdentifier("home.weather.numeral")
    }

    /// Whether today's range is wider than the left column. Measured from the header's width, the reading's width and the
    /// range's natural width, none of which depends on the layout chosen, so choosing the stacked layout cannot flip it back.
    private var rangeOverflows: Bool {
        guard headerWidth > 0, readingWidth > 0, rangeWidth > 0 else { return false }
        return rangeWidth > headerWidth - readingWidth - HassTokens.Spacing.m + 0.5
    }

    /// An invisible one-line copy of the range, to measure it.
    @ViewBuilder
    private func rangeMeasure(_ current: WeatherCurrent) -> some View {
        if let today = forecasts.daily.forecasts.first {
            Text(WeatherFormat.compactHighLow(today))
                .font(.body)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { rangeWidth = $0 }
                .accessibilityHidden(true)
        }
    }

    // MARK: - Today

    /// The web's aria-label for the Today row: `Today Rain H:70°  L:55°`.
    static func todayLabel(_ today: WeatherForecast) -> String {
        "Today \(WeatherConditionInfo(today.condition).label) \(WeatherFormat.compactHighLow(today))"
    }

    /// Today's high and low under the condition; nothing until the daily forecast arrives.
    @ViewBuilder
    private var todayRange: some View {
        if let today = forecasts.daily.forecasts.first {
            Text(WeatherFormat.compactHighLow(today))
                .font(.body)
                .lineLimit(1)
                .foregroundStyle(HassTokens.Surface.secondaryOnModule)
                .monospacedDigit()
                .accessibilityLabel(Self.todayLabel(today))
                .accessibilityIdentifier("home.weather.today")
        } else {
            // Holds the line's height, so the card does not jump when the daily forecast arrives.
            Text(" ").font(.body).accessibilityHidden(true)
        }
    }

    // MARK: - Hourly

    @ViewBuilder
    private func hourly(current: WeatherCurrent) -> some View {
        let feed = forecasts.hourly
        if feed.showsPlaceholders {
            WeatherPagedCarousel(
                count: 24, compactPerPage: 6, regularPerPage: isNarrow ? 6 : 9, label: WeatherCopy.text("carousel.forecast"), identifier: "home.weather"
            ) { _ in WeatherCardHourPlaceholder() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Loading 24-hour weather forecast")
        } else if feed.forecasts.isEmpty {
            Text(feed.error ?? WeatherCopy.text("forecast.hourlyEmpty"))
                .font(.footnote)
                .foregroundStyle(HassTokens.Ink.onDarkSecondary)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                .accessibilityIdentifier("home.weather.hourlyMessage")
        } else {
            WeatherPagedCarousel(
                count: feed.forecasts.count, compactPerPage: 6, regularPerPage: isNarrow ? 6 : 9, label: WeatherCopy.text("carousel.forecast"), identifier: "home.weather"
            ) { index in
                WeatherCardHour(forecast: feed.forecasts[index], index: index, current: current)
            }
        }
    }
}
