import Foundation
@testable import HassCore
import Testing

/// Household Settings: config parity with the web, the presence mode resolver, and what each control sends.
@MainActor
struct HouseholdSettingsTests {
    typealias Config = HouseholdSettingsConfig

    func controller(_ states: [String: String], attributes: [String: [String: JSONValue]] = [:])
        -> (HouseholdSettingsController, EntityStore, RecordingCaller, ManualScheduler)
    {
        let store = makeStore(states, attributes: attributes)
        let caller = RecordingCaller()
        let scheduler = ManualScheduler()
        return (HouseholdSettingsController(store: store, caller: caller, scheduler: scheduler), store, caller, scheduler)
    }

    // MARK: Config

    @Test func adminMatchesTheWeb() {
        #expect(Config.Admin.presenceRooms.count == 14)
        #expect(Config.Admin.presenceRooms.first?.title == "Living Room")
        #expect(Config.Admin.presenceRooms.last?.presenceEntityId == "switch.upper_deck_presence_back_deck_lights_presence_allowed")
        #expect(Config.Admin.autoResetTiles.map(\.entityId).contains("switch.downstairs_hallway_auto_re_enable_presence_lighting"))
        #expect(Set(Config.Admin.presenceRooms.map(\.presenceEntityId)).count == 14)
        #expect(Config.Admin.relayControl.paragraphs.count == 2)
        #expect(Config.Admin.autoReset.paragraphs.count == 2)
        #expect(Config.Admin.showSpecificTiles.map(\.title) == ["Outdoor Faucets", "Christmas Lights"])
    }

    @Test func guestsReuseTheHomeToggles() {
        #expect(Config.Guests.tiles.map(\.entityId) == HomeConfig.guestToggles.map(\.entityId))
        #expect(Config.Guests.tiles.allSatisfy(\.showsState))
    }

    @Test func toggleIdsAreUniqueAndCoverEveryPage() {
        let ids = Config.toggleEntityIds
        #expect(Set(ids).count == ids.count)
        #expect(ids.contains("input_boolean.high_aqi_mode"))
        #expect(ids.contains("input_boolean.relay_control_mode"))
        #expect(ids.count == 1 + 1 + 2 + 14 + 1 + 3)
        #expect(Config.icons.contains("mdi:pause-circle"))
    }

    // MARK: Presence modes

    @Test func presenceModeResolvesFromStateAndAttributes() {
        func mode(_ state: String, _ attributes: [String: JSONValue] = [:]) -> PresenceOverrideState {
            PresenceOverrideState(entity: EntityState(entityId: "switch.x", state: state, attributes: attributes))
        }
        #expect(PresenceOverrideState(entity: nil) == .unavailable)
        #expect(mode("unavailable") == .unavailable)
        #expect(mode("unknown") == .unavailable)
        #expect(mode("off") == .off)
        #expect(mode("off", ["automation_state": .string("paused")]) == .off)
        #expect(mode("on") == .enabled)
        #expect(mode(" ON ") == .enabled)
        #expect(mode("on", ["automation_state": .string("Paused")]) == .paused)
        #expect(mode("on", ["automation_paused": .bool(true)]) == .paused)
        #expect(mode("on", ["automation_paused": .string("on")]) == .paused)
        #expect(mode("on", ["automation_state": .string("quieted")]) == .quieted)
        #expect(mode("on", ["automation_quieted": .string("true")]) == .quieted)
        #expect(mode("on", ["automation_quieted": .bool(false)]) == .enabled)
        #expect(mode("idle") == .unavailable)
    }

