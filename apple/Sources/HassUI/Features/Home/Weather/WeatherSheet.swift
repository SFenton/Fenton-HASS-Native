import HassCore
import HassDesign
import SwiftUI

/// The Weather modal (web `WeatherForecastSheet`): hero, the Today briefing, hourly conditions in three modes, the
/// next seven days and the highlight tiles. HIG: Sheets (full height, inline title, Done), Scroll views, Weather data.
///
/// Reads the same ``WeatherForecastStore`` as the Home card, so opening it never reloads: whatever the card shows is
/// already here. Dark appearance throughout: the condition gradient is always dark.
struct WeatherSheet: View {
    var forecasts: WeatherForecastStore

    @Environment(EntityStore.self) private var entities
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var mode: WeatherHourlyMode = .condition
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 76

    var body: some View {
        let current = WeatherCurrent(entity: entities.entity(WeatherEntities.weather).state)
        let sun = WeatherSunInput(entity: entities.entity(WeatherEntities.sun).state)
        let scene = WeatherScene(condition: current.drawnCondition, isNight: sun?.isNight ?? false)
        NavigationStack {
            ScrollView {
                VStack(spacing: HassTokens.Spacing.l) {
                    hero(current: current, forecasts: forecasts)
                    WeatherBriefingPanel(briefing: forecasts.briefing, current: current, night: sun?.isNight ?? false)
                    WeatherHourlyPanel(feed: forecasts.hourly, current: current, mode: $mode)
                    WeatherDailyPanel(feed: forecasts.daily, current: current, mode: mode)
                    WeatherHighlightsPanel(forecasts: forecasts, current: current, sun: sun)
                }
                .padding(.horizontal, HassTokens.Spacing.l)
                .padding(.bottom, HassTokens.Spacing.xl)
            }
            .scrollIndicators(.hidden)
            .background { WeatherBackdrop(scene: scene).ignoresSafeArea() }
            .navigationTitle("Weather")
            .inlineNavigationTitle()
            .weatherSubtitle(WeatherCopy.text("subtitle", ["temperature": current.degreeText, "condition": current.conditionLabel]))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            #if os(iOS)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
        }
        .foregroundStyle(HassTokens.Ink.onDark)
        .preferredColorScheme(.dark)
        .presentationBackground { WeatherBackdrop(scene: scene).ignoresSafeArea() }
        .accessibilityIdentifier("weather.sheet")
    }

    // MARK: - Hero

    private func hero(current: WeatherCurrent, forecasts: WeatherForecastStore) -> some View {
        VStack(spacing: HassTokens.Spacing.xs) {
            Text(current.degreeText)
                .font(.system(size: heroSize, weight: .thin))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityIdentifier("weather.hero.temperature")
            Text(current.conditionLabel)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("weather.hero.condition")
            if let today = forecasts.daily.forecasts.first {
                let highLow = WeatherFormat.modalHighLow(today)
                if !highLow.isEmpty {
                    Text(highLow)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HassTokens.Ink.onDarkSecondary)
                        .accessibilityIdentifier("weather.hero.highLow")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, HassTokens.Spacing.m)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// A subtitle under the navigation title where the system supports one (iOS 26); the hero says the same earlier.
    @ViewBuilder
    func weatherSubtitle(_ subtitle: String) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            navigationSubtitle(subtitle)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// The "Today" panel: a headline with an icon, then a few narrative sentences (web `currentPanel`).
struct WeatherBriefingPanel: View {
    var briefing: WeatherDayBriefing?
    var current: WeatherCurrent
    var night: Bool

    var body: some View {
        let headline = briefing.map(WeatherBriefingRenderer.headline) ?? WeatherCopy.text("headline.weather", ["condition": current.conditionLabel])
        let sentences = briefing.map { $0.sentences.map(WeatherBriefingRenderer.render) } ?? [WeatherCopy.text("briefing.unavailable")]
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            HStack(spacing: HassTokens.Spacing.m) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(WeatherCopy.text("headline.label"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(HassTokens.Ink.onDarkSecondary)
                    Text(headline)
                        .font(.title3.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("weather.today.headline")
                }
            }
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                ForEach(Array(sentences.enumerated()), id: \.offset) { _, sentence in
                    HStack(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.s) {
                        Text("•").accessibilityHidden(true)
                        Text(sentence)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .accessibilityIdentifier("weather.today.narrative")
        }
        .weatherSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weather.today")
    }

    @ViewBuilder
    private var icon: some View {
        if let hazard = briefing?.hazard {
            Image(systemName: WeatherSymbols.hazard(hazard))
                .font(.title)
                .foregroundStyle(severityColor)
                .accessibilityHidden(true)
        } else {
            WeatherGlyph(condition: briefing?.condition ?? current.drawnCondition, night: night, size: 32)
        }
    }

    private var severityColor: Color {
        switch briefing?.severity ?? .calm {
        case .alert: Color(red: 1.0, green: 0.60, blue: 0.24)
        case .caution: Color(red: 1.0, green: 0.82, blue: 0.30)
        case .notable, .calm: HassTokens.Ink.onDark
        }
    }
}
