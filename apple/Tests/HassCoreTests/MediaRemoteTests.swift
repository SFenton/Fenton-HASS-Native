import Foundation
@testable import HassCore
import Testing

// MARK: - Test doubles

// `RecordingCaller` and `ManualScheduler` live in `Tests/HassTestSupport`.

@MainActor
func makeStore(_ states: [String: String], attributes: [String: [String: JSONValue]] = [:]) -> EntityStore {
    let store = EntityStore()
    store.replaceAll(states.map { EntityState(entityId: $0.key, state: $0.value, attributes: attributes[$0.key] ?? [:]) })
    return store
}

func set(_ store: EntityStore, _ id: String, _ state: String, _ attributes: [String: JSONValue]? = nil) {
    MainActor.assumeIsolated {
        var entity = store.value(id) ?? EntityState(entityId: id, state: state)
        entity.state = state
        if let attributes { entity.attributes = attributes }
        store.apply([entity])
    }
}

// MARK: - Logic

struct MediaRemoteStateTests {
    @Test func unavailableAndOff() {
        #expect(EntityState.isUnavailable(nil))
        #expect(EntityState.isUnavailable("unknown"))
        #expect(EntityState.isUnavailable("unavailable"))
        #expect(!EntityState.isUnavailable("off"))
        #expect(MediaRemoteState.isOff("off"))
        #expect(MediaRemoteState.isOff(nil))
        #expect(!MediaRemoteState.isOff("standby"))
    }

    @Test func titleCaseAndFormat() {
        #expect(StateText.titleCase("armed_away") == "Armed Away")
        #expect(StateText.titleCase("linked") == "Linked")
        #expect(StateText.titleCase(nil) == "Unknown")
        #expect(StateText.titleCase("") == "Unknown")
        #expect(MediaRemoteState.format(nil) == "Unavailable")
        #expect(MediaRemoteState.format("unavailable") == "Unavailable")
        #expect(MediaRemoteState.format("unknown") == "Unknown")
        #expect(MediaRemoteState.format("playing") == "Playing")
    }

    /// `input text '<value>'` with each `'` written as `'\''` (web `textInputCommand`).
    @Test func textPromptEscapesQuotes() {
        #expect(MediaRemoteState.textInputCommand("hello") == "input text 'hello'")
        #expect(MediaRemoteState.textInputCommand("it's") == #"input text 'it'\''s'"#)
        #expect(MediaRemoteState.textInputCommand("''") == #"input text ''\'''\'''"#)
        #expect(MediaRemoteState.textInputCommand("a b") == "input text 'a b'")
    }

    @Test func activeStates() {
        #expect(MediaRemoteState.isActive("playing", activeStates: []))
        #expect(!MediaRemoteState.isActive("off", activeStates: []))
        #expect(MediaRemoteState.isActive("Server", activeStates: ["Server"]))
        #expect(!MediaRemoteState.isActive("TV", activeStates: ["Server"]))
    }

    @Test func syncModesOrderAndIcons() {
        #expect(MediaRemoteState.orderedSyncModes(["video", "passthrough", "game", "Music"]) == ["Music", "video", "game", "passthrough"])
        #expect(MediaRemoteState.orderedSyncModes(["b", "a"]) == ["b", "a"])
        #expect(MediaRemoteState.syncModeIcon("GAME") == "mdi:gamepad-variant")
        #expect(MediaRemoteState.syncModeIcon("music") == "mdi:music")
        #expect(MediaRemoteState.syncModeIcon("video") == "mdi:movie-open")
        #expect(MediaRemoteState.syncModeIcon("passthrough") == "mdi:lightbulb-multiple")
    }

    @Test func numbersPrintLikeJavaScript() {
        #expect(MediaRemoteState.numberString(50) == "50")
        #expect(MediaRemoteState.numberString(12.5) == "12.5")
    }

    @Test func jsonValuesBecomeSerializableFoundationValues() throws {
        let data: [String: JSONValue] = [
            "a": .string("x"), "b": .number(2), "c": .number(0.25), "d": .bool(true),
            "e": .array([.string("media_player.sonos")]), "f": .object(["g": .number(1)]), "h": .null,
        ]
        let foundation = data.mapValues(\.foundationValue)
        #expect(foundation["b"] as? Int == 2)
        #expect(foundation["c"] as? Double == 0.25)
        #expect(foundation["d"] as? Bool == true)
        #expect(JSONSerialization.isValidJSONObject(foundation as [String: Any]))
    }
}

