@testable import HassCore
import Testing

/// Home's room overview sheets (web `AtAGlancePage.tsx` `LightsSheet`, `ClimateSheet`, `OccupancySheet`,
/// `ContactSheet`, `AirQualitySheet`).
struct RoomOverviewTests {
    private func states(_ values: [(String, String)], attributes: [String: [String: JSONValue]] = [:]) -> RoomOverview.Read {
        let map = Dictionary(uniqueKeysWithValues: values.map { ($0.0, EntityState(entityId: $0.0, state: $0.1, attributes: attributes[$0.0] ?? [:])) })
        return { map[$0] }
    }

    private func group(_ kind: RoomOverviewKind, _ room: String) -> RoomGroup {
        RoomOverview.groups(kind).first { $0.room == room }!
    }

    // MARK: Data

    @Test func groupsFollowTheWebLists() {
        #expect(RoomOverview.groups(.lights).count == 17)
        #expect(RoomOverview.groups(.lights).map(\.room).suffix(2) == ["Entryway", "Driveway"])
        #expect(RoomOverview.groups(.lights)[3].room == "Master Bedroom Closet")
        #expect(RoomOverview.groups(.climate).count == 14)
        #expect(RoomOverview.groups(.occupancy).count == 15)
        #expect(RoomOverview.groups(.contacts).count == 11)
        #expect(RoomOverview.groups(.airQuality).isEmpty)
        #expect(RoomOverview.airQualityRooms.count == 6)
        // The closet light sits in two groups but counts once.
        #expect(RoomOverview.lightEntityIds.filter { $0 == "light.master_bedroom_closet_light" }.count == 1)
        #expect(RoomOverview.contactEntityIds.count == 12)
    }

    @Test func climateGroupsCarryTheirColorHelpers() {
        let living = group(.climate, "Living Room")
        #expect(living.colorEntityId == "input_text.living_room_climate_color")
        #expect(living.items.first?.colorEntityId == "input_text.living_room_back_wall_climate_color")
        #expect(living.items.last?.colorEntityId == nil, "Vents have no color helper")
        #expect(group(.climate, "Master Bedroom").items[1].colorEntityId == "input_text.master_bedroom_bed_climate_color")
    }

    // MARK: Titles and sections

    @Test func lightsTitleCountsLightsOn() {
        #expect(RoomOverview.sheetTitle(.lights) { _ in nil } == "Lights (All Off)")
        let read = states([("light.kitchen_table_light", "on"), ("light.gym_light", "on")])
        #expect(RoomOverview.sheetTitle(.lights, read: read) == "Lights (2 On)")
        #expect(RoomOverview.sheetTitle(.climate, read: read) == "Climate")
        #expect(RoomOverview.sheetTitle(.occupancy, read: read) == "Occupancy")
        #expect(RoomOverview.sheetTitle(.contacts, read: read) == "Contact Sensors")
        #expect(RoomOverview.sheetTitle(.airQuality, read: read) == "Air Quality")
    }

    @Test func lightsSplitOnThenOff() {
        let read = states([("light.kitchen_table_light", "on"), ("light.theater_room", "on")])
        let sections = RoomOverview.sections(.lights, read: read)
        #expect(sections.map(\.title) == ["Lights On", "Lights Off"])
        #expect(sections[0].groups.map(\.room) == ["Kitchen", "Theater Room"])
        #expect(sections[1].groups.count == 15)
        // Everything off drops the empty "Lights On" section.
        #expect(RoomOverview.sections(.lights) { _ in nil }.map(\.title) == ["Lights Off"])
    }

    @Test func occupancySplitsOccupiedThenClear() {
        let read = states([("binary_sensor.gym_presence_sensor_presence", "on")])
        let sections = RoomOverview.sections(.occupancy, read: read)
        #expect(sections.map(\.title) == ["Occupied", "Clear"])
        #expect(sections[0].groups.map(\.room) == ["Gym"])
    }

    @Test func climateAndContactsListEveryRoom() {
        #expect(RoomOverview.sections(.climate) { _ in nil }.map(\.title) == ["Rooms"])
        #expect(RoomOverview.sections(.contacts) { _ in nil }.first?.groups.count == 11)
        #expect(RoomOverview.sections(.airQuality) { _ in nil }.first?.groups.isEmpty == true)
    }

    @Test func detailTitlesMatchWebGroupTitles() {
        #expect(RoomOverview.detailTitle(.lights, group(.lights, "Living Room")) == "Living Room Lights")
        #expect(RoomOverview.detailTitle(.lights, group(.lights, "Master Bedroom Closet")) == "Master Bedroom Closet Light")
        #expect(RoomOverview.detailTitle(.climate, group(.climate, "Office")) == "Office Climate")
        #expect(RoomOverview.detailTitle(.occupancy, group(.occupancy, "Hallway")) == "Hallway Occupancy")
        #expect(RoomOverview.detailTitle(.contacts, group(.contacts, "Entryway")) == "Entryway Contact Sensors")
        #expect(RoomOverview.detailTitle(.airQuality, group(.contacts, "Entryway")) == "Entryway")
    }

