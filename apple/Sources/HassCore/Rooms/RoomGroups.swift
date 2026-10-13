import Foundation

/// One entity in a room's lights, climate, occupancy or contact group (web `EntityButtonConfig`).
public struct RoomGroupItem: Hashable, Sendable, Identifiable {
    public var title: String
    public var entityId: String
    /// How many physical sensors one contact entity stands for (two street windows on one sensor).
    public var contactCount: Int
    /// The household member a nightstand belongs to.
    public var resident: HouseholdResident?
    /// A text helper holding this sensor's `rgba()` card color (climate sensors, web `EntityButtonConfig.colorEntityId`).
    public var colorEntityId: String?
    public var id: String { entityId + title }

    public init(_ title: String, _ entityId: String, contactCount: Int = 1, resident: HouseholdResident? = nil, color colorEntityId: String? = nil) {
        self.title = title
        self.entityId = entityId
        self.contactCount = contactCount
        self.resident = resident
        self.colorEntityId = colorEntityId
    }

    /// "Your Nightstand" for the owner, "Steph Nightstand" for anyone else signed in (web `LightsSheet`).
    public func title(for viewer: HouseholdResident?) -> String {
        guard let viewer, let resident else { return title }
        return resident == viewer ? "Your Nightstand" : "\(resident.name) Nightstand"
    }
}

/// A room's entity group, keyed by the room's title (web `LIGHT_GROUPS`, `CLIMATE_GROUPS`, `OCCUPANCY_GROUPS`,
/// `CONTACT_GROUPS`, `ha-sfenton-react-dash@9ac2a46:src/constants/atAGlance.ts:343-760`).
public struct RoomGroup: Hashable, Sendable {
    /// The room this group belongs to (the web title without its " Lights" / " Climate" suffix).
    public var room: String
    /// The group's own entity: a light group, or the climate range text.
    public var entityId: String?
    /// A text helper holding the room's `rgba()` climate color (web `EntityGroupConfig.colorEntityId`).
    public var colorEntityId: String?
    public var items: [RoomGroupItem]

    public init(_ room: String, entityId: String? = nil, colorEntityId: String? = nil, _ items: [RoomGroupItem]) {
        self.room = room
        self.entityId = entityId
        self.colorEntityId = colorEntityId
        self.items = items
    }
}

/// Per-room groups the generic room sheets list.
public enum RoomGroups {
    typealias I = RoomGroupItem

    /// The lights a room's Lights sheet shows (web `roomLightGroup`).
    public static func lights(room: String) -> RoomGroup? { lights.first { $0.room == room } }
    /// The temperatures and vents a room's Climate sheet shows (web `roomClimateGroup`).
    public static func climate(room: String) -> RoomGroup? { climate.first { $0.room == room } }
    /// The presence sensors a room's Occupancy sheet shows (web `roomOccupancyGroup`).
    public static func occupancy(room: String) -> RoomGroup? { occupancy.first { $0.room == room } }
    /// The doors and windows a room's contact sheet shows (web `roomContactGroup`).
    public static func contacts(room: String) -> RoomGroup? { contacts.first { $0.room == room } }

    /// Every room's contact group, for the house-wide door sheet a room without its own group opens (Back Deck, Garage).
    public static var allContacts: [RoomGroup] { contacts }

    /// Every room's lights in web order (`LIGHT_GROUPS`), as Home's Lights sheet lists them.
    public static var allLights: [RoomGroup] { lights }
    /// Every room's temperatures and vents in web order (`CLIMATE_GROUPS`).
    public static var allClimate: [RoomGroup] { climate }
    /// Every room's presence sensors in web order (`OCCUPANCY_GROUPS`).
    public static var allOccupancy: [RoomGroup] { occupancy }

