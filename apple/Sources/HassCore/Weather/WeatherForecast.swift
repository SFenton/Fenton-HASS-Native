import Foundation

/// Which Home Assistant forecast a request asks for (`weather.get_forecasts` `type`).
public enum WeatherForecastKind: String, Codable, Sendable, CaseIterable {
    case daily
    case hourly

    /// How many entries the app keeps: seven days, or the next 24 hours (web `extractForecasts`).
    public var limit: Int { self == .daily ? 7 : 24 }
}

/// A wind direction as the weather integration reports it: degrees, or a compass abbreviation (`"WNW"`).
public enum WeatherWindBearing: Hashable, Sendable {
    case degrees(Double)
    case cardinal(String)

    /// Reads a bearing from a Home Assistant attribute; `nil` for anything else.
    public init?(json: JSONValue?) {
        switch json {
        case let .number(value) where value.isFinite: self = .degrees(value)
        case let .string(value) where !value.trimmingCharacters(in: .whitespaces).isEmpty: self = .cardinal(value)
        default: return nil
        }
    }

    var json: JSONValue {
        switch self {
        case let .degrees(value): .number(value)
        case let .cardinal(value): .string(value)
        }
    }
}

/// One daily or hourly forecast entry from `weather.get_forecasts`.
///
/// Fields mirror the web `WeatherForecast` interface; every field is optional because providers omit them.
/// Source: `ha-sfenton-react-dash@f5a7bf9:src/components/hass/useWeatherForecasts.ts:6`.
public struct WeatherForecast: Codable, Hashable, Sendable {
    public var apparentTemperature: Double?
    public var cloudCoverage: Double?
    public var condition: String?
    /// ISO 8601 start of the period, as Home Assistant sent it.
    public var datetime: String?
    public var dewPoint: Double?
    public var humidity: Double?
    public var precipitation: Double?
    public var precipitationProbability: Double?
    public var pressure: Double?
    public var temperature: Double?
    /// Daily low.
    public var templow: Double?
    public var uvIndex: Double?
    public var windBearing: WeatherWindBearing?
    public var windGustSpeed: Double?
    public var windSpeed: Double?

    /// Creates a forecast entry; tests and fixtures set only what they need.
    public init(
        datetime: String? = nil, condition: String? = nil, temperature: Double? = nil, templow: Double? = nil,
        apparentTemperature: Double? = nil, cloudCoverage: Double? = nil, dewPoint: Double? = nil, humidity: Double? = nil,
        precipitation: Double? = nil, precipitationProbability: Double? = nil, pressure: Double? = nil,
        uvIndex: Double? = nil, windBearing: WeatherWindBearing? = nil, windGustSpeed: Double? = nil, windSpeed: Double? = nil
    ) {
        self.datetime = datetime
        self.condition = condition
        self.temperature = temperature
        self.templow = templow
        self.apparentTemperature = apparentTemperature
        self.cloudCoverage = cloudCoverage
        self.dewPoint = dewPoint
        self.humidity = humidity
        self.precipitation = precipitation
        self.precipitationProbability = precipitationProbability
        self.pressure = pressure
        self.uvIndex = uvIndex
        self.windBearing = windBearing
        self.windGustSpeed = windGustSpeed
        self.windSpeed = windSpeed
    }

    /// Reads one forecast object; numbers may arrive as numeric strings (the web's `numberValue` accepts both).
    public init(json: [String: JSONValue]) {
        self.init(
            datetime: json["datetime"]?.string,
            condition: json["condition"]?.string,
            temperature: json["temperature"]?.lenientNumber,
            templow: json["templow"]?.lenientNumber,
            apparentTemperature: json["apparent_temperature"]?.lenientNumber,
            cloudCoverage: json["cloud_coverage"]?.lenientNumber,
            dewPoint: json["dew_point"]?.lenientNumber,
            humidity: json["humidity"]?.lenientNumber,
            precipitation: json["precipitation"]?.lenientNumber,
            precipitationProbability: json["precipitation_probability"]?.lenientNumber,
            pressure: json["pressure"]?.lenientNumber,
            uvIndex: json["uv_index"]?.lenientNumber,
            windBearing: WeatherWindBearing(json: json["wind_bearing"]),
            windGustSpeed: json["wind_gust_speed"]?.lenientNumber,
            windSpeed: json["wind_speed"]?.lenientNumber
        )
    }

