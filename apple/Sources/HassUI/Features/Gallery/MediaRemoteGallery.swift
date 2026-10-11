import HassCore
import HassDesign
import Observation
import SwiftUI

/// Gallery page for the media remote: every remote on fixture state with a recording service caller, so
/// journeys exercise real controls without touching the house. `FENTON_GALLERY_REMOTE=<id>` opens a remote at
/// launch and `FENTON_GALLERY_TAB=<tab>` picks its first tab.
struct MediaRemoteGallery: View {
    @State private var store: EntityStore
    @State private var recorder: GalleryServiceRecorder
    @State private var open: MediaRemoteConfig?
    private let initialTab: MediaRemoteTab

    init() {
        let environment = ProcessInfo.processInfo.environment
        let store = MediaRemoteFixtures.store()
        _store = State(initialValue: store)
        _recorder = State(initialValue: GalleryServiceRecorder(store: store))
        _open = State(initialValue: environment["FENTON_GALLERY_REMOTE"].flatMap(MediaRemotes.config(id:)))
        initialTab = environment["FENTON_GALLERY_TAB"].flatMap(MediaRemoteTab.init(rawValue:)) ?? .controls
    }

    var body: some View {
        List {
            Section {
                ForEach(MediaRemotes.all) { config in
                    Button(config.title) { open = config }
                        .accessibilityIdentifier("gallery.remote.\(config.id)")
                }
            } footer: {
                // Only while no remote is open: behind an iPad page sheet the dimmed copy fails contrast.
                if open == nil { lastCall }
            }
        }
        .navigationTitle("Media Remote")
        .sheet(item: $open) { config in
            MediaRemoteSheet(config: config, store: store, caller: recorder, imageServer: MediaRemoteFixtures.imageServer, initialTab: initialTab)
                .safeAreaInset(edge: .top) {
                    // FENTON_GALLERY_CLEAN=1 (screenshots) leaves the debug line out.
                    if !Self.isClean { lastCall.padding(.horizontal).padding(.vertical, 4).background(.bar) }
                }
                .mediaRemotePresentation()
        }
    }

    static var isClean: Bool { ProcessInfo.processInfo.environment["FENTON_GALLERY_CLEAN"] == "1" }

    /// The last service call, which journeys read to check what a control sent.
    private var lastCall: some View {
        Text("Last call: \(recorder.lastCall)")
            .font(.caption.monospaced())
            .foregroundStyle(HassTokens.Ink.secondary)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("gallery.lastCall")
    }
}

/// Records service calls and echoes the few that change fixture state, after a short delay like Home Assistant.
@MainActor
@Observable
final class GalleryServiceRecorder: HassServiceCalling {
    private(set) var lastCall = "None"
    @ObservationIgnored private let store: EntityStore

    init(store: EntityStore) { self.store = store }

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        lastCall = Self.describe(domain, service, data)
        try? await Task.sleep(for: .milliseconds(400))
        echo(domain, service, data)
    }

    /// `domain.service key=value …` with keys sorted, e.g. `remote.send_command command=DPAD_UP entity_id=remote.x`.
    static func describe(_ domain: String, _ service: String, _ data: [String: any Sendable]) -> String {
        let pairs = data.keys.sorted().map { key in "\(key)=\(describeValue(data[key]!))" }
        return ([domain + "." + service] + pairs).joined(separator: " ")
    }

    private static func describeValue(_ value: any Sendable) -> String {
        if let array = value as? [any Sendable] { return "[" + array.map(describeValue).joined(separator: ",") + "]" }
        return "\(value)"
    }

    private func echo(_ domain: String, _ service: String, _ data: [String: any Sendable]) {
        let target = data["entity_id"] as? String
        func set(_ id: String, _ state: String) {
            var entity = store.value(id) ?? EntityState(entityId: id, state: state)
            entity.state = state
            store.apply([entity])
        }
        func flip(_ id: String, on: String = "on", off: String = "off") {
            set(id, MediaRemoteState.isOff(store.value(id)?.state) || store.value(id)?.state == off ? on : off)
        }
        switch (domain, service) {
        case ("media_player", "toggle"): if let target { flip(target) }
        case ("switch", "turn_on"), ("light", "turn_on"): if let target { set(target, "on") }
        case ("switch", "turn_off"), ("light", "turn_off"): if let target { set(target, "off") }
        case ("select", "select_option"):
            if let target, let option = data["option"] as? String { set(target, option) }
            // Choosing a sync mode starts syncing, as the Sync Box does.
            if target == MediaRemotes.MusicRoom.hueSyncModeEntityId {
                set(MediaRemotes.MusicRoom.hueSyncPowerEntityId, "on")
                set(MediaRemotes.MusicRoom.hueSyncLightSyncEntityId, "on")
            }
        case ("number", "set_value"):
            if let target, let value = data["value"] { set(target, "\(value)") }
        case ("media_player", "volume_set"):
            if let target, var entity = store.value(target), let level = data["volume_level"] as? Double {
                entity.attributes["volume_level"] = .number(level)
                store.apply([entity])
            }
        case ("input_button", "press"):
            // `input_button.<pc>_on` / `_off` drive `input_boolean.<pc>_power` (theater and office PCs).
            if let target, let cut = target.range(of: "_o", options: .backwards) {
                let prefix = target[target.index(target.startIndex, offsetBy: "input_button.".count)..<cut.lowerBound]
                set("input_boolean.\(prefix)_power", target.hasSuffix("_on") ? "on" : "off")
            }
        case ("remote", "send_command") where data["command"] as? String == "POWER":
            flip("media_player.living_room_shield_2", on: "playing")
        case ("script", "apple_tv_power_on_off"):
            flip("media_player.master_bedroom_apple_tv", on: "paused", off: "standby")
        case ("script", "toggle_on_off_theater_room"):
            flip("media_player.theater_room_shield")
        case ("script", "music_room_tv"):
            set(MediaRemotes.MusicRoom.controlEntityId, "on")
            set(MediaRemotes.MusicRoom.activeMediaSourceEntityId, "TV")
        case ("script", "music_room_tv_off"):
            set(MediaRemotes.MusicRoom.controlEntityId, "off")
            set(MediaRemotes.MusicRoom.activeMediaSourceEntityId, "Off")
        default: break
        }
    }
}