    static let lights: [RoomGroup] = [
        RoomGroup("Living Room", entityId: "light.living_room", [
            I("Front Left", "light.living_room_front_left_light"), I("Front Right", "light.living_room_front_right_light"),
            I("Back Left", "light.living_room_back_left_light"), I("Back Right", "light.living_room_back_right_light"),
        ]),
        RoomGroup("Guest Room", entityId: "light.guest_room", [I("TV Light", "light.guest_room_tv_light"), I("Bed Light", "light.guest_room_bed_light")]),
        RoomGroup("Master Bedroom", entityId: "light.master_bedroom", [
            I("Window Light", "light.master_bedroom_window_light"), I("Bathroom Light", "light.master_bedroom_bathroom_light"),
            I("Door Light", "light.master_bedroom_door_light"), I("Stephen Nightstand", "light.stephen_nightstand_light", resident: .stephen),
            I("Steph Nightstand", "light.steph_nightstand_light", resident: .steph), I("Closet Light", "light.master_bedroom_closet_light"),
        ]),
        RoomGroup("Master Bedroom Closet", entityId: "light.master_bedroom_closet_light", [I("Closet Light", "light.master_bedroom_closet_light")]),
        RoomGroup("Gym", entityId: "light.gym_light", [I("Gym Light", "light.gym_light")]),
        RoomGroup("Hallway", entityId: "light.hallway_lights", [
            I("Entry Light", "light.hallway_entry_light"), I("Gym Light", "light.hallway_gym_light"),
            I("Guest Room Light", "light.hallway_guest_room_light"), I("Office Light", "light.hallway_office_light"),
        ]),
        RoomGroup("Office", entityId: "light.office_light", [I("Office Light", "light.office_light")]),
        RoomGroup("Kitchen", entityId: "light.kitchen", [
            I("Table Light", "light.kitchen_table_light"), I("Door Light", "light.kitchen_door_light"),
            I("Counter Light", "light.kitchen_counter_light"), I("Sink Light", "light.kitchen_sink_light"),
        ]),
        RoomGroup("Dining Room", entityId: "light.dining_room_dimmer_switch", [I("Dining Room Light", "light.dining_room_dimmer_switch")]),
        RoomGroup("Back Deck", entityId: "light.back_deck", [I("Grill Light", "light.grill_light"), I("Couches Light", "light.couch_light")]),
        RoomGroup("Music Room", entityId: "light.music_room", [
            I("Fireplace Light", "light.music_room_fireplace_light_2"), I("Window Light", "light.hue_color_downlight_4"),
            I("Entry Light", "light.hue_color_downlight_1"), I("Drums Light", "light.hue_color_downlight_3"),
            I("Bathroom Light", "light.hue_color_downlight_5"), I("Couch Light", "light.hue_color_downlight_6"),
            I("Server Light", "light.hue_color_downlight_8"), I("TV Light", "light.hue_color_downlight_7"),
            I("TV Left Light", "light.hue_play_2"), I("TV Right Light", "light.hue_play_1"),
        ]),
        RoomGroup("Theater Room", entityId: "light.theater_room", [
            I("Front Screen", "light.theater_room_front_screen_light"), I("Front Right", "light.theater_room_front_right_light"),
            I("Front Back", "light.theater_room_front_rear_light"), I("Rear Front", "light.theater_room_rear_front_light"),
            I("Rear Back", "light.theater_room_rear_back_light"), I("Rear Right", "light.theater_room_rear_right_light"),
        ]),
        RoomGroup("Downstairs Hallway", entityId: "light.downstairs_hallway_light", [I("Downstairs Hallway Light", "light.downstairs_hallway_light")]),
        RoomGroup("Guest Bathroom", entityId: "light.guest_bathroom_dimmer_switch", [I("Guest Bathroom Light", "light.guest_bathroom_dimmer_switch")]),
        RoomGroup("Master Bathroom", entityId: "light.master_bathroom_dimmer_switch", [I("Master Bathroom Light", "light.master_bathroom_dimmer_switch")]),
        RoomGroup("Entryway", entityId: "switch.upper_entryway_light_switch_top", [I("Entryway Light", "switch.upper_entryway_light_switch_top")]),
        RoomGroup("Driveway", entityId: "light.garage_camera_floodlight", [I("Floodlight", "light.garage_camera_floodlight")]),
    ]

