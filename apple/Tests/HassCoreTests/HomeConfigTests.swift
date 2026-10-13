@testable import HassCore
import Testing

struct HomeConfigTests {
    private func chip(_ sheet: HomeConfig.ChipSheet) -> HomeConfig.StatusChip {
        HomeConfig.statusChips.first { $0.sheet == sheet }!
    }

    /// Lights count each room light once (web `ROOM_LIGHT_ENTITY_IDS`), not the room groups.
    @Test func lightsSummaryCountsLightsOn() {
        let states: [String: EntityState] = [
            "light.lights": EntityState(entityId: "light.lights", state: "on"),
            "light.kitchen": EntityState(entityId: "light.kitchen", state: "on"),
            "light.kitchen_table_light": EntityState(entityId: "light.kitchen_table_light", state: "on"),
            "light.kitchen_sink_light": EntityState(entityId: "light.kitchen_sink_light", state: "on"),
            "light.master_bedroom_closet_light": EntityState(entityId: "light.master_bedroom_closet_light", state: "on"),
            "light.gym_light": EntityState(entityId: "light.gym_light", state: "off"),
        ]
        #expect(HomeConfig.summary(for: chip(.lights)) { states[$0] } == "3 On")
        #expect(HomeConfig.summary(for: chip(.lights)) { _ in nil } == "All Off")
    }

    /// Contact Sensors counts the rooms' sensors (web `ROOM_CONTACT_ENTITY_IDS`).
    @Test func contactsSummaryCountsOpenSensors() {
        let states: [String: EntityState] = [
            "binary_sensor.front_door_contact_sensor_contact": EntityState(entityId: "binary_sensor.front_door_contact_sensor_contact", state: "on"),
            "binary_sensor.gym_window_contact_sensor_contact": EntityState(entityId: "binary_sensor.gym_window_contact_sensor_contact", state: "off"),
        ]
        #expect(HomeConfig.summary(for: chip(.contacts)) { states[$0] } == "1 Open")
        #expect(HomeConfig.summary(for: chip(.contacts)) { _ in nil } == "All Closed")
    }

    @Test func occupancyReadsDetectedOrClear() {
        let id = chip(.occupancy).entityId
        #expect(HomeConfig.summary(for: chip(.occupancy)) { [id: EntityState(entityId: id, state: "on")][$0] } == "Detected")
        #expect(HomeConfig.summary(for: chip(.occupancy)) { [id: EntityState(entityId: id, state: "off")][$0] } == "Clear")
    }

    @Test func airQualityJoinsRanges() {
        let states: [String: EntityState] = [
            "input_text.all_aqi_range": EntityState(entityId: "input_text.all_aqi_range", state: "12 - 30"),
            "input_text.all_pm25_range": EntityState(entityId: "input_text.all_pm25_range", state: "1 - 4"),
        ]
        #expect(HomeConfig.summary(for: chip(.airQuality)) { states[$0] } == "AQI 12 - 30 · PM2.5 1 - 4")
        #expect(HomeConfig.summary(for: chip(.airQuality)) { _ in nil } == "AQI Unavailable · PM2.5 Unavailable")
    }

    @Test func climateShowsItsText() {
        let id = chip(.climate).entityId
        #expect(HomeConfig.summary(for: chip(.climate)) { [id: EntityState(entityId: id, state: "68 - 72°F")][$0] } == "68 - 72°F")
    }

    /// Six chips in web order; every chip but Security opens a room overview.
    @Test func chipsMatchTheWebRail() {
        #expect(HomeConfig.statusChips.map(\.title) == ["Lights", "Security", "Climate", "Occupancy", "Contact Sensors", "Air Quality"])
        #expect(HomeConfig.ChipSheet.allCases.filter { $0.overview == nil } == [.security])
        #expect(chip(.airQuality).colorEntityId == "input_text.all_aqi_color")
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