struct SemanticsRuleTests {
    @Test func rules() {
        #expect(SemanticsRule.toggleOnUnless(["off"]).semantics(for: "on") == .toggle(isOn: true))
        #expect(SemanticsRule.toggleOnUnless(["off"]).semantics(for: "off") == .toggle(isOn: false))
        #expect(SemanticsRule.toggleOnUnless(["off"]).semantics(for: nil) == .toggle(isOn: false))
        #expect(SemanticsRule.toggleOnWhen(["on", "playing"]).semantics(for: "playing") == .toggle(isOn: true))
        #expect(SemanticsRule.toggleOnWhen(["on"]).semantics(for: nil) == .toggle(isOn: false))
        #expect(SemanticsRule.selectedWhen(["Server"]).semantics(for: "Server") == .selection(isSelected: true))
        #expect(SemanticsRule.selectedWhen(["Server"]).semantics(for: nil) == .selection(isSelected: false))
        #expect(SemanticsRule.state.semantics(for: "on") == .state)
    }
}

// MARK: - Action resolution

struct ActionResolutionTests {
    let tvOn = MediaRemoteCommand.service(ServiceCall("script", "on"))
    let tvOff = MediaRemoteCommand.service(ServiceCall("script", "off"))

    @Test func stateActionPicksTheMatchingCase() {
        let action = MediaRemoteAction.state(entityId: "media_player.tv", cases: [.init(["off", "unavailable"], tvOn)], otherwise: tvOff)
        #expect(action.resolve { _ in "off" } == tvOn)
        #expect(action.resolve { _ in "unavailable" } == tvOn)
        #expect(action.resolve { _ in "on" } == tvOff)
        #expect(action.resolve { _ in nil } == tvOff, "No state takes the default")
    }

    @Test func stateActionFallsBackToTheControlsEntityAndOverride() {
        let action = MediaRemotes.pcPowerAction(on: "input_button.on", off: "input_button.off")
        let pressOff = MediaRemoteCommand.service(ServiceCall("input_button", "press", target: "input_button.off"))
        let pressOn = MediaRemoteCommand.service(ServiceCall("input_button", "press", target: "input_button.on"))
        #expect(action.resolve(entityId: "input_boolean.pc") { $0 == "input_boolean.pc" ? "on" : nil } == pressOff)
        #expect(action.resolve(entityId: "input_boolean.pc") { _ in "off" } == pressOn)
        #expect(action.resolve { _ in "on" } == pressOn, "No entity at all takes the default")
        #expect(action.resolve(entityId: "input_boolean.pc", stateOverride: "on") { _ in "off" } == pressOff)
    }

    @Test func commandActionsResolveToThemselves() {
        #expect(MediaRemoteAction.command(tvOn).resolve { _ in nil } == tvOn)
    }

    @Test func iconColorRuleIsRedUnlessEveryEntityIsInactive() {
        let rule = IconColorRule(entityIds: ["a", "b"], inactiveStates: ["off"], inactiveStatesByEntity: ["b": ["standby"]])
        #expect(rule.tone { ["a": "off", "b": "standby"][$0] } == .inactive)
        #expect(rule.tone { ["a": "off", "b": "off"][$0] } == .active)
        #expect(rule.tone { ["a": "on", "b": "standby"][$0] } == .active)
        #expect(rule.tone { ["a": "off"][$0] } == .active, "A missing state counts as active")
    }
}

// MARK: - Configs

struct MediaRemoteConfigTests {
    @Test func everyRemoteIsReachable() {
        #expect(MediaRemotes.all.map(\.id) == ["living-room-shield", "master-bedroom-apple-tv", "theater-room-shield", "music-room-remote"])
        #expect(MediaRemotes.config(id: "#theater-room-shield")?.title == "Theater Room SHIELD")
        #expect(MediaRemotes.config(id: "nope") == nil)
        #expect(MediaRemotes.config(forMediaPlayer: "media_player.sony_projector")?.id == "theater-room-shield")
        #expect(MediaRemotes.config(forMediaPlayer: "media_player.living_room_shield")?.id == "living-room-shield")
        #expect(MediaRemotes.config(forMediaPlayer: "media_player.nope") == nil)
    }

