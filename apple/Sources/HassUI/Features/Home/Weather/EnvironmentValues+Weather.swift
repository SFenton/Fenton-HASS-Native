import HassCore
import SwiftUI

extension EnvironmentValues {
    /// The shared forecast store. When unset (the real app), the Home card creates one from the app's connection;
    /// the gallery and tests inject a fixture store.
    @Entry var weatherForecastStore: WeatherForecastStore?
    /// Overrides the connection that answers `weather.get_forecasts` (the gallery's fixture service).
    @Entry var weatherForecastCaller: (any WeatherForecastCalling)?
}
