import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// Hosted renders of the room overview sheets and room detail pages, and the actions their tiles hand out.
@MainActor
struct RoomOverviewViewTests {
    /// A store where some lights, presence sensors and contacts are active, with color helpers and readings.
    private func store() -> EntityStore {
        let store = EntityStore()
        store.apply([
            EntityState(entityId: "light.kitchen", state: "on", attributes: ["brightness": .number(200)]),
            EntityState(entityId: "light.kitchen_table_light", state: "on", attributes: ["brightness": .number(128)]),
            EntityState(entityId: "light.gym_light", state: "off"),
            EntityState(entityId: "switch.upper_entryway_light_switch_top", state: "on"),
            EntityState(entityId: "binary_sensor.gym_presence_sensor_presence", state: "on"),
            EntityState(entityId: "binary_sensor.office_pc_window_sensor_contact", state: "on"),
            EntityState(entityId: "input_text.office_climate_range", state: "70.1 - 72.4°F"),
            EntityState(entityId: "input_text.office_climate_color", state: "rgba(0, 200, 120, 1)"),
            EntityState(entityId: "sensor.office_presence_sensor_temperature", state: "71.3", attributes: ["unit_of_measurement": .string("°F")]),
            EntityState(entityId: "cover.office_vent_vent", state: "open"),
            EntityState(entityId: "input_text.living_room_aqi_color", state: "#33cc66"),
            EntityState(entityId: "sensor.living_room_air_purifier_air_quality_index", state: "12"),
        ])
        return store
    }

    private func group(_ kind: RoomOverviewKind, _ room: String) -> RoomGroup {
        RoomOverview.groups(kind).first { $0.room == room }!
    }

    @Test func everyOverviewSheetRenders() {
        let store = store()
        for kind in RoomOverviewKind.allCases {
            let view = RoomOverviewSheet(kind: kind).environment(store).frame(width: 402, height: 874)
            #expect(ImageRenderer(content: view).cgImage != nil, "\(kind)")
        }
    }

    @Test func everyDetailPageRenders() {
        let store = store()
        let pages: [(RoomOverviewKind, String)] = [(.lights, "Kitchen"), (.lights, "Entryway"), (.climate, "Office"),
                                                   (.occupancy, "Gym"), (.contacts, "Office")]
        for (kind, room) in pages {
            let view = NavigationStack { RoomGroupDetailPage(kind: kind, group: group(kind, room)) }
                .environment(store).frame(width: 402, height: 874)
            #expect(ImageRenderer(content: view).cgImage != nil, "\(kind) \(room)")
        }
        // Air Quality has no detail page; its content is empty.
        let empty = RoomGroupDetail(kind: .airQuality, group: group(.contacts, "Office"), read: { _ in nil }) { _ in }
        #expect(ImageRenderer(content: empty.frame(width: 402, height: 20)).cgImage != nil)
    }

    /// Room tiles hand their room to the sheet, which pushes it.
    @Test func roomTilesSelectTheirRoom() {
        let store = store()
        var selected: [String] = []
        let grid = RoomOverviewGrid(kind: .occupancy) { selected.append($0.room) }.environment(store)
        _ = ImageRenderer(content: grid.frame(width: 402)).cgImage
        let tile = RoomOverviewTile(kind: .occupancy, group: group(.occupancy, "Gym")) { selected.append("Gym") }
        _ = ImageRenderer(content: tile.environment(store).frame(width: 170)).cgImage
        tile.action()
        #expect(selected == ["Gym"])
    }

    @Test func styleSymbolsAndTints() {
        #expect(RoomOverviewStyle.contactSymbol(window: true, open: true) == SymbolMap.symbol(for: "mdi:window-open"))
        #expect(RoomOverviewStyle.contactSymbol(window: false, open: false) == SymbolMap.symbol(for: "mdi:door"))
        for kind in RoomOverviewKind.allCases { _ = RoomOverviewStyle.tint(kind) }
    }

    /// Direction G faces: lights, occupancy and doors fill while active; climate and air quality always stay dark.
    @Test func onlyStatefulKindsFill() {
        for kind in [RoomOverviewKind.lights, .occupancy, .contacts] {
            #expect(RoomOverviewStyle.isFilled(kind, active: true))
            #expect(!RoomOverviewStyle.isFilled(kind, active: false))
        }
        for kind in [RoomOverviewKind.climate, .airQuality] {
            #expect(!RoomOverviewStyle.isFilled(kind, active: true))
        }
    }

    /// Quick Links glyphs take their page's colour family, and Security System follows the alarm mode.
    @Test func quickLinkFamilies() {
        func link(_ id: String) -> QuickLink { QuickLinks.items.first { $0.id == id }! }
        #expect(QuickLinkTile.family(link("rooms"), alarmState: nil) == .neutral)
        #expect(QuickLinkTile.family(link("food"), alarmState: nil) == .neutral)
        #expect(QuickLinkTile.family(link("vacuums"), alarmState: nil) == .cleaning)
        #expect(QuickLinkTile.family(link("media"), alarmState: nil) == .media)
        #expect(QuickLinkTile.family(link("custom-lights"), alarmState: nil) == .lights)
        #expect(QuickLinkTile.family(link("sprinklers"), alarmState: nil) == .water)
        #expect(QuickLinkTile.family(link("security-system"), alarmState: "armed_home") == .securityHome)
        #expect(QuickLinkTile.family(link("security-system"), alarmState: "arming") == .neutral)
    }
}
