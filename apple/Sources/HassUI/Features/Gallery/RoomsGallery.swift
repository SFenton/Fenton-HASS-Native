#if DEBUG
import HassCore
import HassDesign
import SwiftUI

/// Gallery page for room pages, Quick Links and the room grid on fixture state with a recording caller.
/// `FENTON_GALLERY_ROOM=<path>` opens a room at launch; `FENTON_GALLERY_QUICK_LINKS=1` opens Quick Links.
struct RoomsGallery: View {
    @State private var store: EntityStore
    @State private var recorder: GalleryServiceRecorder
    @State private var caller: RoomsGalleryCaller
    @State private var route: HomeRoute?
    @State private var showsQuickLinks: Bool
    @State private var pending: HomeRoute?

    init() {
        let environment = ProcessInfo.processInfo.environment
        let store = RoomsFixtures.store()
        _store = State(initialValue: store)
        let recorder = GalleryServiceRecorder(store: store)
        _recorder = State(initialValue: recorder)
        _caller = State(initialValue: RoomsGalleryCaller(recorder: recorder, bedroom: BedroomGalleryRecorder(store: store)))
        _route = State(initialValue: environment["FENTON_GALLERY_ROOM"].flatMap { RoomsConfig.page(id: $0) == nil ? nil : .room($0) })
        _showsQuickLinks = State(initialValue: environment["FENTON_GALLERY_QUICK_LINKS"] == "1")
    }

    var body: some View {
        NavigationStack { list }
            .safeAreaInset(edge: .bottom) {
                // Journeys read what a control sent while a room is open.
                if route != nil && !GalleryEnvironment.isClean {
                    GalleryLastCall(text: recorder.lastCall, lineLimit: 2)
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .background(.bar)
                }
            }
            .environment(store)
            .environment(\.roomServiceCaller, caller)
            .environment(\.householdViewer, .stephen)
            // Pages are dark-styled (white ink): on the simulator's light appearance the room titles drew black
            // on the navy ground in screenshots.
            .preferredColorScheme(.dark)
    }

    private var list: some View {
        List {
            Section("Rooms") {
                ForEach(RoomsConfig.pages) { page in
                    Button(page.title) { route = .room(page.id) }
                        .accessibilityIdentifier("gallery.room.\(page.id)")
                }
            }
            Section {
                Button("Quick Links") { showsQuickLinks = true }
                    .accessibilityIdentifier("gallery.quickLinks")
            } footer: {
                if route == nil && !GalleryEnvironment.isClean {
                    GalleryLastCall(text: recorder.lastCall)
                }
            }
        }
        .navigationTitle("Rooms")
        .sheet(isPresented: $showsQuickLinks, onDismiss: {
            route = pending
            pending = nil
        }) {
            QuickLinksSheet(caller: caller) { pending = $0 }
        }
        .homeRouteDestination($route)
    }
}

/// The gallery's service caller: records every call for the "Last call" line, and answers calls that return a
/// response (wake light, Solo Trip) like Home Assistant through the bedroom gallery's recorder, so the Master
/// Bedroom's wake-light and bed sheets open here too.
@MainActor
final class RoomsGalleryCaller: HassServiceResponding {
    let recorder: GalleryServiceRecorder
    let bedroom: BedroomGalleryRecorder

    init(recorder: GalleryServiceRecorder, bedroom: BedroomGalleryRecorder) {
        self.recorder = recorder
        self.bedroom = bedroom
    }

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        try await recorder.callService(domain, service, data: data)
    }

    func callServiceWithResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        try? await recorder.callService(domain, service, data: data)
        return try await bedroom.callServiceWithResponse(domain, service, data: data)
    }
}

/// Synthetic states for every room card, group, counter and Quick Links tile (not a copy of the live house).
enum RoomsFixtures {
    @MainActor static func store() -> EntityStore {
        let store = EntityStore()
        store.replaceAll(states, freshness: .live)
        return store
    }

