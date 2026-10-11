import Foundation
@testable import HassCore
import Testing

@MainActor
struct EntityStoreTests {
    @Test func boxesAreStableAndOnlyChangedEntitiesPublish() {
        let store = EntityStore()
        let kitchen = store.entity("light.kitchen")
        let office = store.entity("light.office_light")
        store.replaceAll([
            EntityState(entityId: "light.kitchen", state: "on"),
            EntityState(entityId: "light.office_light", state: "off"),
        ])
        #expect(store.publishedChangeCount == 2)

        // A reconnect delivers the full set again with one change.
        store.replaceAll([
            EntityState(entityId: "light.kitchen", state: "on"),
            EntityState(entityId: "light.office_light", state: "on"),
        ])
        #expect(store.publishedChangeCount == 3)
        #expect(store.entity("light.kitchen") === kitchen)
        #expect(store.entity("light.office_light") === office)
        #expect(office.state?.state == "on")
    }

    @Test func removedEntitiesClearTheirBox() {
        let store = EntityStore()
        let box = store.entity("sensor.gone")
        store.replaceAll([EntityState(entityId: "sensor.gone", state: "1")])
        store.replaceAll([])
        #expect(box.state == nil)
    }

    @Test func freshnessMovesFromSnapshotToLive() {
        let store = EntityStore()
        let saved = Date(timeIntervalSince1970: 1_000)
        store.replaceAll([EntityState(entityId: "light.kitchen", state: "off")], freshness: .snapshot(savedAt: saved))
        #expect(store.freshness == .snapshot(savedAt: saved))
        store.replaceAll([EntityState(entityId: "light.kitchen", state: "off")])
        #expect(store.freshness == .live)
    }

    @Test func resetClearsEverything() {
        let store = EntityStore()
        let box = store.entity("light.kitchen")
        store.replaceAll([EntityState(entityId: "light.kitchen", state: "on")])
        store.reset()
        #expect(box.state == nil)
        #expect(store.freshness == .empty)
        #expect(store.allValues.isEmpty)
    }
}
