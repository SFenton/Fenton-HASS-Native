import HassCore
import SwiftUI

extension EnvironmentValues {
    /// The shared forecast store. When unset (the real app), the Home card creates one from the app's connection;
    /// the gallery and tests inject a fixture store.
    @Entry var weatherForecastStore: WeatherForecastStore?
    /// Overrides the connection that answers `weather.get_forecasts` (the gallery's fixture service).
    @Entry var weatherForecastCaller: (any WeatherForecastCalling)?
    /// The Home card sits in half of a split window (the unfolded Duo's leading column), so its hourly row holds the
    /// compact number of hours per page even in regular width.
    @Entry var weatherCardIsNarrow = false
}
