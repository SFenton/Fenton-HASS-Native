#if DEBUG
import HassCore
import HassDesign
import Observation
import SwiftUI

/// Gallery pages for the Media, Custom Lights and Sprinklers pages: each page on fixture state with a recording
/// service caller, so journeys, audits and screenshots run signed out and never touch the house.
///
/// Launch options: `FENTON_GALLERY_REMOTE=<id>` opens a remote from Media; `FENTON_GALLERY_LIGHT=<entity>` opens a
/// custom light's sheet and `FENTON_GALLERY_PICKER=1` the lighting modes; `FENTON_GALLERY_SPRINKLER=<id>` opens a
/// controller and `FENTON_GALLERY_DETAIL=water-<zone>|schedule-<zone>` a page in it. `FENTON_GALLERY_CLEAN=1` hides the
/// last-call line for screenshots.
struct HomePageGallery: View {
    enum Kind { case media, customLights, sprinklers }

    var kind: Kind
    @State private var store: EntityStore
    @State private var recorder: PageGalleryRecorder

    init(kind: Kind) {
        self.kind = kind
        let store = EntityStore()
        store.replaceAll(HomePageFixtures.states, freshness: .live)
        _store = State(initialValue: store)
        _recorder = State(initialValue: PageGalleryRecorder(store: store))
    }

    var body: some View {
        let environment = ProcessInfo.processInfo.environment
        Group {
            switch kind {
            case .media:
                MediaScreen(store: store, caller: recorder, imageServer: nil,
                            openRemote: environment["FENTON_GALLERY_REMOTE"].flatMap(MediaRemotes.config(id:)))
            case .customLights:
                CustomLightsScreen(store: store, caller: recorder,
                                   openLight: CustomLightsConfig.lights.first { $0.entityId == environment["FENTON_GALLERY_LIGHT"] },
                                   openPicker: environment["FENTON_GALLERY_PICKER"] == "1")
            case .sprinklers:
                SprinklersScreen(store: store, caller: recorder, openController: environment["FENTON_GALLERY_SPRINKLER"],
                                 detail: environment["FENTON_GALLERY_DETAIL"].flatMap(Self.detail))
            }
        }
        .galleryLastCallBanner()
        .environment(\.galleryRecorder, recorder)
        .environment(store)
    }

    /// `water-1` or `schedule-0`.
    static func detail(_ text: String) -> SprinklerDetail? {
        let parts = text.split(separator: "-")
        guard parts.count == 2, let zone = Int(parts[1]) else { return nil }
        switch parts[0] {
        case "water": return .water(zone: zone)
        case "schedule": return .schedule(zone: zone)
        default: return nil
        }
    }
}

// MARK: - Recorder

/// Records service calls and echoes the ones these pages send after a short delay, like Home Assistant.
/// Media remote calls go through the remote gallery's recorder so its echoes apply too.
@MainActor
@Observable
final class PageGalleryRecorder: HassServiceCalling {
    private(set) var lastCall = "None"
    @ObservationIgnored private let store: EntityStore
    @ObservationIgnored private let remote: GalleryServiceRecorder