    static let climate: [RoomGroup] = [
        RoomGroup("Living Room", entityId: "input_text.living_room_climate_range", colorEntityId: "input_text.living_room_climate_color", [
            I("Back Wall", "sensor.living_room_presence_sensor_temperature", color: "input_text.living_room_back_wall_climate_color"), I("Bar", "sensor.living_room_bar_presence_sensor_temperature_2", color: "input_text.living_room_bar_climate_color"),
            I("Kitchen Wall", "sensor.living_room_kitchen_wall_presence_sensor_temperature_2", color: "input_text.living_room_kitchen_wall_climate_color"),
            I("Fireplace", "sensor.living_room_fireplace_presence_sensor_temperature_2", color: "input_text.living_room_fireplace_climate_color"), I("Vents", "cover.living_room_vents"),
        ]),
        RoomGroup("Guest Room", entityId: "input_text.guest_room_climate_range", colorEntityId: "input_text.guest_room_climate_color", [
            I("Presence", "sensor.guest_room_presence_sensor_temperature_2", color: "input_text.guest_room_presence_climate_color"),
            I("Closet", "sensor.guest_room_closet_facing_presence_sensor_temperature_2", color: "input_text.guest_room_closet_climate_color"), I("Vent", "cover.guest_room_vent_vent"),
        ]),
        RoomGroup("Master Bedroom", entityId: "input_text.master_bedroom_climate_range", colorEntityId: "input_text.master_bedroom_climate_color", [
            I("Window", "sensor.master_bedroom_window_presence_sensor_temperature", color: "input_text.master_bedroom_window_climate_color"), I("Bed", "sensor.master_bedroom_bed_presence_sensor_temperature", color: "input_text.master_bedroom_bed_climate_color"),
            I("Bathroom", "sensor.master_bedroom_bathroom_presence_sensor_temperature", color: "input_text.master_bedroom_bathroom_climate_color"),
            I("Closet", "sensor.master_bedroom_closet_presence_sensor_temperature", color: "input_text.master_bedroom_closet_climate_color"), I("Vents", "cover.master_bedroom_vents"),
        ]),
        RoomGroup("Gym", entityId: "input_text.gym_climate_range", colorEntityId: "input_text.gym_climate_color", [
            I("Presence", "sensor.gym_presence_sensor_temperature_2", color: "input_text.gym_presence_climate_color"),
            I("Door", "sensor.hallway_guest_bath_gym_presence_sensor_temperature", color: "input_text.gym_door_guest_bath_climate_color"), I("Vent", "cover.gym_vent_vent"),
        ]),
        RoomGroup("Hallway", entityId: "input_text.hallway_climate_range", colorEntityId: "input_text.hallway_climate_color", [
            I("Entry", "sensor.entryway_presence_sensor_temperature", color: "input_text.entryway_climate_color"),
            I("Guest Room", "sensor.hallway_guest_bath_gym_presence_sensor_temperature", color: "input_text.gym_door_guest_bath_climate_color"),
            I("Office", "sensor.hallway_office_bedroom_presence_sensor_temperature", color: "input_text.office_door_climate_color"),
        ]),
        RoomGroup("Office", entityId: "input_text.office_climate_range", colorEntityId: "input_text.office_climate_color", [
            I("Door", "sensor.hallway_office_bedroom_presence_sensor_temperature", color: "input_text.office_door_climate_color"), I("Presence", "sensor.office_presence_sensor_temperature", color: "input_text.office_presence_climate_color"),
            I("Closet", "sensor.office_closet_presence_sensor_temperature", color: "input_text.office_closet_climate_color"), I("Vent", "cover.office_vent_vent"),
        ]),
        RoomGroup("Kitchen", entityId: "input_text.kitchen_climate_range", colorEntityId: "input_text.kitchen_climate_color", [
            I("Kitchen", "sensor.kitchen_presence_sensor_temperature_2", color: "input_text.kitchen_presence_climate_color"), I("Vent", "cover.kitchen_vent_vent"),
        ]),
        RoomGroup("Dining Room", entityId: "input_text.dining_room_climate_range", colorEntityId: "input_text.dining_room_climate_color", [
            I("Presence", "sensor.dining_room_presence_sensor_temperature_2", color: "input_text.dining_room_presence_climate_color"), I("Vent", "cover.dining_room_vent_vent"),
        ]),
        RoomGroup("Music Room", entityId: "input_text.music_room_climate_range", colorEntityId: "input_text.music_room_climate_color", [
            I("Kitchenette", "sensor.music_room_kitchenette_presence_sensor_temperature_2", color: "input_text.music_room_kitchenette_climate_color"),
            I("North Wall", "sensor.music_room_north_wall_presence_sensor_temperature_2", color: "input_text.music_room_north_wall_climate_color"),
            I("Door", "sensor.music_room_door_presence_sensor_temperature_2", color: "input_text.music_room_door_climate_color"), I("Vent", "cover.music_room_vent_vent"),
        ]),
        RoomGroup("Theater Room", entityId: "input_text.theater_room_climate_range", colorEntityId: "input_text.theater_room_climate_color", [
            I("Presence", "sensor.theater_room_presence_sensor_temperature_2", color: "input_text.theater_room_presence_sensor_climate_color"), I("Vents", "cover.theater_room_vents"),
        ]),
        RoomGroup("Downstairs Hallway", entityId: "input_text.downstairs_hallway_climate_range", colorEntityId: "input_text.downstairs_hallway_climate_color", [
            I("Presence", "sensor.downstairs_hallway_presence_sensor_temperature_2", color: "input_text.downstairs_hallway_climate_color"),
        ]),
        RoomGroup("Guest Bathroom", entityId: "input_text.guest_bathroom_climate_range", colorEntityId: "input_text.guest_bathroom_climate_color", [
            I("Presence", "sensor.guest_bathroom_presence_sensor_temperature_2", color: "input_text.guest_bathroom_presence_climate_color"),
            I("Entry", "sensor.guest_bathroom_entry_presence_sensor_temperature_2", color: "input_text.guest_bathroom_entry_climate_color"), I("Vent", "cover.guest_bathroom_vent_vent"),
        ]),
        RoomGroup("Master Bathroom", entityId: "input_text.master_bathroom_climate_range", colorEntityId: "input_text.master_bathroom_climate_color", [
            I("Presence", "sensor.master_bathroom_presence_sensor_temperature", color: "input_text.master_bathroom_presence_climate_color"), I("Vent", "cover.master_bathroom_vent_vent"),
        ]),
        RoomGroup("Entryway", entityId: "input_text.front_door_climate_range", colorEntityId: "input_text.front_door_climate_color", [
            I("Front Door", "sensor.front_door_presence_sensor_temperature_2", color: "input_text.entryway_climate_color"),
        ]),
    ]