    // MARK: Subtitles

    @Test func lightSubtitles() {
        let living = group(.lights, "Living Room")
        let gym = group(.lights, "Gym")
        #expect(RoomOverview.lightSubtitle(living, read: states([("light.living_room_front_left_light", "on"), ("light.living_room_back_left_light", "on")])) == "2 On")
        #expect(RoomOverview.lightSubtitle(gym, read: states([("light.gym_light", "on")])) == "On")
        #expect(RoomOverview.lightSubtitle(gym) { _ in nil } == "Off")
        #expect(RoomOverview.lightSubtitle(living, read: states([("light.living_room", "unavailable")])) == "Unavailable")
        #expect(RoomOverview.isActive(.lights, living, read: states([("light.living_room", "on")])))
        #expect(!RoomOverview.isActive(.lights, living) { _ in nil })
        #expect(RoomOverview.cardSubtitle(.lights, gym, read: states([("light.gym_light", "on")])) == "On")
    }

    @Test func occupancySubtitles() {
        let living = group(.occupancy, "Living Room")
        let read = states([("binary_sensor.living_room_bar_presence_sensor_presence", "on")])
        #expect(RoomOverview.cardSubtitle(.occupancy, living, read: read) == "Occupied")
        #expect(RoomOverview.cardSubtitle(.occupancy, living) { _ in nil } == "Not Occupied")
        #expect(RoomOverview.detailSubtitle(.occupancy, living, read: read) == "1 sensor occupied")
        #expect(RoomOverview.detailSubtitle(.occupancy, living) { _ in nil } == "0 sensors occupied")
    }

    @Test func contactSubtitles() {
        let office = group(.contacts, "Office")
        let read = states([("binary_sensor.office_pc_window_sensor_contact", "on")])
        #expect(RoomOverview.cardSubtitle(.contacts, office, read: read) == "1 Window Open")
        #expect(RoomOverview.detailSubtitle(.contacts, office) { _ in nil } == "All Windows Closed")
        #expect(RoomOverview.isActive(.contacts, office, read: read))
        #expect(RoomOverview.isWindowGroup(office))
        #expect(!RoomOverview.isWindowGroup(group(.contacts, "Entryway")))
        #expect(RoomOverview.contactCountSummary(0) == "All Closed")
        #expect(RoomOverview.openContactCount(read: read) == 1)
    }

    @Test func climateSubtitlesPreferTheRangeHelper() {
        let office = group(.climate, "Office")
        #expect(RoomOverview.cardSubtitle(.climate, office, read: states([("input_text.office_climate_range", "70.06 - 72.49°F")])) == "70.0 - 72.4°F")
        let sensors = states([
            ("sensor.office_presence_sensor_temperature", "71.27"), ("sensor.office_closet_presence_sensor_temperature", "69.9"),
        ], attributes: [
            "sensor.office_presence_sensor_temperature": ["unit_of_measurement": .string("°F")],
            "sensor.office_closet_presence_sensor_temperature": ["unit_of_measurement": .string("°F")],
        ])
        #expect(RoomOverview.climateSubtitle(office, read: sensors) == "69.9°F - 71.2°F")
        let one = states([("sensor.office_presence_sensor_temperature", "71.0")])
        #expect(RoomOverview.climateSubtitle(office, read: one) == "71.0")
        #expect(RoomOverview.climateSubtitle(office) { _ in nil } == "4 sensors")
        #expect(RoomOverview.normalizedRange("unknown") == nil)
        #expect(RoomOverview.normalizedRange(nil) == nil)
        #expect(RoomOverview.normalizedRange("-3.25 to 4") == "-3.2 to 4.0")
    }

    @Test func climateTextAndColors() {
        let sensor = EntityState(entityId: "sensor.x", state: "71.29", attributes: ["unit_of_measurement": .string("°F")])
        #expect(RoomOverview.climateText(sensor) == "71.2°F")
        #expect(RoomOverview.climateText(EntityState(entityId: "sensor.x", state: "unavailable")) == "Unavailable")
        #expect(RoomOverview.climateText(EntityState(entityId: "cover.vent", state: "open")) == "Open")
        #expect(RoomOverview.climateText(nil) == "Unavailable")
        let fallback = RoomColor(1, 2, 3)
        #expect(RoomOverview.climateColor(EntityState(entityId: "cover.v", state: "open"), colorEntity: nil, fallback: fallback) == RoomColor(30, 136, 229))
        #expect(RoomOverview.climateColor(EntityState(entityId: "cover.v", state: "closed"), colorEntity: nil, fallback: fallback) == RoomColor(128, 128, 128))
        let helper = EntityState(entityId: "input_text.c", state: "rgba(10, 20, 30, 0.5)")
        #expect(RoomOverview.climateColor(sensor, colorEntity: helper, fallback: fallback) == RoomColor(10, 20, 30))
        #expect(RoomOverview.climateColor(EntityState(entityId: "sensor.x", state: "50"), colorEntity: nil, fallback: fallback) == RoomColor(0, 110, 255))
        #expect(RoomOverview.climateColor(nil, colorEntity: nil, fallback: fallback) == fallback)
    }

