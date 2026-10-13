import Foundation

/// How alarming a briefing's lead hazard is.
public enum WeatherBriefingSeverity: String, Codable, Sendable {
    case alert, caution, notable, calm

    var rank: Int {
        switch self {
        case .alert: 3
        case .caution: 2
        case .notable: 1
        case .calm: 0
        }
    }
}

/// A weather hazard the Today headline can lead with.
public enum WeatherHazard: String, Codable, Sendable, CaseIterable {
    case damagingWind, denseFog, extremeCold, extremeHeat, freeze, hail, heat, heavyRain, heavySnow
    case highUv, ice, poorAir, severeStorms, snow, wind

    /// The hazard's headline copy key.
    public var headlineKey: String { "briefing.hazard.\(rawValue)" }

    var baseSeverity: WeatherBriefingSeverity {
        switch self {
        case .damagingWind, .extremeCold, .extremeHeat, .heavySnow, .ice, .severeStorms: .alert
        case .denseFog, .hail, .heavyRain, .poorAir, .snow: .caution
        case .freeze, .heat, .highUv, .wind: .notable
        }
    }

    /// Web MDI icon name.
    public var icon: String {
        switch self {
        case .damagingWind, .wind: "mdi:weather-windy"
        case .denseFog: "mdi:weather-fog"
        case .extremeCold: "mdi:snowflake-alert"
        case .extremeHeat: "mdi:thermometer-alert"
        case .freeze: "mdi:snowflake"
        case .hail: "mdi:weather-hail"
        case .heat: "mdi:thermometer-high"
        case .heavyRain: "mdi:weather-pouring"
        case .heavySnow: "mdi:weather-snowy-heavy"
        case .highUv: "mdi:weather-sunny-alert"
        case .ice: "mdi:car-traction-control"
        case .poorAir: "mdi:air-filter"
        case .severeStorms: "mdi:weather-lightning"
        case .snow: "mdi:weather-snowy"
        }
    }

    /// Severity first, then meteorological priority inside a band (lowest index first).
    static let priority: [WeatherHazard] = [
        .severeStorms, .ice, .heavySnow, .damagingWind, .extremeCold, .extremeHeat, .hail, .heavyRain,
        .snow, .poorAir, .denseFog, .wind, .heat, .freeze, .highUv,
    ]
}

/// A value inside a briefing sentence: literal text, a number, or another copy reference.
public enum WeatherBriefingValue: Codable, Hashable, Sendable {
    case text(String)
    case number(Double)
    case ref(WeatherBriefingRef)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { self = .text(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else { self = .ref(try container.decode(WeatherBriefingRef.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .ref(value): try container.encode(value)
        }
    }
}

/// A copy key plus the values to fill it with; rendered to text by ``WeatherBriefingRenderer``.
public struct WeatherBriefingRef: Codable, Hashable, Sendable {
    public var key: String
    public var values: [String: WeatherBriefingValue]

    public init(_ key: String, _ values: [String: WeatherBriefingValue] = [:]) {
        self.key = key
        self.values = values
    }
}

/// The frozen "Today" briefing: a headline, an icon and a few narrative sentences.
public struct WeatherDayBriefing: Codable, Hashable, Sendable {
    public var condition: String?
    /// Local calendar day, `2026-01-15`.
    public var dateKey: String
    public var generatedAt: Date
    public var hazard: WeatherHazard?
    public var headline: WeatherBriefingRef?
    /// Literal headline for a provider condition the copy deck lacks.
    public var headlineText: String?
    /// Web MDI icon name.
    public var icon: String
    public var sentences: [WeatherBriefingRef]
    public var severity: WeatherBriefingSeverity
    public var version: Int
}

/// Everything the briefing generator reads.
public struct WeatherDayBriefingInput: Sendable {
    public var aqi: Double?
    public var daily: [WeatherForecast]
    public var generatedAt: Date
    public var hourly: [WeatherForecast]
    public var precipitationUnit: String?
    public var sunrise: String?
    public var sunset: String?
    public var temperatureUnit: String?
    public var timeZone: TimeZone
    public var windSpeedUnit: String?

    public init(
        aqi: Double? = nil, daily: [WeatherForecast] = [], generatedAt: Date, hourly: [WeatherForecast] = [],
        precipitationUnit: String? = nil, sunrise: String? = nil, sunset: String? = nil, temperatureUnit: String? = nil,
        timeZone: TimeZone = .current, windSpeedUnit: String? = nil
    ) {
        self.aqi = aqi
        self.daily = daily
        self.generatedAt = generatedAt
        self.hourly = hourly
        self.precipitationUnit = precipitationUnit
        self.sunrise = sunrise
        self.sunset = sunset
        self.temperatureUnit = temperatureUnit
        self.timeZone = timeZone
        self.windSpeedUnit = windSpeedUnit
    }
}

/// Turns a briefing into text with the weather copy deck.
public enum WeatherBriefingRenderer {
    /// Renders one reference, resolving nested references first.
    public static func render(_ ref: WeatherBriefingRef) -> String {
        var values: [String: String] = [:]
        for (name, value) in ref.values {
            switch value {
            case let .text(text): values[name] = text
            case let .number(number): values[name] = number == number.rounded() ? String(Int(number)) : String(number)
            case let .ref(nested): values[name] = render(nested)
            }
        }
        return WeatherCopy.text(ref.key, values)
    }

    /// All sentences joined by a space.
    public static func text(_ briefing: WeatherDayBriefing) -> String {
        briefing.sentences.map(render).joined(separator: " ")
    }

    /// The headline: a hazard or condition label.
    public static func headline(_ briefing: WeatherDayBriefing) -> String {
        if let headline = briefing.headline { return render(headline) }
        return briefing.headlineText ?? ""
    }
}

/// Decides when the day's briefing is written. Home Assistant stays the source: the briefing is frozen once per
/// local day, at or after 00:01, and never rewritten that day; the first one ever is written at once.
/// Source: `ha-sfenton-react-dash@f5a7bf9:src/components/hass/useWeatherDayBriefing.ts:106`.
public enum WeatherBriefingPlanner {
    /// The earliest minute of the day a new briefing is written.
    public static let generationMinute = 1

    /// Whether a new briefing should be generated now.
    public static func shouldGenerate(
        current: WeatherDayBriefing?, now: Date, timeZone: TimeZone, hourly: [WeatherForecast], daily: [WeatherForecast]
    ) -> Bool {
        let dateKey = WeatherDates.dateKey(now, in: timeZone)
        if let current, current.dateKey == dateKey { return false }
        if current != nil {
            let parts = WeatherDates.parts(now, in: timeZone)
            if parts.hour * 60 + parts.minute < generationMinute { return false }
        }
        return covers(hourly, dateKey: dateKey, timeZone: timeZone) || covers(daily, dateKey: dateKey, timeZone: timeZone)
    }

    private static func covers(_ forecasts: [WeatherForecast], dateKey: String, timeZone: TimeZone) -> Bool {
        forecasts.contains { forecast in
            guard let start = forecast.start else { return false }
            return WeatherDates.dateKey(start, in: timeZone) == dateKey
        }
    }
}
