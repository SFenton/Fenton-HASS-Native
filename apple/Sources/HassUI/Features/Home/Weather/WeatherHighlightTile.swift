import HassCore
import HassDesign
import SwiftUI

/// Feels like, UV, wind, sun, visibility and pressure (web `HighlightTile`).
struct WeatherHighlightTile: View {
    var tile: WeatherHighlight
    var sun: WeatherSunInput?

    var body: some View {
        if tile.kind == .wind, let wind = tile.wind {
            WeatherWindTile(tile: tile, wind: wind)
        } else {
            WeatherTile(
                title: tile.title, symbol: WeatherSymbols.highlight(tile.kind, sun: sunEvent), label: tile.accessibilityLabel,
                identifier: "weather.highlight.\(tile.kind.rawValue)", value: nil
            ) {
                content
            }
        }
    }

    private var sunEvent: WeatherPresentation.SunEvent? {
        sun.flatMap { WeatherPresentation.sun(state: $0.state, nextRising: $0.nextRising, nextSetting: $0.nextSetting)?.primary }
    }

    @ViewBuilder
    private var content: some View {
        if !tile.available {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                Text(tile.value).font(.title2.weight(.bold))
                Image(systemName: WeatherSymbols.highlight(tile.kind))
                    .font(.title)
                    .foregroundStyle(HassTokens.Ink.onDark.opacity(0.35))
            }
        } else if tile.kind == .pressure {
            let parts = tile.value.split(separator: " ", maxSplits: 1).map(String.init)
            WeatherPressureGauge(percent: tile.percent ?? 50, value: parts.first ?? tile.value, unit: parts.count > 1 ? parts[1] : nil)
        } else {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                HStack(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.s) {
                    Text(tile.value).font(.title2.weight(.bold)).monospacedDigit()
                    if let status = tile.status {
                        Text(status).font(.footnote).foregroundStyle(HassTokens.Ink.onDarkSecondary)
                    }
                }
                visual
            }
        }
    }

    @ViewBuilder
    private var visual: some View {
        switch tile.kind {
        case .feels: WeatherRail(tone: .feels, range: WeatherRailRange(markerPercent: tile.percent))
        case .uv: WeatherRail(tone: .uv, range: WeatherRailRange(markerPercent: tile.percent))
        case .visibility:
            WeatherRail(tone: .visibility, range: WeatherRailRange(
                markerPercent: (tile.percent ?? 0) > 0 ? tile.percent : nil, rangeSizePercent: tile.percent, rangeStartPercent: 0
            ))
        case .sun: WeatherSunArc(percent: tile.percent)
        default: EmptyView()
        }
    }
}
