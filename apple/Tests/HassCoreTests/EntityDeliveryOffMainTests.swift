import Foundation
@preconcurrency import HAKit
@preconcurrency import HAKit_Mocks
@testable import HassCore
import Testing

/// HAKit's callbacks and the entity diff run off the main thread; only the changed entities are applied on it
/// (`.agents/testing/apple/performance.md`, "Scroll cost": the diff of thousands of entities took over half of the main
/// thread's CPU time).
@MainActor
struct EntityDeliveryOffMainTests {
    private func make() -> (HassConnection, EntityStore, HAMockConnection) {
        let mock = HAMockConnection()
        let store = EntityStore()
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "offmain-\(UUID()).json"))
        return (HassConnection(server: .fentonHome, store: store, snapshotCache: cache, connection: mock), store, mock)
    }

    private func entity(_ id: String, _ state: String, updated: TimeInterval) throws -> HAEntity {
        try HAEntity(entityId: id, state: state, lastChanged: Date(timeIntervalSince1970: updated),
                     lastUpdated: Date(timeIntervalSince1970: updated), attributes: [:],
                     context: .init(id: "c", userId: nil, parentId: nil))
    }

    /// Waits (suspending the main actor, so the connection's main-queue hops can run) until `condition` holds.
    private func settle(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func hakitCallsBackOffTheMainQueue() {
        let (_, _, mock) = make()
        #expect(mock.callbackQueue !== DispatchQueue.main)
    }

    @Test func aDeliveryFromAnotherQueueReachesTheStore() async throws {
        let (connection, store, _) = make()
        let first: Set<HAEntity> = [try entity("light.a", "on", updated: 1), try entity("light.b", "off", updated: 1), try entity("sensor.c", "3", updated: 1)]
        let second: Set<HAEntity> = [try entity("light.a", "on", updated: 1), try entity("light.b", "on", updated: 2)]
        let background = DispatchQueue(label: "test.delivery")
        nonisolated(unsafe) let firstDelivery = HassConnection.Delivery(entities: first)
        nonisolated(unsafe) let secondDelivery = HassConnection.Delivery(entities: second)
        background.async {
            connection.process(firstDelivery)
            connection.process(secondDelivery)
        }
        let boxA = store.entity("light.a")
        await settle { store.entity("sensor.c").state == nil && store.entity("light.b").state?.state == "on" }
        #expect(boxA.state?.state == "on")
        #expect(store.entity("light.b").state?.state == "on")
        // The entity the second delivery no longer has is gone, in order after the first delivery added it.
        #expect(store.entity("sensor.c").state == nil)
        #expect(store.freshness == .live)
    }

    @Test func deliveriesApplyInTheOrderTheyArrived() async throws {
        let (connection, store, _) = make()
        let background = DispatchQueue(label: "test.delivery.order")
        nonisolated(unsafe) var deliveries: [HassConnection.Delivery] = []
        for step in 1...20 { deliveries.append(HassConnection.Delivery(entities: [try entity("sensor.n", "\(step)", updated: Double(step))])) }
        nonisolated(unsafe) let queued = deliveries
        background.async { for delivery in queued { connection.process(delivery) } }
        await settle { store.entity("sensor.n").state?.state == "20" }
        #expect(store.entity("sensor.n").state?.state == "20")
    }

    @Test func aBurstOfDeliveriesLeavesTheNewestState() async throws {
        let (connection, store, mock) = make()
        nonisolated(unsafe) var deliveries: [HassConnection.Delivery] = []
        for step in 1...50 { deliveries.append(HassConnection.Delivery(entities: [try entity("sensor.burst", "\(step)", updated: Double(step))])) }
        nonisolated(unsafe) let burst = deliveries
        // HAKit calls the handler on its callback queue, one delivery after another.
        mock.callbackQueue.async { for delivery in burst { connection.receive(delivery) } }
        await settle { store.entity("sensor.burst").state?.state == "50" }
        #expect(store.entity("sensor.burst").state?.state == "50")
    }
}