    static let occupancy: [RoomGroup] = [
        RoomGroup("Living Room", [
            I("Back Wall", "binary_sensor.living_room_presence_sensor_presence"), I("Bar", "binary_sensor.living_room_bar_presence_sensor_presence"),
            I("Kitchen Wall", "binary_sensor.living_room_kitchen_wall_presence_sensor_presence"),
            I("Fireplace", "binary_sensor.living_room_fireplace_presence_sensor_presence"),
        ]),
        RoomGroup("Hallway", [
            I("Entryway", "binary_sensor.entryway_presence_sensor_presence"),
            I("Bathroom", "binary_sensor.hallway_guest_bath_gym_presence_sensor_presence"),
            I("Office", "binary_sensor.hallway_office_bedroom_presence_sensor_presence"),
        ]),
        RoomGroup("Kitchen", [I("Kitchen", "binary_sensor.kitchen_presence_sensor_presence")]),
        RoomGroup("Guest Room", [
            I("Guest Room", "binary_sensor.guest_room_presence_sensor_presence"),
            I("Closet", "binary_sensor.guest_room_closet_facing_presence_sensor_presence"),
        ]),
        RoomGroup("Gym", [I("Gym", "binary_sensor.gym_presence_sensor_presence")]),
        RoomGroup("Office", [
            I("Office", "binary_sensor.office_presence_sensor_presence"), I("Closet", "binary_sensor.office_closet_presence_sensor_presence"),
        ]),
        RoomGroup("Master Bedroom", [
            I("Master Bedroom", "binary_sensor.master_bedroom_window_presence_sensor_presence"),
            I("Bed", "binary_sensor.master_bedroom_bed_presence_sensor_presence"),
            I("Bathroom", "binary_sensor.master_bedroom_bathroom_presence_sensor_presence"),
            I("Closet", "binary_sensor.master_bedroom_closet_presence_sensor_presence"),
        ]),
        RoomGroup("Master Bedroom Closet", [I("Closet", "binary_sensor.master_bedroom_closet_presence_sensor_presence")]),
        RoomGroup("Guest Bathroom", [
            I("Guest Bathroom", "binary_sensor.guest_bathroom_presence_sensor_presence"),
            I("Entry", "binary_sensor.guest_bathroom_entry_presence_sensor_presence"),
        ]),
        RoomGroup("Master Bathroom", [I("Master Bathroom", "binary_sensor.master_bathroom_presence_sensor_presence")]),
        RoomGroup("Music Room", [
            I("North Wall", "binary_sensor.music_room_north_wall_presence_sensor_presence"),
            I("Kitchenette", "binary_sensor.music_room_kitchenette_presence_sensor_presence"),
            I("Door", "binary_sensor.music_room_door_presence_sensor_presence"),
        ]),
        RoomGroup("Dining Room", [I("Dining Room", "binary_sensor.dining_room_presence_sensor_presence")]),
        RoomGroup("Theater Room", [I("Theater Room", "binary_sensor.theater_room_presence_sensor_presence")]),
        RoomGroup("Entryway", [
            I("Entryway Occupancy", "binary_sensor.entryway_presence_sensor_presence"),
            I("Front Door", "binary_sensor.front_door_presence_sensor_presence"),
        ]),
        RoomGroup("Downstairs Hallway", [I("Downstairs Hallway", "binary_sensor.downstairs_hallway_presence_sensor_presence")]),
    ]