    @Test func temperatureGradientInterpolates() {
        #expect(RoomOverview.colorFromTemperature(nil) == nil)
        #expect(RoomOverview.colorFromTemperature(20) == RoomColor(0, 110, 255))
        #expect(RoomOverview.colorFromTemperature(99) == RoomColor(255, 0, 0))
        #expect(RoomOverview.colorFromTemperature(71) == RoomColor(128, 208, 60))
    }

    @Test func cssColorsParse() {
        #expect(RoomOverview.colorFromRgba("rgb(1, 2, 3)") == RoomColor(1, 2, 3))
        #expect(RoomOverview.colorFromRgba("blue") == nil)
        #expect(RoomOverview.colorFromRgba(nil) == nil)
        #expect(RoomOverview.colorFromCss("#ff8000") == RoomColor(255, 128, 0))
        #expect(RoomOverview.colorFromCss("RGBA(4, 5, 6, 1)") == RoomColor(4, 5, 6))
        #expect(RoomOverview.colorFromCss("#ff80") == nil)
        #expect(RoomOverview.colorFromCss(nil) == nil)
    }

    // MARK: Colors and details

    @Test func cardColorsUseRoomColors() {
        let read: RoomOverview.Read = { _ in nil }
        #expect(RoomOverview.cardColor(.lights, group(.lights, "Gym"), read: read) == RoomOverview.lightOnColor)
        #expect(RoomOverview.cardColor(.occupancy, group(.occupancy, "Gym"), read: read) == RoomColor(213, 117, 26))
        #expect(RoomOverview.cardColor(.contacts, group(.contacts, "Garage"), read: read) == RoomColor(223, 12, 12))
        #expect(RoomOverview.cardColor(.climate, group(.climate, "Gym"), read: read) == RoomColor(213, 117, 26))
        let tinted = states([("input_text.gym_climate_color", "rgb(9, 8, 7)")])
        #expect(RoomOverview.cardColor(.climate, group(.climate, "Gym"), read: tinted) == RoomColor(9, 8, 7))
        let noRoom = RoomGroup("Nowhere", [])
        #expect(RoomOverview.cardColor(.occupancy, noRoom, read: read) == RoomColor(46, 180, 120))
        #expect(RoomOverview.cardColor(.contacts, noRoom, read: read) == RoomColor(220, 92, 68))
        #expect(RoomOverview.cardColor(.climate, noRoom, read: read) == RoomColor(25, 84, 130))
        #expect(RoomOverview.cardColor(.airQuality, noRoom, read: read) == RoomColor(0, 150, 136))
        #expect(RoomOverview.roomIcon("Gym") == "mdi:dumbbell")
    }

    @Test func detailSectionsHeadTheirTiles() {
        #expect(RoomOverview.detailSections(.lights, group(.lights, "Gym")).map(\.title) == ["Light"])
        #expect(RoomOverview.detailSections(.lights, group(.lights, "Kitchen")).map(\.title) == ["Lights"])
        #expect(RoomOverview.detailSections(.climate, group(.climate, "Living Room")).map(\.title) == ["Temperature Sensors", "Vents"])
        #expect(RoomOverview.detailSections(.climate, group(.climate, "Gym")).map(\.title) == ["Temperature Sensors", "Vent"])
        #expect(RoomOverview.detailSections(.climate, group(.climate, "Entryway")).map(\.title) == ["Temperature Sensor"])
        #expect(RoomOverview.detailSections(.occupancy, group(.occupancy, "Gym")).map(\.title) == ["Occupancy Sensor"])
        #expect(RoomOverview.detailSections(.occupancy, group(.occupancy, "Office"), showsHeadings: false).map(\.title) == [nil])
        #expect(RoomOverview.detailSections(.contacts, group(.contacts, "Office")).map(\.title) == ["Contact Sensors"])
        #expect(RoomOverview.detailSections(.contacts, group(.contacts, "Office"), showsHeadings: false).first?.title == nil)
        #expect(RoomOverview.detailSections(.airQuality, group(.contacts, "Office")).isEmpty)
    }

    @Test func multiLightRoomsShowTheirGroupLight() {
        #expect(RoomOverview.groupLightEntityId(group(.lights, "Kitchen")) == "light.kitchen")
        #expect(RoomOverview.groupLightEntityId(group(.lights, "Gym")) == nil)
        #expect(RoomOverview.groupLightEntityId(RoomGroup("X", entityId: "switch.x", [RoomGroupItem("a", "switch.a"), RoomGroupItem("b", "switch.b")])) == nil)
    }

    @Test func airQualityColorsAndSummary() {
        let room = RoomOverview.airQualityRooms[0]
        #expect(RoomOverview.airQualityColor(room, read: states([(room.colorEntityId, "#00ff00")])) == RoomColor(0, 255, 0))
        #expect(RoomOverview.airQualityColor(room) { _ in nil } == RoomColor(0, 150, 136))
    }
}