    @Test func tabsOnlyWithContent() {
        #expect(MediaRemotes.livingRoomShield.tabs == [.controls, .apps])
        #expect(MediaRemotes.masterBedroomAppleTV.tabs == [.controls, .apps])
        #expect(MediaRemotes.theaterRoomShield.tabs == [.controls, .apps, .devices])
        #expect(MediaRemotes.musicRoom.tabs == [.controls, .apps, .devices, .hueSync])
        #expect(MediaRemoteTab.allCases.map(\.title) == ["Remote", "Apps", "Devices", "Hue Sync"])
    }

    /// Service calls match `mediaRemotes.ts` verbatim.
    @Test func livingRoomShieldCalls() {
        let config = MediaRemotes.livingRoomShield
        #expect(config.up.action == .service("remote", "send_command", target: "remote.living_room_shield", data: ["command": "DPAD_UP"]))
        #expect(config.select.action == .service("remote", "send_command", target: "remote.living_room_shield", data: ["command": "DPAD_CENTER"]))
        #expect(!config.select.hasIcon, "SHIELD select is blank")
        #expect(config.back.iconRotationDegrees == 90)
        #expect(config.power.action == .service("remote", "send_command", target: "remote.living_room_shield", data: ["command": "POWER"]))
        #expect(config.power.iconColorRule?.inactiveStates == ["off", "unavailable", "unknown"])
        #expect(config.keyboard?.action == .command(.textPrompt(targetEntityId: "media_player.living_room_shield_2")))
        #expect(config.volumeMute.action == .service("script", "toggle_sonos_mute", data: ["sonosdevice": .array(["media_player.sonos"])]))
        #expect(config.volumeUp.action == .service("media_player", "volume_up", target: "media_player.sonos"))
        #expect(config.apps.map(\.title) == ["Plex", "YouTube", "Netflix", "Prime Video", "Paramount+", "Disney+"])
        #expect(config.apps[1].whiteBackground)
        #expect(config.apps[3].imagePath == "/local/images/apps/prime.jpeg")
        #expect(config.apps[0].action == .service("script", "launch_app_on_media_player", data: [
            "entity": "media_player.living_room_shield", "remote_entity": "remote.living_room_shield", "app_id": "com.plexapp.android",
        ]))
        #expect(!config.showVolumeWhenOff)
    }

    @Test func appleTVCalls() {
        let config = MediaRemotes.masterBedroomAppleTV
        #expect(config.up.action == .service("remote", "send_command", target: "remote.master_bedroom_apple_tv", data: ["command": "up"]),
                "Presses skip the single-mode script so fast presses aren't dropped")
        let presses: [(MediaRemoteButton, String)] = [
            (config.left, "left"), (config.select, "select"), (config.right, "right"), (config.down, "down"),
            (config.back, "menu"), (config.home, "home"), (config.pause, "pause"), (config.play, "play"),
        ]
        for (button, command) in presses {
            #expect(button.action == .service("remote", "send_command", target: "remote.master_bedroom_apple_tv", data: ["command": .string(command)]),
                    "\(button.label)")
        }
        #expect(config.back.label == "Menu")
        #expect(config.back.icon == "mdi:chevron-left")
        #expect(config.home.icon == "mdi:home")
        #expect(config.select.hasIcon, "Apple TV select is a dot")
        #expect(config.keyboard == nil)
        #expect(config.power.action == .service("script", "apple_tv_power_on_off"))
        #expect(config.power.iconColorRule?.inactiveStates == ["off", "standby", "unavailable"])
        #expect(config.volumeEntityId == "media_player.primary_bedroom")
        #expect(config.apps.first?.action == .service("script", "launch_app_on_apple_tv", data: [
            "entity": "media_player.master_bedroom_apple_tv", "app_name": "Plex", "remote_entity": "remote.master_bedroom_apple_tv",
        ]))
    }

    @Test func theaterCalls() {
        let config = MediaRemotes.theaterRoomShield
        #expect(config.power.action == .service("script", "toggle_on_off_theater_room"))
        #expect(config.volumeMute.action == .service("media_player", "volume_mute", target: "media_player.theater", data: ["is_volume_muted": true]))
        #expect(config.showVolumeWhenOff)
        #expect(config.apps[0].action == .service("script", "launch_app_on_media_player", data: [
            "entity": "media_player.theater_room_shield", "remote_entity": "remote.theater_shield_remote",
            "app_id": "com.plexapp.android", "turn_on_projector": true,
        ]))
        #expect(config.devices.map(\.title) == ["Projector", "Yamaha AVR", "Theater Room SHIELD", "Theater Room PC"])
        #expect(config.devices[0].action == .service("media_player", "toggle", target: "media_player.sony_projector"))
    }

    @Test func musicRoomMatchesTheWeb() {
        let config = MediaRemotes.musicRoom
        typealias M = MediaRemotes.MusicRoom
        #expect(config.power.action == M.tvToggle)
        #expect(config.power.semantics == .toggleOnUnless(["off", "unavailable", "unknown"]))
        #expect(config.appSectionTitle == "Quick App Launch")
        #expect(config.volumeTitle == "Sonos Beam Volume")
        #expect(config.showVolumeWhenOff)
        #expect(config.devices.map(\.title) == ["TV", "Xbox", "Server", "Windows PC", "Sonos Beam"])
        #expect(config.devices[1].activeHold == .seconds(45))
        #expect(config.devices[2].stateLabels == ["Fortnite": "Off", "Off": "Off", "Server": "On", "TV": "Off", "Windows PC": "Off", "Xbox": "Off"])
        #expect(config.liveChangeEntityIds == [M.activeMediaSourceEntityId])
        #expect(Set(config.optimisticEntityIds).count == 10)
        #expect(config.hueSync?.entityIds.count == 10)
        guard case let .command(.service(call, intents)) = M.fortnite else { Issue.record("fortnite is a script"); return }
        #expect(call == ServiceCall("script", "music_room_fortnite"))
        #expect(intents.count == 6)
        #expect(intents.allSatisfy { $0.revertAfter == .seconds(120) })
        #expect(intents.contains(OptimisticIntent(M.hueSyncHdmiInputEntityId, "HDMI 1", revertAfter: .seconds(120))))
    }
}

