import Foundation

/// The current-conditions attributes of the weather entity, plus the sun and air-quality inputs the sheet needs.
public struct WeatherCurrent: Equatable, Sendable {
    /// Home Assistant condition (`rainy`); `nil` while the entity is missing or unavailable.
    public var condition: String?
    public var temperature: Double?
    public var apparentTemperature: Double?
    public var temperatureUnit: String?
    public var humidity: Double?
    public var windSpeed: Double?
    public var windGustSpeed: Double?
    public var windSpeedUnit: String?
    public var windBearing: WeatherWindBearing?
    public var pressure: Double?
    public var pressureUnit: String?
    public var visibility: Double?
    public var visibilityUnit: String?
    public var precipitationUnit: String?

    public init(
        condition: String? = nil, temperature: Double? = nil, apparentTemperature: Double? = nil, temperatureUnit: String? = nil,
        humidity: Double? = nil, windSpeed: Double? = nil, windGustSpeed: Double? = nil, windSpeedUnit: String? = nil,
        windBearing: WeatherWindBearing? = nil, pressure: Double? = nil, pressureUnit: String? = nil,
        visibility: Double? = nil, visibilityUnit: String? = nil, precipitationUnit: String? = nil
    ) {
        self.condition = condition
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature
        self.temperatureUnit = temperatureUnit
        self.humidity = humidity
        self.windSpeed = windSpeed
        self.windGustSpeed = windGustSpeed
        self.windSpeedUnit = windSpeedUnit
        self.windBearing = windBearing
        self.pressure = pressure
        self.pressureUnit = pressureUnit
        self.visibility = visibility
        self.visibilityUnit = visibilityUnit
        self.precipitationUnit = precipitationUnit
    }

    /// Reads the weather entity's state and attributes. A missing entity gives an empty value.
    public init(entity: EntityState?) {
        guard let entity else { self.init(); return }
        let attributes = entity.attributes
        self.init(
            condition: entity.state.isEmpty ? nil : entity.state,
            temperature: attributes["temperature"]?.lenientNumber,
            apparentTemperature: attributes["apparent_temperature"]?.lenientNumber,
            temperatureUnit: attributes["temperature_unit"]?.string,
            humidity: attributes["humidity"]?.lenientNumber,
            windSpeed: attributes["wind_speed"]?.lenientNumber,
            windGustSpeed: attributes["wind_gust_speed"]?.lenientNumber,
            windSpeedUnit: attributes["wind_speed_unit"]?.string,
            windBearing: WeatherWindBearing(json: attributes["wind_bearing"]),
            pressure: attributes["pressure"]?.lenientNumber,
            pressureUnit: attributes["pressure_unit"]?.string,
            visibility: attributes["visibility"]?.lenientNumber,
            visibilityUnit: attributes["visibility_unit"]?.string,
            precipitationUnit: attributes["precipitation_unit"]?.string
        )
    }

    /// `72°F` for the card's accessible name and the sheet subtitle, `--` when unknown.
    public var temperatureText: String { WeatherFormat.temperature(temperature, unit: temperatureUnit) }

    /// `72°` for the big number.
    public var degreeText: String { WeatherFormat.degree(temperature) }

    /// The condition label (`Partly Cloudy`), `Weather Unavailable` when unknown.
    public var conditionLabel: String { WeatherConditionInfo(isUnavailableState ? nil : condition).label }

    /// Home Assistant reports `unavailable` / `unknown` for a weather entity that lost its provider.
    var isUnavailableState: Bool { condition == "unavailable" || condition == "unknown" }

    /// The condition to draw; `nil` when unavailable.
    public var drawnCondition: String? { isUnavailableState ? nil : condition }
}

/// The `sun.sun` entity's fields the sheet reads.
public struct WeatherSunInput: Equatable, Sendable {
    public var state: String?
    public var nextRising: String?
    public var nextSetting: String?

    public init(state: String?, nextRising: String?, nextSetting: String?) {
        self.state = state
        self.nextRising = nextRising
        self.nextSetting = nextSetting
    }

    /// Reads a `sun.sun` entity; `nil` when the entity is missing.
    public init?(entity: EntityState?) {
        guard let entity else { return nil }
        self.init(state: entity.state, nextRising: entity.attributes["next_rising"]?.string, nextSetting: entity.attributes["next_setting"]?.string)
    }

    /// `below_horizon` means night.
    public var isNight: Bool { state == "below_horizon" }
}
