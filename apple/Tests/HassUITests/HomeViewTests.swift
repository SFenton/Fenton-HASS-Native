import Foundation
import HassCore
@testable import HassUI
import SwiftUI
import Testing

@MainActor
struct HomeViewTests {
    @Test func weatherConditionsMapToNamesAndSymbols() {
        #expect(WeatherSummaryCard.conditionName("partlycloudy") == "Partly Cloudy")
        #expect(WeatherSummaryCard.conditionName(nil) == "Unavailable")
        #expect(WeatherSummaryCard.conditionName("rainy") == "Rainy")
        #expect(WeatherSummaryCard.symbol(for: "sunny") == "sun.max.fill")
        #expect(WeatherSummaryCard.symbol(for: nil) == "cloud.fill")
    }

    @Test func homeSheetIdsAreUnique() {
        let ids = HomeConfig.ChipSheet.allCases.map { HomeSheet.chip($0).id } + HomeConfig.cameras.map { HomeSheet.camera($0).id }
        #expect(Set(ids).count == ids.count)
    }

    /// Hosted render of Home from a snapshot-only store: every section draws without a live connection.
    @Test func homeRendersFromSnapshot() throws {
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "home-\(UUID()).json"))
        try cache.save([
            EntityState(entityId: "light.lights", state: "on"),
            EntityState(entityId: "light.kitchen", state: "on"),
            EntityState(entityId: "weather.pirate_weather", state: "sunny", attributes: ["temperature": .number(70)]),
            EntityState(entityId: "input_boolean.guests_staying_in_guest_room", state: "on"),
        ], server: .fentonHome)
        let store = EntityStore()
        let connection = HassConnection(server: .fentonHome, tokens: TokenManager(store: InMemoryTokenStore()), store: store, snapshotCache: cache)
        #expect(store.value("light.kitchen")?.state == "on")
        if case .snapshot = store.freshness {} else { Issue.record("expected snapshot freshness") }

        let view = NavigationStack { HomeScreen() }
            .environment(connection)
            .environment(store)
            .frame(width: 402, height: 874)
        let renderer = ImageRenderer(content: view)
        #expect(renderer.cgImage != nil)
        cache.clear()
    }
}
