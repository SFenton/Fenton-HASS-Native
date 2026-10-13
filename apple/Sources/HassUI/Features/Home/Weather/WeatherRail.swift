import HassCore
import HassDesign
import SwiftUI

/// A horizontal gauge: a track, an optional coloured span and an optional marker (web `WeatherRail`).
///
/// Decorative: the value it draws is always spoken by the row or tile that holds it. Changes animate unless Reduce
/// Motion is on (web: `WEATHER_DATA_TRANSITION_MS`). HIG: Progress indicators, Gauges.
struct WeatherRail: View {
    /// What the rail measures; picks the colours.
    enum Tone {
        case aqi, feels, precipitation, temperature, uv, visibility

        /// Gradient stops across the full track.
        var colors: [Color] {
            switch self {
            case .temperature: [Color(red: 0.36, green: 0.80, blue: 1.0), Color(red: 1.0, green: 0.85, blue: 0.30), Color(red: 1.0, green: 0.55, blue: 0.20)]
            case .feels: [Color(red: 0.36, green: 0.80, blue: 1.0), Color(red: 0.85, green: 0.88, blue: 0.92), Color(red: 1.0, green: 0.55, blue: 0.20)]
            case .precipitation: [Color(red: 0.35, green: 0.70, blue: 1.0), Color(red: 0.35, green: 0.70, blue: 1.0)]
            case .visibility: [Color(red: 0.75, green: 0.80, blue: 0.86), Color.white]
            case .uv: [Color(red: 0.30, green: 0.85, blue: 0.45), Color(red: 1.0, green: 0.85, blue: 0.25), Color(red: 1.0, green: 0.55, blue: 0.20), Color(red: 0.95, green: 0.30, blue: 0.30), Color(red: 0.70, green: 0.40, blue: 0.95)]
            case .aqi: [Color(red: 0.30, green: 0.85, blue: 0.45), Color(red: 1.0, green: 0.85, blue: 0.25), Color(red: 1.0, green: 0.55, blue: 0.20), Color(red: 0.95, green: 0.30, blue: 0.30), Color(red: 0.70, green: 0.40, blue: 0.95), Color(red: 0.65, green: 0.20, blue: 0.30)]
            }
        }

        /// Scale tones colour the whole track; range tones colour only the span.
        var isScale: Bool { self == .aqi || self == .feels || self == .uv }
    }

    var tone: Tone
    var range: WeatherRailRange
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A rail for a range (temperature, precipitation, visibility) or a scale with a marker (AQI, UV, feels like).
    init(tone: Tone, range: WeatherRailRange = WeatherRailRange()) {
        self.tone = tone
        self.range = range
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let start = clamp(tone.isScale ? 0 : range.rangeStartPercent ?? 0)
            let size = tone.isScale ? 100 : min(clamp(range.rangeSizePercent ?? 0), 100 - start)
            ZStack(alignment: .leading) {
                Capsule().fill(HassTokens.Ink.onDark.opacity(0.22))
                Capsule()
                    .fill(LinearGradient(colors: tone.colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: width * size / 100)
                    .offset(x: width * start / 100)
                    .opacity(size > 0 ? 1 : 0)
                if let marker = range.markerPercent, marker.isFinite {
                    Circle()
                        .fill(HassTokens.Ink.onDark)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: 1.5))
                        .frame(width: 12, height: 12)
                        .offset(x: max(0, min(width - 12, width * clamp(marker) / 100 - 6)))
                }
            }
            .frame(maxHeight: .infinity)
            .animation(reduceMotion ? nil : .smooth(duration: 0.39), value: range)
        }
        .frame(height: 12)
        .frame(minWidth: 48)
        .accessibilityHidden(true)
    }

    private func clamp(_ value: Double) -> Double { min(100, max(0, value.isFinite ? value : 0)) }
}
