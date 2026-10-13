import Foundation

/// Entity configuration and state rules for the Security page, ported from the React dashboard.
///
/// Sources (`ha-sfenton-react-dash@9ac2a46`): `src/constants/securityPage.ts`, `src/constants/garageDoors.ts`,
/// `src/components/hass/SecurityDashboard.tsx`, `SecurityControls.tsx` and `securityState.ts`.
public enum SecurityConfig {
    // MARK: - Entities

    /// The household alarm panel (`SECURITY_ENTITY`, atAGlance.ts:757).
    public static let alarmEntityId = "alarm_control_panel.aqara_hub_m3_0056_security_system_2"
    /// The front door smart lock.
    public static let frontDoorLockEntityId = "lock.aqara_smart_lock_u400"
    /// Garage door covers (`GARAGE_DOOR_ENTITY_IDS`).
    public static let leftGarageDoorEntityId = "cover.garage_left_door"
    public static let rightGarageDoorEntityId = "cover.garage_right_door"
    /// The car's door lock (`SECURITY_MACHE_TILES`).
    public static let vehicleLockEntityId = "lock.fordpass_3fmtk3su5mma09266_doorlock"
    /// Contact sensor group the Contact Sensors chip summarizes.
    public static let contactSensorsEntityId = "binary_sensor.contact_sensors"

    /// The web hides the Vehicle section (`SHOW_MACHE_SECTION = false`, SecurityDashboard.tsx:31); the native
    /// page follows it. The debug gallery shows the section so its tile stays tested.
    public static let showsVehicleSection = false

    // MARK: - Tiles

    /// How a tile behaves (web `SecurityTileTone` plus `SecurityTileAction`).
    public enum TileKind: String, Sendable {
        /// Opens the security system sheet.
        case alarm
        /// Locks or unlocks.
        case lock
        /// A garage door: open/close with the command state machine (``GarageDoorController``).
        case garageDoor
        /// The car's door lock.
        case vehicle
    }

    /// One Security tile.
    public struct Tile: Sendable, Identifiable, Hashable {
        public var title: String
        public var entityId: String
        /// Web MDI icon name.
        public var icon: String
        public var kind: TileKind
        public var id: String { entityId }
    }

    /// `SECURITY_CONTROL_TILES`, in web order.
    public static let controlTiles: [Tile] = [
        .init(title: "Security System", entityId: alarmEntityId, icon: "mdi:shield-outline", kind: .alarm),
        .init(title: "Front Door", entityId: frontDoorLockEntityId, icon: "mdi:lock", kind: .lock),
        .init(title: "Left Door", entityId: leftGarageDoorEntityId, icon: "mdi:garage", kind: .garageDoor),
        .init(title: "Right Door", entityId: rightGarageDoorEntityId, icon: "mdi:garage", kind: .garageDoor),
    ]

    /// `SECURITY_MACHE_TILES`.
    public static let vehicleTiles: [Tile] = [
        .init(title: "Doors", entityId: vehicleLockEntityId, icon: "mdi:car-door-lock", kind: .vehicle),
    ]

    // MARK: - Tone

    /// A tile's color role (web `TileTone` as chosen by `tileTone`, SecurityDashboard.tsx:59).
    public enum Tone: String, Sendable {
        /// Closed, locked or disarmed (web `contact`, green).
        case secure
        /// Armed or moving (web `security`, blue).
        case active
        /// Open, unlocked or failed (web `danger`, red).
        case danger
        /// Unavailable.
        case neutral
    }

    /// The tone for a tile showing `state`.
    public static func tone(for kind: TileKind, state: String?) -> Tone {
        guard let state, !EntityState.isUnavailable(state) else { return .neutral }
        switch kind {
        case .garageDoor:
            switch state {
            case "closed": return .secure
            case "open", "opening": return .danger
            default: return .active
            }
        case .lock, .vehicle:
            switch state {
            case "locked": return .secure
            case "unlocked", "open", "jammed": return .danger
            default: return .active
            }
        case .alarm:
            return state == "disarmed" ? .secure : (state == "triggered" ? .danger : .active)
        }
    }

    // MARK: - Locks

    /// The lock service that flips what the tile shows (web `lockServiceForState`): unlocked or unlocking locks,
    /// anything else unlocks. Explicit services, never `toggle`.
    public static func lockService(for state: String?) -> String {
        state == "unlocked" || state == "unlocking" || state == "open" ? "lock" : "unlock"
    }

    /// The `lock.lock` / `lock.unlock` call for a lock tile.
    public static func lockCall(entityId: String, state: String?) -> ServiceCall {
        ServiceCall("lock", lockService(for: state), target: entityId)
    }

    // MARK: - Alarm modes

    /// One alarm mode button (`SECURITY_MODES`, SecurityControls.tsx:15).
    public struct AlarmMode: Sendable, Identifiable, Hashable {
        public var title: String
        /// `alarm_control_panel` service.
        public var service: String
        /// The panel state this mode sets.
        public var state: String
        public var icon: String
        public var id: String { state }
        /// Disarming opens the house, so it asks first (HIG: Alerts, confirming actions with serious consequences).
        public var needsConfirmation: Bool { state == "disarmed" }

        /// The service call that selects this mode.
        public var call: ServiceCall { ServiceCall("alarm_control_panel", service, target: SecurityConfig.alarmEntityId) }
    }

    /// Modes in web order.
    public static let alarmModes: [AlarmMode] = [
        .init(title: "Home", service: "alarm_arm_home", state: "armed_home", icon: "mdi:shield-home"),
        .init(title: "Away", service: "alarm_arm_away", state: "armed_away", icon: "mdi:shield"),
        .init(title: "Night", service: "alarm_arm_night", state: "armed_night", icon: "mdi:shield-moon"),
        .init(title: "Disarmed", service: "alarm_disarm", state: "disarmed", icon: "mdi:shield-off"),
    ]

    /// The mode that disarms.
    public static var disarmMode: AlarmMode { alarmModes.first(where: \.needsConfirmation)! }

    /// Alarm state colors as 0...255 RGB (`SECURITY_STATE_META`, securityState.ts:7).
    public static func alarmColor(for state: String?) -> (red: Int, green: Int, blue: Int) {
        switch state {
        case "armed_away", "triggered": (229, 57, 53)
        case "armed_home": (30, 136, 229)
        case "armed_night": (142, 36, 170)
        case "disarmed": (67, 160, 71)
        default: (84, 110, 122)
        }
    }

    /// The alarm icon for a panel state (`alarmIcon`, SecurityDashboard.tsx:49).
    public static func alarmIcon(for state: String?) -> String {
        switch state {
        case "disarmed": "mdi:shield-off"
        case "armed_home": "mdi:shield-home"
        case "armed_night": "mdi:shield-moon"
        case "armed_away": "mdi:shield"
        case "triggered": "mdi:shield-alert"
        default: "mdi:shield-outline"
        }
    }

    // MARK: - Text

    /// Title-cased state (`titleCaseState`): `armed_home` → `Armed Home`; missing → `Unknown`.
    public static func stateText(_ state: String?) -> String { StateText.titleCase(state) }
}
