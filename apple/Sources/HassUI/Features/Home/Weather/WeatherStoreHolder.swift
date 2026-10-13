import HassCore
import SwiftUI

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
