import Foundation

/// Entity configuration for the Home page, ported from the React dashboard.
///
/// Source: `ha-sfenton-react-dash@9ac2a46:src/constants/atAGlance.ts` and `src/constants/portedDashboard.ts`.
public enum HomeConfig {
    // MARK: - Status rail

    /// Which sheet a status chip opens.
    public enum ChipSheet: String, Sendable, Hashable, CaseIterable, Identifiable {
        case lights, security, climate, occupancy, contacts
        public var id: String { rawValue }
    }

    /// Visual tone of a chip (web `StatusChipConfig.tone`).
    public enum ChipTone: String, Sendable { case light, security, climate, presence, contact }

    /// One chip in the Home status rail.
    public struct StatusChip: Sendable, Identifiable {
        public var title: String
        /// Web MDI icon name, mapped to an SF Symbol by `HassDesign`.
        public var icon: String
        public var entityId: String
        public var tone: ChipTone
        public var sheet: ChipSheet
        public var id: String { entityId }
    }

    /// `OVERVIEW_STATUS_CHIPS` (atAGlance.ts:128).
    public static let statusChips: [StatusChip] = [
        .init(title: "Lights", icon: "mdi:lightbulb-group", entityId: "light.lights", tone: .light, sheet: .lights),
        .init(title: "Security", icon: "mdi:shield-outline", entityId: "alarm_control_panel.aqara_hub_m3_0056_security_system_2", tone: .security, sheet: .security),
        .init(title: "Climate", icon: "mdi:thermometer", entityId: "input_text.all_climate_range", tone: .climate, sheet: .climate),
        .init(title: "Occupancy", icon: "mdi:motion-sensor", entityId: "binary_sensor.occupancy_sensors", tone: .presence, sheet: .occupancy),
        .init(title: "Contact Sensors", icon: "mdi:door", entityId: "binary_sensor.contact_sensors", tone: .contact, sheet: .contacts),
    ]

    // MARK: - Weather

    /// Weather entity used by the web `WeatherSummary`.
    public static let weatherEntityId = "weather.pirate_weather"

    // MARK: - Guests

    /// One guest-stay toggle (`GUEST_CONTROL_ITEMS`, portedDashboard.ts:391).
    public struct GuestToggle: Sendable, Identifiable {
        public var title: String
        public var entityId: String
        public var icon: String
        public var id: String { entityId }
    }

    /// Guest-stay toggles; the guest presence section shows when any is on.
    public static let guestToggles: [GuestToggle] = [
        .init(title: "Guest Room", entityId: "input_boolean.guests_staying_in_guest_room", icon: "mdi:bed"),
        .init(title: "Music Room", entityId: "input_boolean.guests_staying_in_music_room", icon: "mdi:guitar-electric"),
        .init(title: "Theater Room", entityId: "input_boolean.guests_staying_in_theater_room", icon: "mdi:projector"),
    ]

    // MARK: - Cameras

    /// One camera tile (`CAMERA_ITEMS`, atAGlance.ts:281).
    public struct Camera: Sendable, Identifiable, Hashable {
        public var title: String
        public var entityId: String
        /// go2rtc stream id for the future live view.
        public var rtcStreamId: String
        /// Width / height.
        public var aspectRatio: Double
        public var id: String { entityId }
    }

    /// Home cameras in web order.
    public static let cameras: [Camera] = [
        .init(title: "Front Door", entityId: "camera.front_door_camera", rtcStreamId: "front_door", aspectRatio: 4.0 / 3.0),
        .init(title: "Driveway", entityId: "camera.garage_camera", rtcStreamId: "garage_camera", aspectRatio: 10.0 / 3.0),
        .init(title: "Upper Deck", entityId: "camera.upper_deck_camera_2", rtcStreamId: "upper_deck", aspectRatio: 16.0 / 9.0),
        .init(title: "Lower Deck", entityId: "camera.lower_deck_camera", rtcStreamId: "lower_deck", aspectRatio: 16.0 / 9.0),
    ]

    // MARK: - Lights

    /// A room's light group (`LIGHT_GROUPS`, atAGlance.ts:343).
    public struct LightGroup: Sendable, Identifiable {
        public var title: String
        public var toggleEntityId: String
        public var id: String { toggleEntityId }
    }

    /// Room light groups shown in the Lights sheet, in web order.
    public static let lightGroups: [LightGroup] = [
        .init(title: "Living Room", toggleEntityId: "light.living_room"),
        .init(title: "Guest Room", toggleEntityId: "light.guest_room"),
        .init(title: "Master Bedroom", toggleEntityId: "light.master_bedroom"),
        .init(title: "Master Bedroom Closet", toggleEntityId: "light.master_bedroom_closet_light"),
        .init(title: "Gym", toggleEntityId: "light.gym_light"),
        .init(title: "Hallway", toggleEntityId: "light.hallway_lights"),
        .init(title: "Office", toggleEntityId: "light.office_light"),
        .init(title: "Kitchen", toggleEntityId: "light.kitchen"),
        .init(title: "Dining Room", toggleEntityId: "light.dining_room_dimmer_switch"),
        .init(title: "Back Deck", toggleEntityId: "light.back_deck"),
        .init(title: "Music Room", toggleEntityId: "light.music_room"),
        .init(title: "Theater Room", toggleEntityId: "light.theater_room"),
        .init(title: "Downstairs Hallway", toggleEntityId: "light.downstairs_hallway_light"),
        .init(title: "Guest Bathroom", toggleEntityId: "light.guest_bathroom_dimmer_switch"),
        .init(title: "Master Bathroom", toggleEntityId: "light.master_bathroom_dimmer_switch"),
        .init(title: "Entryway", toggleEntityId: "switch.upper_entryway_light_switch_top"),
    ]
}

// MARK: - Summaries

public extension HomeConfig {
    /// The short value a status chip shows under its title.
    /// - Parameters:
    ///   - chip: The chip.
    ///   - value: Looks up an entity's current state.
    static func summary(for chip: StatusChip, value: (String) -> EntityState?) -> String {
        guard let entity = value(chip.entityId), !entity.isUnavailable else { return "Unavailable" }
        switch chip.sheet {
        case .lights:
            let on = lightGroups.filter { value($0.toggleEntityId)?.state == "on" }.count
            return on == 0 ? "All off" : "\(on) on"
        case .security:
            return entity.state.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
        case .climate:
            return entity.state
        case .occupancy:
            return entity.state == "on" ? "Occupied" : "Clear"
        case .contacts:
            if let ids = entity.attributes["entity_id"]?.array?.compactMap(\.string) {
                let open = ids.filter { value($0)?.state == "on" }.count
                return open == 0 ? "All closed" : "\(open) open"
            }
            return entity.state == "on" ? "Open" : "All closed"
        }
    }
}