    public init(from decoder: Decoder) throws {
        let object = try decoder.singleValueContainer().decode([String: JSONValue].self)
        self.init(json: object)
    }

    public func encode(to encoder: Encoder) throws {
        var object: [String: JSONValue] = [:]
        func put(_ key: String, _ value: Double?) { if let value { object[key] = .number(value) } }
        if let datetime { object["datetime"] = .string(datetime) }
        if let condition { object["condition"] = .string(condition) }
        put("temperature", temperature)
        put("templow", templow)
        put("apparent_temperature", apparentTemperature)
        put("cloud_coverage", cloudCoverage)
        put("dew_point", dewPoint)
        put("humidity", humidity)
        put("precipitation", precipitation)
        put("precipitation_probability", precipitationProbability)
        put("pressure", pressure)
        put("uv_index", uvIndex)
        put("wind_gust_speed", windGustSpeed)
        put("wind_speed", windSpeed)
        if let windBearing { object["wind_bearing"] = windBearing.json }
        var container = encoder.singleValueContainer()
        try container.encode(object)
    }

    /// The start of the period, parsed from ``datetime``.
    public var start: Date? { datetime.flatMap(WeatherDates.parse) }
}

extension JSONValue {
    /// A number, or a string holding one (`numberValue` in the web code); `nil` otherwise.
    var lenientNumber: Double? {
        switch self {
        case let .number(value): value.isFinite ? value : nil
        case let .string(value):
            Double(value.trimmingCharacters(in: .whitespaces)).flatMap { $0.isFinite ? $0 : nil }
        default: nil
        }
    }
}

/// Why a forecast response could not be used.
public struct WeatherForecastError: Error, Equatable, LocalizedError, Sendable {
    /// The user-facing message (`forecast.dailyError` / `forecast.hourlyError`).
    public var message: String
    public var errorDescription: String? { message }

    /// The malformed-response error for a forecast kind.
    public static func malformed(_ kind: WeatherForecastKind) -> WeatherForecastError {
        WeatherForecastError(message: WeatherCopy.forecastFailure(kind))
    }

    /// The websocket dropped or was not ready; the store retries quietly instead of showing an error.
    public static let connectionLost = WeatherForecastError(message: "Connection lost")
}

public extension WeatherForecast {
    /// Extracts the forecast list from a `weather.get_forecasts` response.
    ///
    /// Accepts the `response` object Home Assistant returns (`{"weather.x": {"forecast": [...]}}`), optionally
    /// wrapped in `service_response`. Daily entries are cut to 7 and hourly to 24; non-object entries are dropped.
    /// Source: `ha-sfenton-react-dash@f5a7bf9:src/components/hass/useWeatherForecasts.ts:98`.
    /// - Throws: ``WeatherForecastError`` when the envelope is not shaped as expected, so a bad reply is never
    ///   published as an empty success.
    static func extract(from response: JSONValue, entityId: String, kind: WeatherForecastKind) throws -> [WeatherForecast] {
        guard case let .object(root) = response else { throw WeatherForecastError.malformed(kind) }
        let payload: JSONValue = {
            if let wrapped = root["service_response"], wrapped != .null { return wrapped }
            return response
        }()
        guard case let .object(entities) = payload,
              case let .object(entity)? = entities[entityId],
              case let .array(entries)? = entity["forecast"] else { throw WeatherForecastError.malformed(kind) }
        return entries.compactMap { entry -> WeatherForecast? in
            guard case let .object(object) = entry else { return nil }
            return WeatherForecast(json: object)
        }
        .prefix(kind.limit)
        .map { $0 }
    }
}
