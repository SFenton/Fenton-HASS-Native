import HassCore
import SwiftUI

extension EnvironmentValues {
    /// The shared forecast store. When unset (the real app), the Home card creates one from the app's connection;
    /// the gallery and tests inject a fixture store.
    @Entry var weatherForecastStore: WeatherForecastStore?
    /// Overrides the connection that answers `weather.get_forecasts` (the gallery's fixture service).
    @Entry var weatherForecastCaller: (any WeatherForecastCalling)?
}

/// Creates the card's forecast store once per card, restoring the disk snapshot before the first frame.
@MainActor
final class WeatherStoreHolder {
    private var store: WeatherForecastStore?

    /// The store for the signed-in server, created on first use.
    func store(for server: HassServer?) -> WeatherForecastStore {
        if let store { return store }
        let created = WeatherForecastStore(server: server, cache: server == nil ? nil : WeatherForecastDiskCache())
        store = created
        return created
    }
}