    static let contacts: [RoomGroup] = [
        RoomGroup("Entryway", [I("Front Door", "binary_sensor.front_door_contact_sensor_contact")]),
        RoomGroup("Office", [
            I("PC Window", "binary_sensor.office_pc_window_sensor_contact"), I("Window", "binary_sensor.office_window_contact_sensor_contact"),
        ]),
        RoomGroup("Living Room", [I("Window", "binary_sensor.living_room_window_contact_sensor_contact")]),
        RoomGroup("Garage", [I("Garage Door", "binary_sensor.garage_door_contact_sensor_contact")]),
        RoomGroup("Master Bedroom", [I("Street Windows", "binary_sensor.master_bedroom_street_window_contact_sensor_contact", contactCount: 2)]),
        RoomGroup("Dining Room", [I("Dining Room Door", "binary_sensor.dining_room_door_contact_sensor_contact")]),
        RoomGroup("Kitchen", [I("Kitchen Door", "binary_sensor.kitchen_door_contact_sensor_contact")]),
        RoomGroup("Music Room", [I("Music Room Door", "binary_sensor.music_room_door_contact_sensor_contact")]),
        RoomGroup("Theater Room", [I("Theater Room Door", "binary_sensor.theater_room_door_contact_sensor_contact")]),
        RoomGroup("Guest Room", [I("Window", "binary_sensor.guest_room_window_contact_sensor_contact")]),
        RoomGroup("Gym", [I("Window", "binary_sensor.gym_window_contact_sensor_contact")]),
    ]
}
