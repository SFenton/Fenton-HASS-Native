import HassCore
import HassDesign
import SwiftUI

/// The card's presentation: reads entities and the store, owns the sheet.
///
/// Direction G (`.agents/design/direction-g.md`, mockup n1 home): a thin module on the wallpaper with the glyph and
/// the screen's one display numeral, the condition and today's high and low trailing, the day's first briefing
/// sentence, then the hours.
struct WeatherCardContent: View {
    var forecasts: WeatherForecastStore
    var startsOpen = false

    @Environment(EntityStore.self) private var entities
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.weatherCardIsNarrow) private var isNarrow
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
                .hassSheet(.page)
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

    @ViewBuilder
    private func header(current: WeatherCurrent, night: Bool) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: HassTokens.Spacing.s))
            : AnyLayout(HStackLayout(alignment: .center, spacing: HassTokens.Spacing.m))
        layout {
            Button { isPresented = true } label: {
                // At accessibility sizes the glyph sits above the numeral, so "54°" keeps the card's width.
                let hero = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: HassTokens.Spacing.xs))
                    : AnyLayout(HStackLayout(spacing: HassTokens.Spacing.m))
                hero {
                    WeatherGlyph(condition: current.drawnCondition, night: night, size: glyphSize)
                    Text(current.degreeText)
                        // Capped: past this a three-digit reading no longer fits the folded Duo's card at AX5.
                        .font(.system(size: min(numeralSize, Self.maxNumeralSize), weight: .thin))
                        .monospacedDigit()
                        .lineLimit(1)
                        // The condition wraps first; the reading never truncates.
                        .layoutPriority(1)
                }
                .frame(minHeight: HassTokens.minTarget)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.openLabel(current))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("home.weather.card")
            if !typeSize.isAccessibilitySize { Spacer(minLength: HassTokens.Spacing.s) }
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                HStack(spacing: HassTokens.Spacing.xs) {
                    Text(current.conditionLabel)
                        .font(.headline)
                        .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: WeatherSymbols.disclosure)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(HassTokens.Surface.secondaryOnModule)
                }
                // The card button already reads the condition.
                .accessibilityHidden(true)
                todayRange
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