    init(store: EntityStore) {
        self.store = store
        remote = GalleryServiceRecorder(store: store)
    }

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        lastCall = GalleryServiceRecorder.describe(domain, service, data)
        try await remote.callService(domain, service, data: data)
        echo(domain, service, data)
    }

    private func echo(_ domain: String, _ service: String, _ data: [String: any Sendable]) {
        let target = data["entity_id"] as? String
        func update(_ id: String, _ change: (inout EntityState) -> Void) {
            var entity = store.value(id) ?? EntityState(entityId: id, state: "unknown")
            change(&entity)
            store.apply([entity])
        }
        switch (domain, service) {
        case ("input_boolean", "turn_on"), ("input_boolean", "turn_off"):
            if let target { update(target) { $0.state = service == "turn_on" ? "on" : "off" } }
        case ("input_select", "select_option"):
            if let target, let option = data["option"] as? String { update(target) { $0.state = option } }
        case ("light", "turn_off"):
            if let target { update(target) { $0.state = "off"; $0.attributes["brightness"] = nil } }
        case ("light", "turn_on"):
            guard let target else { return }
            let ids = target == CustomLightsConfig.groupEntityId ? CustomLightsConfig.lights.map(\.entityId) + [target] : [target]
            for id in ids {
                update(id) { entity in
                    entity.state = "on"
                    if let percent = data["brightness_pct"] as? Int { entity.attributes["brightness"] = .number(Double(percent) * 2.55) }
                    if let brightness = data["brightness"] as? Int { entity.attributes["brightness"] = .number(Double(brightness)) }
                    if let rgb = data["rgb_color"] as? [any Sendable] { entity.attributes["rgb_color"] = .array(rgb.compactMap { ($0 as? Int).map { .number(Double($0)) } }) }
                    if data["color_temp_kelvin"] != nil { entity.attributes["rgb_color"] = .array([.number(255), .number(137), .number(14)]) }
                }
            }
        case ("bhyve", "start_watering"), ("bhyve", "stop_watering"):
            if let valve = data["entity_id"] as? String { update(valve) { $0.state = service == "start_watering" ? "open" : "closed" } }
        case ("bhyve", "update_program"):
            guard let program = data["entity_id"] as? String else { return }
            update(program) { entity in
                if let budget = data["budget"] as? Int { entity.attributes["budget"] = .number(Double(budget)) }
                if let times = data["start_times"] as? [any Sendable] { entity.attributes["start_times"] = .array(times.compactMap { ($0 as? String).map(JSONValue.string) }) }
                if let frequency = data["frequency"] as? [String: any Sendable], let days = frequency["days"] as? [any Sendable] {
                    entity.attributes["frequency"] = .object(["type": .string("days"), "days": .array(days.compactMap { ($0 as? Int).map { .number(Double($0)) } })])
                }
            }
        default: break
        }
    }
}

// MARK: - Last call banner

private struct GalleryRecorderKey: EnvironmentKey {
    static let defaultValue: PageGalleryRecorder? = nil
}

extension EnvironmentValues {
    /// The gallery's recorder; `nil` in the app, so the banner never shows there.
    var galleryRecorder: PageGalleryRecorder? {
        get { self[GalleryRecorderKey.self] }
        set { self[GalleryRecorderKey.self] = newValue }
    }
}

extension View {
    /// In the gallery, shows the last service call above the content (journeys read it); nothing in the app.
    func galleryLastCallBanner() -> some View { modifier(GalleryLastCallBanner()) }
}

private struct GalleryLastCallBanner: ViewModifier {
    @Environment(\.galleryRecorder) private var recorder

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top) {
            if let recorder, !MediaRemoteGallery.isClean {
                Text("Last call: \(recorder.lastCall)")
                    .font(.caption.monospaced())
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .background(.bar)
                    .accessibilityIdentifier("gallery.lastCall")
            }
        }
    }
}

// MARK: - Fixtures

/// Synthetic states for the three pages (not a copy of the live house).
enum HomePageFixtures {
    static func entity(_ id: String, _ state: String, _ attributes: [String: JSONValue] = [:]) -> EntityState {
        EntityState(entityId: id, state: state, attributes: attributes)
    }

    static func rgb(_ r: Double, _ g: Double, _ b: Double) -> JSONValue { .array([.number(r), .number(g), .number(b)]) }

    static func numbers(_ values: [Double]) -> JSONValue { .array(values.map(JSONValue.number)) }

    @MainActor static func store() -> EntityStore {
        let store = EntityStore()
        store.replaceAll(states, freshness: .live)
        return store
    }

    static let states: [EntityState] = MediaRemoteFixtures.states + media + customLights + sprinklers

    static let media: [EntityState] = [
        entity("media_player.living_room_shield", "playing"),
        entity("input_boolean.is_nintendo_switch_active", "off"),
        entity("input_boolean.is_theater_shield_active", "on"),
    ]

