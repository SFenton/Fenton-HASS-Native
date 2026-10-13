import Foundation
import HAKit
@testable import HassCore
import Testing

/// ``OptimisticActions``: commit-then-call, rollback on failure, live confirmation and resets.
@MainActor
struct OptimisticActionsTests {
    private func make(_ states: [String: String], rules: [String: OptimisticOverlay.ClearRule])
        -> (OptimisticActions, EntityStore, RecordingCaller, ManualScheduler) {
        let store = makeStore(states)
        let caller = RecordingCaller()
        let scheduler = ManualScheduler()
        let actions = OptimisticActions(store: store, rules: rules, caller: caller, scheduler: scheduler)
        return (actions, store, caller, scheduler)
    }

    /// Lets the observation hop (`Task { @MainActor in ... }`) run.
    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    @Test func showsTheIntentAtOnceAndSendsTheCall() async {
        let (actions, _, caller, _) = make(["light.desk": "off"], rules: ["light.desk": .confirmation])
        let task = actions.perform(ServiceCall("light", "turn_on", target: "light.desk"), showing: [.init("light.desk", value: "on")])
        #expect(actions.shown("light.desk") == "on")
        #expect(actions.isPending("light.desk"))
        await task.value
        #expect(caller.calls == [.init(domain: "light", service: "turn_on", data: ["entity_id": "light.desk"])])
    }

    @Test func confirmationClearsQuietly() async {
        let (actions, store, _, _) = make(["light.desk": "off"], rules: ["light.desk": .confirmation])
        await actions.perform("light", "turn_on", data: ["entity_id": "light.desk"], showing: [.init("light.desk", value: "on")]).value
        store.apply([EntityState(entityId: "light.desk", state: "on")])
        await settle()
        #expect(actions.overlay.pending["light.desk"] == nil)
        #expect(actions.shown("light.desk") == "on")
    }

    @Test func liveChangeRuleClearsOnAnyChange() async {
        let (actions, store, _, _) = make(["light.desk": "off"], rules: ["light.desk": .liveChange])
        actions.perform("light", "turn_on", data: ["entity_id": "light.desk"], showing: [.init("light.desk", value: "on")])
        // Presence Based Lighting reverts the light: the tile follows the truth instead of holding "on".
        store.apply([EntityState(entityId: "light.desk", state: "unavailable")])
        await settle()
        #expect(actions.shown("light.desk") == "unavailable")
    }

    @Test func failureRollsBackWithoutWaitingForTheTimer() async {
        let (actions, _, caller, scheduler) = make(["switch.fan": "off"], rules: ["switch.fan": .confirmation])
        caller.failNext = true
        let task = actions.perform(ServiceCall("switch", "turn_on", target: "switch.fan"), showing: [.init("switch.fan", value: "on")])
        #expect(actions.shown("switch.fan") == "on")
        await task.value
        #expect(actions.shown("switch.fan") == "off")
        #expect(scheduler.pending.isEmpty)
    }

    @Test func anOlderFailureNeverUndoesANewerTap() async {
        let (actions, _, caller, _) = make(["select.mode": "a"], rules: ["select.mode": .confirmation])
        caller.failNext = true
        let first = actions.perform(ServiceCall("select", "select_option", target: "select.mode"), showing: [.init("select.mode", value: "b")])
        actions.perform(ServiceCall("select", "select_option", target: "select.mode"), showing: [.init("select.mode", value: "c")])
        await first.value
        await actions.waitForCalls()
        #expect(actions.shown("select.mode") == "c")
    }

    @Test func revertTimerGivesWayToLive() {
        let (actions, _, _, scheduler) = make(["switch.fan": "off"], rules: ["switch.fan": .confirmation])
        actions.perform(ServiceCall("switch", "turn_on", target: "switch.fan"), showing: [.init("switch.fan", value: "on")])
        #expect(scheduler.pending.first?.delay == OptimisticActions.defaultRevert)
        scheduler.fireAll()
        #expect(actions.shown("switch.fan") == "off")
    }