    @Test func presenceCommandsMapEnabledToActive() {
        #expect(PresenceOverrideState.enabled.command(for: "switch.x")
            == ServiceCall("presence_based_lighting", "set_automation_state", target: "switch.x", data: ["state": .string("active")]))
        #expect(PresenceOverrideState.quieted.command(for: "switch.x")?.data["state"] == .string("quieted"))
        #expect(PresenceOverrideState.off.command(for: "switch.x")?.data["state"] == .string("off"))
        #expect(PresenceOverrideState.unavailable.command(for: "switch.x") == nil)
    }

    @Test func presencePresentationMatchesTheWeb() {
        #expect(PresenceOverrideState.choices == [.enabled, .off, .paused, .quieted])
        #expect(PresenceOverrideState.enabled.summary == "Enabled")
        #expect(PresenceOverrideState.off.label == "Disable Presence-Based Lighting")
        #expect(PresenceOverrideState.paused.detail == "Lights stay in their current state until explicitly resumed.")
        #expect(PresenceOverrideState.quieted.rgb.red == 117 && PresenceOverrideState.quieted.rgb.blue == 180)
        for state in PresenceOverrideState.allCases {
            #expect(!state.label.isEmpty && !state.summary.isEmpty && !state.detail.isEmpty && state.icon.hasPrefix("mdi:"))
            #expect(state.id == state.rawValue)
        }
    }

    // MARK: Toggles

    @Test func togglesSendExplicitOnOffFromTheShownState() async {
        let (settings, _, caller, _) = controller([
            "input_boolean.high_aqi_mode": "off",
            "switch.kitchen_auto_re_enable_presence_lighting": "on",
        ])
        settings.flip("input_boolean.high_aqi_mode")
        settings.flip("switch.kitchen_auto_re_enable_presence_lighting")
        await settings.waitForCalls()
        #expect(caller.calls == [
            .init(domain: "input_boolean", service: "turn_on", data: ["entity_id": "input_boolean.high_aqi_mode"]),
            .init(domain: "switch", service: "turn_off", data: ["entity_id": "switch.kitchen_auto_re_enable_presence_lighting"]),
        ])
    }

    @Test func otherDomainsGoThroughHomeAssistant() async {
        let (settings, _, caller, _) = controller(["fan.x": "on"])
        settings.flip("fan.x")
        await settings.waitForCalls()
        #expect(caller.calls.first?.domain == "homeassistant")
        #expect(caller.calls.first?.service == "turn_off")
    }

    @Test func toggleIsOptimisticUntilConfirmed() async {
        let id = "input_boolean.high_aqi_mode"
        let (settings, store, _, scheduler) = controller([id: "off"])
        #expect(settings.toggle(id) == .init(isOn: false, isUnavailable: false, subtitle: "Off"))
        settings.flip(id)
        #expect(settings.toggle(id).isOn)
        // A second tap flips from what is shown.
        settings.flip(id)
        #expect(!settings.toggle(id).isOn)
        settings.flip(id)
        await settings.waitForCalls()
        store.apply([EntityState(entityId: id, state: "on")])
        for _ in 0..<20 where settings.overlay.pending[id] != nil { await Task.yield() }
        #expect(settings.overlay.pending[id] == nil)
        #expect(settings.toggle(id).subtitle == "On")
        #expect(scheduler.pending.isEmpty)
    }

    @Test func toggleRevertsWhenHomeAssistantDoesNotConfirm() async {
        let id = "input_boolean.relay_control_mode"
        let (settings, _, _, scheduler) = controller([id: "on"])
        settings.flip(id)
        #expect(!settings.toggle(id).isOn)
        scheduler.fireAll()
        #expect(settings.toggle(id).isOn)
    }

    @Test func failedCallUndoesTheToggle() async {
        let id = "input_boolean.show_christmas_lights"
        let (settings, _, caller, _) = controller([id: "off"])
        caller.failNext = true
        settings.flip(id)
        #expect(settings.toggle(id).isOn)
        await settings.waitForCalls()
        #expect(!settings.toggle(id).isOn)
    }

    @Test(arguments: [nil, "unavailable", "unknown"])
    func unavailableTogglesDoNothing(state: String?) async {
        let id = "input_boolean.high_aqi_mode"
        let (settings, _, caller, _) = controller(state.map { [id: $0] } ?? [:])
        #expect(settings.toggle(id) == .init(isOn: false, isUnavailable: true, subtitle: "Unavailable"))
        settings.flip(id)
        await settings.waitForCalls()
        #expect(caller.calls.isEmpty)
    }

    @Test func relayWarningNeedsRelayModeAndGuestRoom() {
        let relay = Config.Admin.relayControlEntityId
        let guest = "input_boolean.guests_staying_in_guest_room"
        #expect(controller([relay: "on", guest: "on"]).0.showsRelayGuestModeWarning)
        #expect(!controller([relay: "on", guest: "off"]).0.showsRelayGuestModeWarning)
        #expect(!controller([relay: "off", guest: "on"]).0.showsRelayGuestModeWarning)
        #expect(!controller([:]).0.showsRelayGuestModeWarning)
    }

    // MARK: Presence

    @Test func settingAPresenceModeSendsItAndShowsItAtOnce() async {
        let id = Config.Admin.presenceRooms[0].presenceEntityId
        let (settings, store, caller, _) = controller([id: "on"])
        #expect(settings.presence(id) == .enabled)
        settings.setPresence(id, to: .paused)
        #expect(settings.presence(id) == .paused)
        await settings.waitForCalls()
        #expect(caller.calls == [.init(domain: "presence_based_lighting", service: "set_automation_state",
                                       data: ["entity_id": id, "state": "paused"])])
        store.apply([EntityState(entityId: id, state: "on", attributes: ["automation_state": .string("paused")])])
        for _ in 0..<20 where settings.overlay.pending[HouseholdSettingsController.presenceKey(id)] != nil { await Task.yield() }
        #expect(settings.overlay.pending[HouseholdSettingsController.presenceKey(id)] == nil)
        #expect(settings.presence(id) == .paused)
    }

    @Test func presenceFailureAndUnavailable() async {
        let id = Config.Admin.presenceRooms[1].presenceEntityId
        let (settings, store, caller, _) = controller([id: "off"])
        caller.failNext = true
        settings.setPresence(id, to: .enabled)
        #expect(settings.presence(id) == .enabled)
        await settings.waitForCalls()
        #expect(settings.presence(id) == .off)
        store.apply([EntityState(entityId: id, state: "unavailable")])
        settings.setPresence(id, to: .enabled)
        settings.setPresence(id, to: .unavailable)
        await settings.waitForCalls()
        #expect(caller.calls.count == 1)
        #expect(settings.presence(id) == .unavailable)
    }

    // MARK: Commands and read-only tiles

    @Test func powerRecoveryTriggersTheAutomation() async {
        let (settings, _, caller, _) = controller([:])
        settings.triggerPowerRecovery()
        await settings.waitForCalls()
        #expect(caller.calls == [.init(domain: "automation", service: "trigger",
                                       data: ["entity_id": "automation.attempt_to_turn_power_back_on_in_living_room"])])
    }

    @Test func machETilesFormatLikeTheWeb() {
        let tiles = Config.MachE.tiles
        let (settings, _, _, _) = controller([
            tiles[0].entityId: "ChargingAC",
            tiles[1].entityId: "locked",
            tiles[2].entityId: "heated_low",
            tiles[3].entityId: "unavailable",
        ])
        #expect(settings.readOnly(tiles[0]) == .init(subtitle: "ChargingAC", isActive: false, isUnavailable: false))
        #expect(settings.readOnly(tiles[1]).subtitle == "Locked")
        #expect(settings.readOnly(tiles[2]).subtitle == "Heated Low")
        #expect(settings.readOnly(tiles[3]) == .init(subtitle: "Unavailable", isActive: false, isUnavailable: true))
        #expect(settings.readOnly(tiles[4]) == .init(subtitle: "Unavailable", isActive: false, isUnavailable: true))
        let hidden = HouseholdSettingsConfig.Tile(title: "X", entityId: "light.x", icon: "mdi:x", showsState: false)
        let (lit, _, _, _) = controller(["light.x": "on"])
        #expect(lit.readOnly(hidden) == .init(subtitle: nil, isActive: true, isUnavailable: false))
    }

    @Test func stateFormatting() {
        #expect(HouseholdSettingsController.format(nil) == "Unknown")
        #expect(HouseholdSettingsController.format("") == "Unknown")
        #expect(HouseholdSettingsController.format("armed_away") == "Armed Away")
        #expect(HouseholdSettingsController.compactState(nil) == "Unavailable")
        #expect(HouseholdSettingsController.compactState(EntityState(entityId: "sensor.x", state: "42.5")) == "42.5")
        #expect(HouseholdSettingsController.compactState(EntityState(entityId: "number.x", state: "72")) == "72")
    }
}