/// Synthetic entity states for the gallery and hosted tests (not a copy of the live house).
enum MediaRemoteFixtures {
    /// App artwork comes from the household server's public `/local` folder when it is reachable; the tiles fall
    /// back to icons otherwise. `FENTON_GALLERY_OFFLINE=1` forces the fallback.
    static var imageServer: HassServer? {
        let environment = ProcessInfo.processInfo.environment
        if environment["FENTON_GALLERY_OFFLINE"] == "1" { return nil }
        return environment["FENTON_HASS_SERVER"].flatMap(URL.init(string:)).map(HassServer.init(baseURL:)) ?? .fentonHome
    }

    @MainActor static func store() -> EntityStore {
        let store = EntityStore()
        store.replaceAll(states, freshness: .live)
        return store
    }

    static let states: [EntityState] = {
        typealias M = MediaRemotes.MusicRoom
        func entity(_ id: String, _ state: String, _ attributes: [String: JSONValue] = [:]) -> EntityState {
            EntityState(entityId: id, state: state, attributes: attributes)
        }
        func options(_ values: [String]) -> [String: JSONValue] { ["options": .array(values.map(JSONValue.string))] }
        return [
            entity("media_player.living_room_shield_2", "playing"),
            entity("media_player.sonos", "playing", ["volume_level": .number(0.32)]),
            entity("media_player.master_bedroom_apple_tv", "paused"),
            entity("media_player.primary_bedroom", "idle", ["volume_level": .number(0.24)]),
            entity("media_player.theater_room_shield", "on"),
            entity("media_player.theater", "on", ["volume_level": .number(0.45)]),
            entity("media_player.sony_projector", "on"),
            entity("input_boolean.theater_pc_power", "off"),
            entity(M.controlEntityId, "on"),
            entity(M.xboxEntityId, "off"),
            entity(M.volumeEntityId, "on", ["volume_level": .number(0.3)]),
            entity(M.activeMediaSourceEntityId, "TV"),
            entity(M.mediaSourceEntityId, "TV"),
            entity(M.hueSyncPowerEntityId, "on"),
            entity(M.hueSyncLightSyncEntityId, "off"),
            entity(M.hueSyncModeEntityId, "video", options(["video", "music", "game"])),
            entity(M.hueSyncIntensityEntityId, "moderate", options(["subtle", "moderate", "high", "intense"])),
            entity(M.hueSyncBrightnessEntityId, "50", ["min": .number(0), "max": .number(100), "step": .number(1)]),
            entity(M.hueSyncHdmiInputEntityId, "HDMI 1", options(["HDMI 1", "HDMI 2", "HDMI 3", "HDMI 4"])),
            entity(M.hueSyncHdmiStatusEntityIds[0], "linked"),
            entity(M.hueSyncHdmiStatusEntityIds[1], "connected"),
            entity(M.hueSyncHdmiStatusEntityIds[2], "plugged"),
            entity(M.hueSyncHdmiStatusEntityIds[3], "unplugged"),
        ]
    }()
}
