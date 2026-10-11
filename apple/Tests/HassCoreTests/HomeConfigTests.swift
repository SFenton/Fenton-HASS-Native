@testable import HassCore
import Testing

struct HomeConfigTests {
    private func chip(_ sheet: HomeConfig.ChipSheet) -> HomeConfig.StatusChip {
        HomeConfig.statusChips.first { $0.sheet == sheet }!
    }

    @Test func lightsSummaryCountsRoomGroupsOn() {
        let states: [String: EntityState] = [
            "light.lights": EntityState(entityId: "light.lights", state: "on"),
            "light.kitchen": EntityState(entityId: "light.kitchen", state: "on"),
            "light.office_light": EntityState(entityId: "light.office_light", state: "on"),
            "light.gym_light": EntityState(entityId: "light.gym_light", state: "off"),
        ]
        #expect(HomeConfig.summary(for: chip(.lights)) { states[$0] } == "2 on")
    }

    @Test func contactsSummaryCountsOpenMembers() {
        let states: [String: EntityState] = [
            "binary_sensor.contact_sensors": EntityState(
                entityId: "binary_sensor.contact_sensors",
                state: "on",
                attributes: ["entity_id": .array([.string("binary_sensor.front_door"), .string("binary_sensor.back_door")])]
            ),
            "binary_sensor.front_door": EntityState(entityId: "binary_sensor.front_door", state: "on"),
            "binary_sensor.back_door": EntityState(entityId: "binary_sensor.back_door", state: "off"),
        ]
        #expect(HomeConfig.summary(for: chip(.contacts)) { states[$0] } == "1 open")
    }

    @Test func unavailableChip() {
        #expect(HomeConfig.summary(for: chip(.security)) { _ in nil } == "Unavailable")
    }

    @Test func securitySummaryIsReadable() {
        let id = chip(.security).entityId
        let states = [id: EntityState(entityId: id, state: "armed_away")]
        #expect(HomeConfig.summary(for: chip(.security)) { states[$0] } == "Armed Away")
    }
}
