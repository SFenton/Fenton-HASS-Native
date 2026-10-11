import HassCore
import HassDesign
import SwiftUI

/// Gallery page for room pages, Quick Links and the room grid on fixture state with a recording caller.
/// `FENTON_GALLERY_ROOM=<path>` opens a room at launch; `FENTON_GALLERY_QUICK_LINKS=1` opens Quick Links.
struct RoomsGallery: View {
    @State private var store: EntityStore
    @State private var recorder: GalleryServiceRecorder
    @State private var route: HomeRoute?
    @State private var showsQuickLinks: Bool
    @State private var pending: HomeRoute?

    init() {
        let environment = ProcessInfo.processInfo.environment
        let store = RoomsFixtures.store()
        _store = State(initialValue: store)
        _recorder = State(initialValue: GalleryServiceRecorder(store: store))
        _route = State(initialValue: environment["FENTON_GALLERY_ROOM"].flatMap { RoomsConfig.page(id: $0) == nil ? nil : .room($0) })
        _showsQuickLinks = State(initialValue: environment["FENTON_GALLERY_QUICK_LINKS"] == "1")
    }

    var body: some View {
        NavigationStack { list }
            .safeAreaInset(edge: .bottom) {
                // Journeys read what a control sent while a room is open.
                if route != nil && !MediaRemoteGallery.isClean {
                    Text("Last call: \(recorder.lastCall)")
                        .font(.caption2.monospaced())
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .background(.bar)
                        .accessibilityIdentifier("gallery.lastCall")
                }
            }
            .environment(store)
            .environment(\.roomServiceCaller, recorder)
            .environment(\.householdViewer, .stephen)
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
                if route == nil && !MediaRemoteGallery.isClean {
                    Text("Last call: \(recorder.lastCall)")
                        .font(.caption.monospaced())
                        .foregroundStyle(HassTokens.Ink.secondary)
                        .accessibilityIdentifier("gallery.lastCall")
                }
            }
        }
        .navigationTitle("Rooms")
        .sheet(isPresented: $showsQuickLinks, onDismiss: {
            route = pending
            pending = nil
        }) {
            QuickLinksSheet(caller: recorder) { pending = $0 }
        }
        .homeRouteDestination($route)
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

        // A lived-in evening: some lights on, one room occupied, one window open.
        add("light.living_room", "on", ["brightness": .number(180), "supported_color_modes": .array([.string("brightness")])])
        add("binary_sensor.living_room_occupancy_sensors", "on")
        add("binary_sensor.living_room_window_contact_sensor_contact", "on")
        add("climate.sleepypod_eight_pod_left_side", "heat_cool", ["hvac_action": .string("heating")])
        add("climate.sleepypod_eight_pod_right_side", "off", ["hvac_action": .string("off")])
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
        add(QuickLinks.sprinklersVisibilityEntityId, "on")
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
        return [:]
    }
}
