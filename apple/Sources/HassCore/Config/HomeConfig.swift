import Foundation

/// Entity configuration for the Home page, ported from the React dashboard.
///
/// Source: `ha-sfenton-react-dash@9ac2a46:src/constants/atAGlance.ts` and `src/constants/portedDashboard.ts`; the status
/// rail and its summaries follow `ha-sfenton-react-dash@f5a7bf9`.
public enum HomeConfig {
    // MARK: - Status rail

    /// Which sheet a status chip opens.
    public enum ChipSheet: String, Sendable, Hashable, CaseIterable, Identifiable {
        case lights, security, climate, occupancy, contacts, airQuality
        public var id: String { rawValue }

        /// The room overview this chip opens, or `nil` for Security (its own controls).
        public var overview: RoomOverviewKind? {
            switch self {
            case .lights: .lights
            case .climate: .climate
            case .occupancy: .occupancy
            case .contacts: .contacts
            case .airQuality: .airQuality
            case .security: nil
            }
        }
    }

    /// Visual tone of a chip (web `StatusChipConfig.tone`).
    public enum ChipTone: String, Sendable { case light, security, climate, presence, contact, air }

    /// One chip in the Home status rail.
    public struct StatusChip: Sendable, Identifiable {
        public var title: String
        /// Web MDI icon name, mapped to an SF Symbol by `HassDesign`.
        public var icon: String
        public var entityId: String
        public var tone: ChipTone
        public var sheet: ChipSheet
        /// A text helper whose color tints the icon (Air Quality, web `colorEntityId`).
        public var colorEntityId: String? = nil
        public var id: String { entityId }
    }

    /// `OVERVIEW_STATUS_CHIPS` (`ha-sfenton-react-dash@f5a7bf9:src/constants/atAGlance.ts:128`).
    public static let statusChips: [StatusChip] = [
        .init(title: "Lights", icon: "mdi:lightbulb-group", entityId: "light.lights", tone: .light, sheet: .lights),
        .init(title: "Security", icon: "mdi:shield-outline", entityId: "alarm_control_panel.aqara_hub_m3_0056_security_system_2", tone: .security, sheet: .security),
        .init(title: "Climate", icon: "mdi:thermometer", entityId: "input_text.all_climate_range", tone: .climate, sheet: .climate),
        .init(title: "Occupancy", icon: "mdi:motion-sensor", entityId: "binary_sensor.occupancy_sensors", tone: .presence, sheet: .occupancy),
        .init(title: "Contact Sensors", icon: "mdi:door", entityId: "binary_sensor.contact_sensors", tone: .contact, sheet: .contacts),
        .init(title: "Air Quality", icon: "mdi:blur", entityId: "input_text.all_aqi_range", tone: .air, sheet: .airQuality,
              colorEntityId: "input_text.all_aqi_color"),
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

    /// Room light groups shown in the Lights sheet, in web order (`LIGHT_GROUPS`, atAGlance.ts:343).
    public static var lightGroups: [RoomGroup] { RoomGroups.allLights }
}

// MARK: - Summaries

public extension HomeConfig {
    /// The short value a status chip shows under its title.
    /// - Parameters:
    ///   - chip: The chip.
    ///   - value: Looks up an entity's current state.
    static func summary(for chip: StatusChip, value: (String) -> EntityState?) -> String {
        // Lights, Contact Sensors and Air Quality count their rooms' entities (web `subtitleByHash`), so they read
        // even while the chip's own group entity is missing.
        switch chip.sheet {
        case .lights: return RoomOverview.lightCountSummary(RoomOverview.activeLightCount(read: value))
        case .contacts: return RoomOverview.contactCountSummary(RoomOverview.openContactCount(read: value))
        case .airQuality: return RoomOverview.airQualityChipSummary(read: value)
        default: break
        }
        guard let entity = value(chip.entityId), !entity.isUnavailable else { return "Unavailable" }
        switch chip.sheet {
        case .security: return StateText.titleCase(entity.state)
        case .occupancy: return RoomFormat.occupancy(entity)
        default: return entity.state
        }
    }
}
