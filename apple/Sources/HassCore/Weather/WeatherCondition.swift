import Foundation

/// A Home Assistant weather condition's label and web icon.
/// Source: `ha-sfenton-react-dash@f5a7bf9:src/components/hass/weatherPresentation.ts:200`.
public struct WeatherConditionInfo: Equatable, Sendable {
    /// Web MDI icon name.
    public var icon: String
    /// Display label.
    public var label: String

    /// Info for a condition string. A missing condition reads as unavailable; an unknown one is title-cased
    /// (`heavy-snow` becomes `Heavy Snow`) because providers emit conditions Home Assistant has not standardised.
    public init(_ condition: String?) {
        guard let condition, !condition.isEmpty else {
            icon = "mdi:alert-circle"
            label = WeatherCopy.text("condition.unavailable")
            return
        }
        if let icon = Self.icons[condition] {
            self.icon = icon
            label = WeatherCopy.text("condition.\(condition)")
        } else {
            icon = "mdi:cloud"
            label = condition.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
                .split(separator: " ", omittingEmptySubsequences: false)
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    /// Whether Home Assistant standardises this condition.
    public static func isKnown(_ condition: String?) -> Bool { condition.map { icons[$0] != nil } ?? false }

    static let icons: [String: String] = [
        "clear-night": "mdi:weather-night", "cloudy": "mdi:cloud", "exceptional": "mdi:alert-circle",
        "fog": "mdi:weather-fog", "hail": "mdi:weather-hail", "lightning": "mdi:weather-lightning",
        "lightning-rainy": "mdi:weather-lightning-rainy", "partlycloudy": "mdi:weather-partly-cloudy",
        "pouring": "mdi:weather-pouring", "rainy": "mdi:weather-rainy", "snowy": "mdi:weather-snowy",
        "snowy-rainy": "mdi:weather-snowy-rainy", "sunny": "mdi:weather-sunny", "windy": "mdi:weather-windy",
        "windy-variant": "mdi:weather-windy-variant",
    ]
}

/// The atmosphere behind the weather sheet (web `WeatherScene`).
public enum WeatherScene: String, Sendable, CaseIterable {
    case sunny, night, clouds, fog, rain, storm, snow, wind, exceptional, neutral

    /// Maps a condition to its scene; `isNight` turns a sunny sky into the night scene (`weatherSceneForCondition`).
    public init(condition: String?, isNight: Bool = false) {
        switch condition {
        case "clear-night": self = .night
        case "sunny": self = isNight ? .night : .sunny
        case "partlycloudy", "cloudy": self = .clouds
        case "fog": self = .fog
        case "rainy", "pouring": self = .rain
        case "lightning", "lightning-rainy", "hail": self = .storm
        case "snowy", "snowy-rainy": self = .snow
        case "windy", "windy-variant": self = .wind
        case "exceptional": self = .exceptional
        default: self = .neutral
        }
    }
}