// MARK: - Music Room Xbox resolver

struct MusicRoomXboxResolverTests {
    typealias M = MediaRemotes.MusicRoom

    func states(cloud: String? = nil, hdmi: String? = nil, tv: String? = nil, power: String? = nil, input: String? = nil) -> [String: String] {
        var states: [String: String] = [:]
        states[M.xboxEntityId] = cloud
        states[M.xboxHdmiStatusEntityId] = hdmi
        states[M.controlEntityId] = tv
        states[M.hueSyncPowerEntityId] = power
        states[M.hueSyncHdmiInputEntityId] = input
        return states
    }

    @Test(arguments: ["on", "playing", "paused"])
    func cloudActiveIsOn(cloud: String) {
        #expect(M.xboxState(states(cloud: cloud)) == "on")
    }

    @Test func linkedOnTheActivePathIsOn() {
        #expect(M.xboxState(states(cloud: "off", hdmi: "linked", tv: "on", power: "on", input: "HDMI 1")) == "on")
    }

    @Test func anyBrokenLinkIsOff() {
        #expect(M.xboxState(states(cloud: "off", hdmi: "plugged", tv: "on", power: "on", input: "HDMI 1")) == "off")
        #expect(M.xboxState(states(cloud: "off", hdmi: "linked", tv: "off", power: "on", input: "HDMI 1")) == "off")
        #expect(M.xboxState(states(cloud: "off", hdmi: "linked", tv: "unknown", power: "on", input: "HDMI 1")) == "off")
        #expect(M.xboxState(states(cloud: "off", hdmi: "linked", tv: "on", power: "off", input: "HDMI 1")) == "off")
        #expect(M.xboxState(states(cloud: "off", hdmi: "linked", tv: "on", power: "on", input: "HDMI 2")) == "off")
        #expect(M.xboxState(states(hdmi: "linked", tv: "on", power: "on")) == "off", "No input")
    }

    @Test func nothingKnownIsUnavailable() {
        #expect(M.xboxState(states()) == "unavailable")
        #expect(M.xboxState(states(cloud: "unavailable", hdmi: "unknown")) == "unavailable")
        #expect(MediaRemoteStateResolver.musicRoomXbox.resolve(states(cloud: "playing")) == "on")
    }
}
