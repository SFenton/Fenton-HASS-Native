import Foundation
import HassCore
@testable import HassUI
import SwiftUI
import Testing

@MainActor
struct HomeViewTests {
    @Test func weatherConditionsMapToNamesAndSymbols() {
        #expect(WeatherConditionInfo("partlycloudy").label == "Partly Cloudy")
        #expect(WeatherConditionInfo(nil).label == "Weather Unavailable")
        #expect(WeatherConditionInfo("rainy").label == "Rain")
        #expect(WeatherSymbols.condition("sunny") == "sun.max.fill")
        #expect(WeatherSymbols.condition(nil) == "cloud.fill")
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

@MainActor
struct LightGroupTileTests {
    /// Dimmable groups draw the brightness tile; on/off-only entities fall back to a power tile.
    @Test func rendersBothTileKinds() {
        let group = HomeConfig.lightGroups[0]
        let id = group.entityId ?? ""
        let states: [EntityState?] = [
            EntityState(entityId: id, state: "on", attributes: ["brightness": .number(128), "rgb_color": .array([.number(255), .number(160), .number(60)])]),
            EntityState(entityId: id, state: "off", attributes: ["supported_color_modes": .array([.string("onoff")])]),
            nil,
        ]
        for state in states {
            let tile = LightGroupTile(title: group.room, entityId: id, state: state) { _ in }.frame(width: 170)
            #expect(ImageRenderer(content: tile).cgImage != nil)
        }
    }
}