    static let customLights: [EntityState] = {
        let color: [String: JSONValue] = ["supported_color_modes": .array([.string("color_temp"), .string("xy")])]
        let colors = [rgb(0, 255, 0), rgb(0, 0, 255), rgb(255, 0, 234), rgb(255, 0, 0), rgb(0, 255, 0), rgb(255, 137, 14), rgb(0, 0, 255)]
        var states = [
            entity(CustomLightsConfig.manualControlEntityId, "on"),
            entity(CustomLightsConfig.modeEntityId, "Custom", ["options": .array(CustomLightsConfig.fallbackModes.map(JSONValue.string))]),
            entity(CustomLightsConfig.groupEntityId, "on", color),
        ]
        for (index, light) in CustomLightsConfig.lights.enumerated() {
            if index < colors.count {
                states.append(entity(light.entityId, "on", color.merging(["brightness": .number(Double(255 - index * 25)), "rgb_color": colors[index]]) { $1 }))
            } else {
                states.append(entity(light.entityId, "off", color))
            }
        }
        return states
    }()

    static let sprinklers: [EntityState] = {
        let front = SprinklersConfig.frontYard
        let back = SprinklersConfig.backyard
        func program(_ id: String, station: Int, days: [Double], times: [String], budget: Double, minutes: Double, on: Bool = true) -> EntityState {
            entity(id, on ? "on" : "off", [
                "frequency": .object(["type": .string("days"), "days": numbers(days)]),
                "start_times": .array(times.map(JSONValue.string)),
                "budget": .number(budget),
                "run_times": .array([.object(["station": .number(Double(station)), "run_time": .number(minutes)])]),
            ])
        }
        func valve(_ id: String, name: String, station: Int, open: Bool = false) -> EntityState {
            entity(id, open ? "open" : "closed", ["zone_name": .string(name), "station": .number(Double(station))])
        }
        func history(_ id: String, start: String, minutes: Double) -> EntityState {
            entity(id, start, ["start_time": .string(start), "run_time": .number(minutes)])
        }
        return [
            entity(SprinklersConfig.visibilityEntityId, "on"),
            // Front yard: ready, one zone.
            entity(front.stateEntityId, "auto"),
            entity(front.modeEntityId, "auto"),
            entity(front.batteryEntityId, "86"),
            entity(front.faultEntityId, "off"),
            entity(front.hubConnectedEntityId, "on"),
            entity(front.nextWateringEntityId, "2026-10-12T13:30:00+00:00"),
            entity(front.rainDelayEntityId, "off"),
            entity(front.smartWateringEntityId, "on"),
            valve(front.zones[0].valveEntityId, name: "Front Yard", station: 1),
            program(front.zones[0].programEntityId, station: 1, days: [1, 3, 5], times: ["06:30"], budget: 100, minutes: 20),
            history(front.zones[0].historyEntityId, start: "2026-10-10T13:30:00+00:00", minutes: 20),
            // Backyard: low battery, the House zone watering.
            entity(back.stateEntityId, "auto"),
            entity(back.modeEntityId, "auto"),
            entity(back.batteryEntityId, "18"),
            entity(back.faultEntityId, "off"),
            entity(back.hubConnectedEntityId, "on"),
            entity(back.nextWateringEntityId, "unknown"),
            entity(back.rainDelayEntityId, "off"),
            entity(back.smartWateringEntityId, "off"),
            valve(back.zones[0].valveEntityId, name: "Bushes", station: 1),
            valve(back.zones[1].valveEntityId, name: "House", station: 2, open: true),
            valve(back.zones[2].valveEntityId, name: "Backyard", station: 3),
            valve(back.zones[3].valveEntityId, name: "Sidewalk", station: 4),
            program(back.zones[0].programEntityId, station: 1, days: [0, 1, 2, 3, 4, 5, 6], times: ["05:00", "19:00"], budget: 80, minutes: 10),
            program(back.zones[1].programEntityId, station: 2, days: [2, 4], times: ["06:00"], budget: 100, minutes: 15),
            program(back.zones[2].programEntityId, station: 3, days: [6], times: ["07:15"], budget: 120, minutes: 25, on: false),
            program(back.zones[3].programEntityId, station: 4, days: [], times: [], budget: 100, minutes: 5, on: false),
            history(back.zones[0].historyEntityId, start: "2026-10-11T12:00:00+00:00", minutes: 10),
            history(back.zones[1].historyEntityId, start: "2026-10-11T15:00:00+00:00", minutes: 15),
        ]
    }()
}
#endif
