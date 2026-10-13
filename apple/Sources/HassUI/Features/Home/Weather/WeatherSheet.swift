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
