import Foundation

/// The entities the weather card and sheet read.
/// Source: `ha-sfenton-react-dash@f5a7bf9:src/constants/atAGlance.ts:766`.
public enum WeatherEntities {
    /// `weather.pirate_weather`: current conditions and the forecast source.
    public static let weather = HomeConfig.weatherEntityId
    /// `sensor.pirate_weather_air_quality_index`: US AQI.
    public static let airQuality = "sensor.pirate_weather_air_quality_index"
    /// `sun.sun`: next sunrise and sunset, and whether it is night.
    public static let sun = "sun.sun"
}

public extension WeatherForecastStore {
    /// A value that changes when the weather entity updates, standing in for the web's `last_updated`:
    /// the entity's state and attributes change whenever the provider publishes new data.
    nonisolated static func revision(of entity: EntityState?) -> String? {
        entity.map { String($0.hashValue) }
    }
}
