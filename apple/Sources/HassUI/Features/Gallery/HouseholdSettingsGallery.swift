import HassCore
import HassDesign
import Observation
import SwiftUI

/// Gallery page for the household Settings pages on fixture state with a recording service caller, so
/// journeys tap real toggles and presence modes without touching the house.
///
/// `FENTON_GALLERY_HOUSEHOLD=<page>` (`admin`, `specialDeviceModes`, `guests`, `machE`) opens a page at launch;
/// `FENTON_GALLERY_UNAVAILABLE=1` makes every entity unavailable; `FENTON_GALLERY_CLEAN=1` hides the last-call line.
struct HouseholdSettingsGallery: View {
    @State private var store: EntityStore
    @State private var recorder: HouseholdGalleryRecorder
    @State private var open: HouseholdSettingsPage?

    init() {
        let environment = ProcessInfo.processInfo.environment
        let store = HouseholdSettingsFixtures.store(unavailable: environment["FENTON_GALLERY_UNAVAILABLE"] == "1")
        _store = State(initialValue: store)
        _recorder = State(initialValue: HouseholdGalleryRecorder(store: store))
        _open = State(initialValue: environment["FENTON_GALLERY_HOUSEHOLD"].flatMap(HouseholdSettingsPage.init(rawValue:)))
    }

    var body: some View {
        List {
            Section {
                ForEach(HouseholdSettingsPage.allCases) { page in
                    Button { open = page } label: {
                        SettingsLinkRow(title: page.rowTitle, subtitle: page.subtitle, symbol: page.symbol)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.topic.\(page.rawValue)")
                }
            } footer: {
                if !MediaRemoteGallery.isClean { lastCall }
            }
        }
        .navigationTitle("Household Settings")
        .navigationDestination(item: $open) { page in
            HouseholdSettingsPageView(page: page, store: store, caller: recorder)
                .safeAreaInset(edge: .bottom) {
                    if !MediaRemoteGallery.isClean { lastCall.padding(.horizontal).padding(.vertical, 4).background(.bar) }
                }
        }
    }

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

/// Records service calls and echoes them into the fixture store after a short delay, like Home Assistant.
@MainActor
@Observable
final class HouseholdGalleryRecorder: HassServiceCalling {
    private(set) var lastCall = "None"
    @ObservationIgnored private let store: EntityStore

    init(store: EntityStore) { self.store = store }

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        lastCall = GalleryServiceRecorder.describe(domain, service, data)
        try? await Task.sleep(for: .milliseconds(400))
        echo(domain, service, data)
    }

    private func echo(_ domain: String, _ service: String, _ data: [String: any Sendable]) {
        guard let target = data["entity_id"] as? String, var entity = store.value(target) else { return }
        switch (domain, service) {
        case (_, "turn_on"): entity.state = "on"
        case (_, "turn_off"): entity.state = "off"
        case ("presence_based_lighting", "set_automation_state"):
            let mode = data["state"] as? String ?? "active"
            entity.state = mode == "off" ? "off" : "on"
            entity.attributes["automation_state"] = .string(mode)
        default: return
        }
        store.apply([entity])
    }
}

/// Synthetic states for the gallery and hosted tests (not a copy of the live house).
enum HouseholdSettingsFixtures {
    /// A store with every household entity, in a spread of states.
    static func store(unavailable: Bool = false) -> EntityStore {
        let store = EntityStore()
        store.replaceAll(states(unavailable: unavailable))
        return store
    }

    static func states(unavailable: Bool = false) -> [EntityState] {
        typealias Config = HouseholdSettingsConfig
        let admin = Config.Admin.self
        if unavailable {
            let ids = Config.toggleEntityIds + admin.presenceRooms.map(\.presenceEntityId) + Config.MachE.tiles.map(\.entityId)
            return ids.map { EntityState(entityId: $0, state: "unavailable") }
        }
        var states: [EntityState] = []
        func add(_ id: String, _ state: String, _ attributes: [String: JSONValue] = [:]) {
            states.append(EntityState(entityId: id, state: state, attributes: attributes))
        }
        add(admin.securityTiles[0].entityId, "on")
        add(admin.relayControlEntityId, "on")
        add(admin.showSpecificTiles[0].entityId, "off")
        add(admin.showSpecificTiles[1].entityId, "on")
        add(Config.SpecialDeviceModes.highAqiTile.entityId, "off")
        for (index, tile) in Config.Guests.tiles.enumerated() { add(tile.entityId, index == 0 ? "on" : "off") }
        // Cycle the rooms through every mode, with one unavailable.
        let modes: [(String, [String: JSONValue])] = [
            ("on", ["automation_state": .string("active")]),
            ("off", [:]),
            ("on", ["automation_state": .string("paused")]),
            ("on", ["automation_quieted": .bool(true)]),
        ]
        for (index, room) in admin.presenceRooms.enumerated() {
            if room.title == "Upper Deck" {
                add(room.presenceEntityId, "unavailable")
            } else {
                let mode = modes[index % modes.count]
                add(room.presenceEntityId, mode.0, mode.1)
            }
            add(room.autoReenableEntityId, index.isMultiple(of: 3) ? "off" : "on")
        }
        let mache = Config.MachE.tiles
        add(mache[0].entityId, "ChargingAC")
        add(mache[1].entityId, "locked")
        add(mache[2].entityId, "off")
        add(mache[3].entityId, "heated_low")
        add(mache[4].entityId, "72")
        return states
    }
}
