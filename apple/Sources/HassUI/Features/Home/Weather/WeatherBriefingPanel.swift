import HassCore
import HassDesign
import SwiftUI

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
                        .font(.title3.bold())
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
