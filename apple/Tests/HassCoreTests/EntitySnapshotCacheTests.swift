import Foundation
@testable import HassCore
import Testing

struct EntitySnapshotCacheTests {
    private func makeCache() -> EntitySnapshotCache {
        EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "snapshot-\(UUID()).json"))
    }

    @Test func roundTripsStatesForTheSameServer() throws {
        let cache = makeCache()
        let state = EntityState(
            entityId: "weather.pirate_weather",
            state: "sunny",
            attributes: ["temperature": .number(71), "friendly_name": .string("Pirate Weather"), "flag": .bool(true)],
            lastChanged: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try cache.save([state], server: .fentonHome, at: Date(timeIntervalSince1970: 5))
        let snapshot = try #require(cache.load(for: .fentonHome))
        #expect(snapshot.entities == [state])
        #expect(snapshot.savedAt == Date(timeIntervalSince1970: 5))
        cache.clear()
    }

    @Test func ignoresSnapshotFromAnotherServer() throws {
        let cache = makeCache()
        try cache.save([EntityState(entityId: "light.a", state: "on")], server: .fentonHome)
        #expect(cache.load(for: HassServer(baseURL: URL(string: "https://other.example")!)) == nil)
        cache.clear()
    }
}