    static let states: [EntityState] = {
        var byId: [String: EntityState] = [:]
        func add(_ id: String, _ state: String, _ attributes: [String: JSONValue] = [:]) {
            if byId[id] == nil { byId[id] = EntityState(entityId: id, state: state, attributes: attributes) }
        }
        for state in MediaRemoteFixtures.states { byId[state.entityId] = state }
        // Device sheets wired from room cards: the room device lane's fixtures (fans off and unlocked).
        let devices = BathroomFanConfig.all.flatMap { RoomDeviceFixture.fanStates($0, power: "off", locked: false, pending: false, now: Date()) }
            + AirPurifierConfig.all.flatMap { RoomDeviceFixture.purifierStates($0, mode: "Auto", percentage: 33) }
            + RoomDeviceFixture.grillStates
        for state in devices { byId[state.entityId] = state }
        // Wake light and both bed sides with schedules (the bedroom lane's fixtures).
        for state in BedroomFixtures.states(.default) { byId[state.entityId] = state }

        // A lived-in evening: some lights on, one room occupied, one window open.
        add("light.living_room", "on", ["brightness": .number(180), "supported_color_modes": .array([.string("brightness")])])
        add("binary_sensor.living_room_occupancy_sensors", "on")
        add("binary_sensor.living_room_window_contact_sensor_contact", "on")
        // The live pods sit in heat mode. One heats (filled); one has nothing running, so it draws its off face with
        // the Heating glyph (`ThermostatTileFace`). The bedroom fixtures' own attributes stay.
        func setPod(_ id: String, state: String, action: String) {
            var attributes = byId[id]?.attributes ?? [:]
            attributes["hvac_action"] = .string(action)
            byId[id] = EntityState(entityId: id, state: state, attributes: attributes)
        }
        setPod("climate.sleepypod_eight_pod_left_side", state: "heat", action: "heating")
        setPod("climate.sleepypod_eight_pod_right_side", state: "heat", action: "idle")
        add(RoomsConfig.WakeLight.statusEntityId, "6:45 AM")
        add(RoomsConfig.dishwasherProgramEntityId, "Eco 50°C")

        let groups = RoomsConfig.pages.flatMap { page in
            [RoomGroups.lights(room: page.title), RoomGroups.climate(room: page.title),
             RoomGroups.occupancy(room: page.title), RoomGroups.contacts(room: page.title)].compactMap { $0 }
        } + RoomGroups.allContacts
        for group in groups {
            for item in group.items { add(item.entityId, defaultState(item.entityId), defaultAttributes(item.entityId)) }
        }
        for card in RoomsConfig.pages.flatMap(\.allCards) {
            for id in [card.entityId, card.modalEntityId].compactMap({ $0 }) + card.subtitleEntityIds + card.modalItems.map(\.entityId) {
                add(id, defaultState(id), defaultAttributes(id))
            }
            if card.kind == .air { add(RoomFormat.aqiEntityId(forPM25: card.modalEntityId ?? card.entityId), "38") }
            if let alternate = card.alternate { add(alternate.whenEntityId, "off"); add(alternate.entityId, defaultState(alternate.entityId)) }
        }
        for (index, item) in RoomNavigation.items.enumerated() {
            add(item.accessCounterEntityId, "\([4, 1, 2, 9, 7, 0, 12, 5, 1, 3][index % 10])")
        }
        add(QuickLinks.securityEntityId, "armed_home")
        add(SprinklersConfig.visibilityEntityId, "on")
        add(QuickLinks.totalItemsEntityId, "42")
        add(QuickLinks.expiringSoonEntityId, "3")
        add(RoomsConfig.Groceries.listEntityId, "5")
        return Array(byId.values)
    }()

    private static func defaultState(_ id: String) -> String {
        let domain = id.prefix { $0 != "." }
        switch domain {
        case "light", "switch", "input_boolean", "fan": return "off"
        case "binary_sensor": return "off"
        case "cover": return "open"
        case "vacuum": return "docked"
        case "media_player": return "off"
        case "select": return "Auto"
        case "climate": return "off"
        case "input_text":
            if id.hasSuffix("_climate_range") { return "68–72°F" }
            if id.hasSuffix("_power_state") { return "Off" }
            return "—"
        case "sensor":
            if id.contains("temperature") { return "70.4" }
            if id.contains("humidity") { return "44" }
            if id.contains("pm2_5") { return "6" }
            return "Ready"
        default: return "off"
        }
    }

    private static func defaultAttributes(_ id: String) -> [String: JSONValue] {
        if id.hasPrefix("sensor."), id.contains("temperature") { return ["unit_of_measurement": .string("°F")] }
        if id.hasPrefix("sensor."), id.contains("humidity") { return ["unit_of_measurement": .string("%")] }
        if id.hasPrefix("sensor."), id.contains("pm2_5") { return ["unit_of_measurement": .string("µg/m³")] }
        if id.hasPrefix("light.") { return ["supported_color_modes": .array([.string("brightness")])] }
        // Vents report how far they are open, which their tiles show.
        if id.hasPrefix("cover.") { return ["current_position": .number(60)] }
        return [:]
    }
}
#endif