    @Test func resetsClearMatchingPendingValuesOnly() async {
        let (actions, _, _, _) = make(["media_player.tv": "idle", "select.source": "a"],
                                      rules: ["media_player.tv": .confirmation, "select.source": .confirmation])
        actions.perform(ServiceCall("media_player", "media_play", target: "media_player.tv"), showing: [.init("media_player.tv", value: "playing")])
        actions.perform(ServiceCall("select", "select_option", target: "select.source"), showing: [.init("select.source", value: "b")])
        actions.perform(ServiceCall("media_player", "media_stop", target: "media_player.tv"), showing: [],
                        resetting: [.init("media_player.tv", values: ["playing"]), .init("select.source", values: ["z"])])
        #expect(actions.shown("media_player.tv") == "idle")
        #expect(actions.shown("select.source") == "b")
        await actions.waitForCalls()
    }

    @Test func untrackedKeysAreSentButNotShown() async {
        let (actions, _, caller, _) = make(["light.desk": "off"], rules: [:])
        await actions.perform(ServiceCall("light", "turn_on", target: "light.desk"), showing: [.init("light.desk", value: "on")]).value
        #expect(actions.shown("light.desk") == "off")
        #expect(caller.calls.count == 1)
    }

    @Test func customLiveSourceTracksAttributes() async {
        let store = makeStore(["climate.hub": "heat"], attributes: ["climate.hub": ["fan_mode": .string("auto")]])
        let actions = OptimisticActions(rules: ["hub#fan": .confirmation], caller: RecordingCaller(), scheduler: ManualScheduler()) { key in
            key == "hub#fan" ? store.entity("climate.hub").state?.attributes["fan_mode"]?.string : nil
        }
        actions.perform(ServiceCall("climate", "set_fan_mode", target: "climate.hub"), showing: [.init("hub#fan", value: "on")])
        #expect(actions.shown("hub#fan") == "on")
        store.apply([EntityState(entityId: "climate.hub", state: "heat", attributes: ["fan_mode": .string("on")])])
        await settle()
        #expect(actions.overlay.pending["hub#fan"] == nil)
        await actions.waitForCalls()
    }
}

/// ``HassConnection/delta(from:to:)``: only changed entities are converted.
@MainActor
struct EntityDeliveryDeltaTests {
    private func entity(_ id: String, _ state: String, updated: TimeInterval, attributes: [String: Any] = [:]) throws -> HAEntity {
        try HAEntity(entityId: id, state: state, lastChanged: Date(timeIntervalSince1970: updated),
                     lastUpdated: Date(timeIntervalSince1970: updated), attributes: attributes,
                     context: .init(id: "c", userId: nil, parentId: nil))
    }

    @Test func firstDeliveryConvertsEverything() throws {
        let delta = HassConnection.delta(from: [:], to: [try entity("light.a", "on", updated: 1), try entity("light.b", "off", updated: 1)])
        #expect(delta.isFirst)
        #expect(Set(delta.changed.map(\.entityId)) == ["light.a", "light.b"])
        #expect(delta.removed.isEmpty)
    }

    @Test func laterDeliveriesConvertOnlyChangesAndReportRemovals() throws {
        let a = try entity("light.a", "on", updated: 1)
        let b = try entity("light.b", "off", updated: 1)
        let c = try entity("sensor.c", "3", updated: 1)
        let first = HassConnection.delta(from: [:], to: [a, b, c])
        let bChanged = try entity("light.b", "off", updated: 2, attributes: ["brightness": 10])
        let second = HassConnection.delta(from: first.delivered, to: [a, bChanged])
        #expect(!second.isFirst)
        #expect(second.changed.map(\.entityId) == ["light.b"])
        #expect(second.changed.first?.attributes["brightness"] == .number(10))
        #expect(second.removed == ["sensor.c"])
    }

    @Test func storeAppliesChangesAndRemovalsInPlace() {
        let store = makeStore(["light.a": "on", "sensor.c": "3"])
        let kept = store.entity("light.a")
        let removed = store.entity("sensor.c")
        let before = store.publishedChangeCount
        store.apply([EntityState(entityId: "light.a", state: "on")], removing: ["sensor.c", "missing.x"], freshness: .live)
        #expect(kept.state?.state == "on")
        #expect(removed.state == nil)
        #expect(store.publishedChangeCount == before + 1)
        #expect(store.freshness == .live)
    }
}
