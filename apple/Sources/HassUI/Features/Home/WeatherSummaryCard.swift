#if os(iOS)
import HassCore
import HassDesign
import SwiftUI

/// Current conditions (web `WeatherSummary`, first pass: no forecast rail).
struct WeatherSummaryCard: View {
    @Environment(EntityStore.self) private var store

    var body: some View {
        let weather = store.entity(HomeConfig.weatherEntityId).state
        HStack(spacing: HassTokens.Spacing.l) {
            Image(systemName: Self.symbol(for: weather?.state))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 44))
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                Text(temperature(weather))
                    .font(.largeTitle.weight(.semibold))
                    .monospacedDigit()
                Text(Self.conditionName(weather?.state))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let humidity = weather?.attributes["humidity"]?.number {
                Label("\(Int(humidity))%", systemImage: "humidity")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(HassTokens.Spacing.l)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func temperature(_ weather: EntityState?) -> String {
        guard let value = weather?.attributes["temperature"]?.number else { return "--" }
        let unit = weather?.attributes["temperature_unit"]?.string ?? "°"
        return "\(Int(value.rounded()))\(unit.hasPrefix("°") ? "°" : unit)"
    }

    /// HA weather condition → SF Symbol.
    static func symbol(for condition: String?) -> String {
        switch condition ?? "" {
        case "sunny": "sun.max.fill"
        case "clear-night": "moon.stars.fill"
        case "partlycloudy": "cloud.sun.fill"
        case "cloudy": "cloud.fill"
        case "rainy": "cloud.rain.fill"
        case "pouring": "cloud.heavyrain.fill"
        case "snowy", "snowy-rainy": "cloud.snow.fill"
        case "lightning", "lightning-rainy": "cloud.bolt.rain.fill"
        case "fog": "cloud.fog.fill"
        case "windy", "windy-variant": "wind"
        case "hail": "cloud.hail.fill"
        default: "cloud.fill"
        }
    }

    /// HA weather condition → display name.
    static func conditionName(_ condition: String?) -> String {
        switch condition ?? "" {
        case "", "unavailable", "unknown": "Unavailable"
        case "partlycloudy": "Partly Cloudy"
        case "clear-night": "Clear"
        case "snowy-rainy": "Sleet"
        case "lightning-rainy": "Thunderstorms"
        case "windy-variant": "Windy"
        case let value: value.capitalized
        }
    }
}
#endif
