import HassCore
import SwiftUI

/// SF Symbols for weather conditions, hazards and highlight tiles.
///
/// The web draws custom SVG glyphs; native uses SF Symbols in multicolor rendering (HIG: SF Symbols, Weather data).
/// A hosted test checks that every name exists in the system symbol set.
enum WeatherSymbols {
    /// The symbol for a Home Assistant condition. `night` swaps the sun for the moon (current conditions only).
    static func condition(_ condition: String?, night: Bool = false) -> String {
        switch condition ?? "" {
        case "sunny": night ? "moon.stars.fill" : "sun.max.fill"
        case "clear-night": "moon.stars.fill"
        case "partlycloudy": night ? "cloud.moon.fill" : "cloud.sun.fill"
        case "cloudy": "cloud.fill"
        case "rainy": night ? "cloud.moon.rain.fill" : "cloud.rain.fill"
        case "pouring": "cloud.heavyrain.fill"
        case "snowy": "cloud.snow.fill"
        case "snowy-rainy": "cloud.sleet.fill"
        case "lightning": "cloud.bolt.fill"
        case "lightning-rainy": "cloud.bolt.rain.fill"
        case "fog": "cloud.fog.fill"
        case "hail": "cloud.hail.fill"
        case "windy": "wind"
        case "windy-variant": "smoke.fill"
        case "exceptional": "exclamationmark.triangle.fill"
        default: "cloud.fill"
        }
    }

    /// The symbol for a briefing hazard.
    static func hazard(_ hazard: WeatherHazard) -> String {
        switch hazard {
        case .damagingWind, .wind: "wind"
        case .denseFog: "cloud.fog.fill"
        case .extremeCold: "thermometer.snowflake"
        case .extremeHeat: "thermometer.sun.fill"
        case .freeze: "snowflake"
        case .hail: "cloud.hail.fill"
        case .heat: "thermometer.high"
        case .heavyRain: "cloud.heavyrain.fill"
        case .heavySnow, .snow: "cloud.snow.fill"
        case .highUv: "sun.max.trianglebadge.exclamationmark.fill"
        case .ice: "snowflake.circle.fill"
        case .poorAir: "aqi.medium"
        case .severeStorms: "cloud.bolt.fill"
        }
    }

    /// The symbol for a highlight tile.
    static func highlight(_ kind: WeatherHighlight.Kind, sun: WeatherPresentation.SunEvent? = nil) -> String {
        switch kind {
        case .aqi: "aqi.medium"
        case .feels: "thermometer.medium"
        case .uv: "sun.max.fill"
        case .wind: "wind"
        case .sun: sun == .sunrise ? "sunrise.fill" : "sunset.fill"
        case .visibility: "eye.fill"
        case .pressure: "gauge.with.dots.needle.33percent"
        }
    }

    static let precipitation = "cloud.rain.fill"
    static let humidity = "humidity.fill"
    static let cloudCover = "cloud.fill"
    static let drop = "drop.fill"
    static let windArrow = "location.north.fill"
    static let windFlag = "wind"
    static let previous = "chevron.left"
    static let next = "chevron.right"
    static let disclosure = "chevron.right"

    /// The three hourly detail modes' toggle icons (web `WEATHER_HOURLY_MODES`).
    static func mode(_ mode: WeatherHourlyMode) -> String {
        switch mode {
        case .condition: "cloud.fill"
        case .precipitation: "drop.fill"
        case .wind: "wind"
        }
    }

    /// Every name this file can return, for the hosted existence test.
    static var allNames: [String] {
        let conditions = ["sunny", "clear-night", "partlycloudy", "cloudy", "rainy", "pouring", "snowy", "snowy-rainy", "lightning",
                          "lightning-rainy", "fog", "hail", "windy", "windy-variant", "exceptional", "unknown"]
        var names = conditions.flatMap { [condition($0), condition($0, night: true)] }
        names += WeatherHazard.allCases.map(hazard)
        names += WeatherHighlight.Kind.allCases.map { highlight($0) }
        names += [highlight(.sun, sun: .sunrise), precipitation, humidity, cloudCover, drop, windArrow, windFlag, previous, next]
        names += WeatherHourlyMode.allCases.map(mode)
        return Array(Set(names)).sorted()
    }
}
