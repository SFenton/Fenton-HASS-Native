import Foundation

// MARK: - Bathroom fans

/// One bathroom fan: a switch with an automation lock and an off timer, all driven through one script
/// (web `BathroomFanConfig`, `ha-sfenton-react-dash@9ac2a46:src/constants/bathroomFans.ts`).
public struct BathroomFanConfig: Hashable, Sendable, Identifiable {
    public var id: String
    /// The room, used in the sheet title ("Guest Bathroom Fan").
    public var roomTitle: String
    /// `input_boolean` on while the timer's auto-unlock is set.
    public var autoUnlockEntityId: String
    /// `input_datetime` holding when the timer ends.
    public var deadlineEntityId: String
    /// `input_boolean` on while the automation lock holds the fan.
    public var lockEntityId: String
    /// `input_boolean` on while a timer is pending.
    public var pendingEntityId: String
    /// The fan's switch.
    public var powerEntityId: String
    /// The `script.<name>` every command goes through.
    public var scriptService: String
    /// The `timer` entity the script runs (read-only here).
    public var timerEntityId: String

    /// Creates a fan.
    public init(id: String, roomTitle: String, autoUnlockEntityId: String, deadlineEntityId: String, lockEntityId: String,
                pendingEntityId: String, powerEntityId: String, scriptService: String, timerEntityId: String) {
        self.id = id
        self.roomTitle = roomTitle
        self.autoUnlockEntityId = autoUnlockEntityId
        self.deadlineEntityId = deadlineEntityId
        self.lockEntityId = lockEntityId
        self.pendingEntityId = pendingEntityId
        self.powerEntityId = powerEntityId
        self.scriptService = scriptService
        self.timerEntityId = timerEntityId
    }

    /// The four entities the controls show optimistically.
    public var optimisticEntityIds: [String] { [powerEntityId, lockEntityId, pendingEntityId, autoUnlockEntityId] }
}

public extension BathroomFanConfig {
    /// `BATHROOM_FANS.guest`.
    static let guest = BathroomFanConfig(
        id: "guest", roomTitle: "Guest Bathroom",
        autoUnlockEntityId: "input_boolean.guest_bathroom_fan_timer_auto_unlock",
        deadlineEntityId: "input_datetime.guest_bathroom_fan_timer_ends_at",
        lockEntityId: "input_boolean.guest_bathroom_fan_automation_lock",
        pendingEntityId: "input_boolean.guest_bathroom_fan_timer_pending",
        powerEntityId: "switch.guest_bathroom_fan_switch_top",
        scriptService: "guest_bathroom_fan_command",
        timerEntityId: "timer.guest_bathroom_fan_off_timer"
    )

    /// `BATHROOM_FANS.master`.
    static let master = BathroomFanConfig(
        id: "master", roomTitle: "Master Bathroom",
        autoUnlockEntityId: "input_boolean.master_bathroom_fan_timer_auto_unlock",
        deadlineEntityId: "input_datetime.master_bathroom_fan_timer_ends_at",
        lockEntityId: "input_boolean.master_bathroom_fan_automation_lock",
        pendingEntityId: "input_boolean.master_bathroom_fan_timer_pending",
        powerEntityId: "switch.master_bathroom_fan_switch_top",
        scriptService: "master_bathroom_fan_command",
        timerEntityId: "timer.master_bathroom_fan_off_timer"
    )

    /// Every fan.
    static let all: [BathroomFanConfig] = [.guest, .master]

    /// The fan whose switch is `entityId` (web `bathroomFanForPowerEntity`).
    static func forPowerEntity(_ entityId: String) -> BathroomFanConfig? {
        all.first { $0.powerEntityId == entityId }
    }
}

// MARK: - Air purifiers

/// A Levoit air purifier, whose entities all derive from its PM2.5 sensor
/// (web `derivedAirPurifierEntityIds`, `src/components/hass/airQualityState.ts`).
public struct AirPurifierConfig: Hashable, Sendable, Identifiable {
    /// The room, used in the sheet title and accessibility labels.
    public var roomTitle: String
    /// e.g. `sensor.office_air_purifier_pm2_5`.
    public var pm25EntityId: String

    public var id: String { pm25EntityId }

    /// Creates a purifier from its PM2.5 sensor.
    public init(roomTitle: String, pm25EntityId: String) {
        self.roomTitle = roomTitle
        self.pm25EntityId = pm25EntityId
    }

    /// The shared prefix, e.g. `office_air_purifier`.
    var base: String {
        var base = pm25EntityId
        if base.hasPrefix("sensor.") { base.removeFirst("sensor.".count) }
        if base.hasSuffix("_pm2_5") { base.removeLast("_pm2_5".count) }
        return base
    }

    /// `sensor.<base>_air_quality_index`.
    public var aqiEntityId: String { "sensor.\(base)_air_quality_index" }
    /// `select.<base>_auto_mode`.
    public var autoModeEntityId: String { "select.\(base)_auto_mode" }
    /// `fan.<base>_levoit_purifier`.
    public var fanEntityId: String { "fan.\(base)_levoit_purifier" }
    /// `select.<base>_fan_mode`.
    public var modeEntityId: String { "select.\(base)_fan_mode" }
}

public extension AirPurifierConfig {
    /// The purifiers on the web room pages (`src/constants/roomPages.ts`).
    static let all: [AirPurifierConfig] = [
        .init(roomTitle: "Living Room", pm25EntityId: "sensor.living_room_air_purifier_pm2_5"),
        .init(roomTitle: "Guest Room", pm25EntityId: "sensor.guest_room_air_purifier_pm2_5"),
        .init(roomTitle: "Master Bedroom", pm25EntityId: "sensor.master_bedroom_air_purifier_pm2_5"),
        .init(roomTitle: "Office", pm25EntityId: "sensor.office_air_purifier_pm2_5"),
        .init(roomTitle: "Music Room", pm25EntityId: "sensor.air_purifier_pm2_5"),
        .init(roomTitle: "Theater Room", pm25EntityId: "sensor.theater_room_air_purifier_pm2_5"),
    ]

    /// The purifier a room page names by its PM2.5 sensor.
    static func forPM25Entity(_ entityId: String) -> AirPurifierConfig? {
        all.first { $0.pm25EntityId == entityId }
    }
}

// MARK: - Humidifiers

/// A humidifier's operating mode; raw values are the `select` options Home Assistant uses.
public enum HumidifierMode: String, CaseIterable, Hashable, Sendable {
    case manual = "Manual"
    case targetHumidity = "Target Humidity"
    case sleep = "Sleep"

    /// What the app calls the mode (web `HUMIDIFIER_MODES` labels).
    public var title: String {
        switch self {
        case .manual: "Manual"
        case .targetHumidity: "Auto Humidity"
        case .sleep: "Sleep"
        }
    }

    /// Web MDI icon.
    public var icon: String {
        switch self {
        case .manual: "mdi:water"
        case .targetHumidity: "mdi:fan-auto"
        case .sleep: "mdi:weather-night"
        }
    }
}

/// A Levoit LV600S humidifier and its scheduling helpers (web `HumidifierConfig`, `src/constants/humidifiers.ts`).
public struct HumidifierConfig: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var applyProfileScriptService: String
    public var currentHumidityEntityId: String
    public var currentTemperatureEntityId: String
    public var displayEntityId: String
    public var humidifyingEntityId: String
    public var mistLevelEntityId: String
    public var modeEntityId: String
    public var powerEntityId: String
    public var scheduleEnabledEntityId: String
    public var scheduleEntityId: String
    /// The `schedule` helper's id for `schedule/list` and `schedule/update`.
    public var scheduleId: String
    public var setLevelScriptService: String
    public var tankRemovedEntityId: String
    public var targetHumidityEntityId: String
    public var timerMinutesEntityId: String
    public var timerRemainingEntityId: String
    public var vacationModeEntityId: String
    public var warmLevelEntityId: String
    public var waterLowEntityId: String

    /// Entities whose values the controls show optimistically.
    public var optimisticEntityIds: [String] {
        [powerEntityId, modeEntityId, mistLevelEntityId, targetHumidityEntityId, warmLevelEntityId, timerMinutesEntityId,
         displayEntityId, scheduleEnabledEntityId]
    }

    /// A mist preset (web `HUMIDIFIER_MIST_PRESETS`).
    public struct Preset: Hashable, Sendable, Identifiable {
        public var title: String
        public var icon: String
        public var value: Int
        public var id: Int { value }
    }

    /// Low 2, Medium 5, High 8, Max 9.
    public static let mistPresets: [Preset] = [
        .init(title: "Low", icon: "mdi:fan-speed-1", value: 2),
        .init(title: "Medium", icon: "mdi:fan-speed-2", value: 5),
        .init(title: "High", icon: "mdi:fan-speed-3", value: 8),
        .init(title: "Max", icon: "mdi:fan", value: 9),
    ]

    /// Off 0 to High 3 (web `HUMIDIFIER_WARM_LEVELS`).
    public static let warmLevels: [Preset] = [
        .init(title: "Off", icon: "mdi:power", value: 0),
        .init(title: "Low", icon: "mdi:fire", value: 1),
        .init(title: "Medium", icon: "mdi:fire", value: 2),
        .init(title: "High", icon: "mdi:fire", value: 3),
    ]
}

public extension HumidifierConfig {
    /// `MASTER_BEDROOM_HUMIDIFIER`.
    static let masterBedroom = HumidifierConfig(
        id: "master-bedroom-lv600s",
        title: "Master Bedroom Humidifier",
        applyProfileScriptService: "master_bedroom_humidifier_apply_profile",
        currentHumidityEntityId: "sensor.lv600s_humidifier_current_humidity",
        currentTemperatureEntityId: "sensor.lv600s_humidifier_current_temperature",
        displayEntityId: "switch.lv600s_humidifier_display",
        humidifyingEntityId: "binary_sensor.lv600s_humidifier_humidifying",
        mistLevelEntityId: "number.lv600s_humidifier_mist_level",
        modeEntityId: "select.lv600s_humidifier_mode",
        powerEntityId: "switch.lv600s_humidifier_power",
        scheduleEnabledEntityId: "input_boolean.master_bedroom_humidifier_schedule_enabled",
        scheduleEntityId: "schedule.master_bedroom_humidifier",
        scheduleId: "master_bedroom_humidifier",
        setLevelScriptService: "master_bedroom_humidifier_set_level",
        tankRemovedEntityId: "binary_sensor.lv600s_humidifier_tank_removed",
        targetHumidityEntityId: "number.lv600s_humidifier_target_humidity",
        timerMinutesEntityId: "number.lv600s_humidifier_timer_minutes",
        timerRemainingEntityId: "sensor.lv600s_humidifier_timer_remaining",
        vacationModeEntityId: Vacation.modeEntityId,
        warmLevelEntityId: "number.lv600s_humidifier_warm_level",
        waterLowEntityId: "binary_sensor.lv600s_humidifier_water_low"
    )

    /// Every humidifier.
    static let all: [HumidifierConfig] = [.masterBedroom]

    /// The humidifier whose power switch is `entityId` (web `humidifierForPowerEntity`).
    static func forPowerEntity(_ entityId: String) -> HumidifierConfig? {
        all.first { $0.powerEntityId == entityId }
    }
}

// MARK: - Grill

/// The Traeger grill sheet (web `GrillModalContent.tsx`).
public struct GrillConfig: Hashable, Sendable {
    /// One detail card.
    public struct Detail: Hashable, Sendable, Identifiable {
        public var title: String
        public var entityId: String
        public var icon: String
        public var id: String { entityId }
        /// Switches can be tapped; sensors only show their value.
        public var isSwitch: Bool { entityId.hasPrefix("switch.") }
    }

    public var title: String
    /// The room, shown before the title in the sheet ("Back Deck: Bear Grills").
    public var roomTitle: String
    public var stateEntityId: String
    public var details: [Detail]

    /// Bear Grills (`GRILL_DETAILS`).
    public static let bearGrills = GrillConfig(
        title: "Bear Grills",
        roomTitle: "Back Deck",
        stateEntityId: "sensor.d8478fa2ad0a_grill_state",
        details: [
            .init(title: "Probe 1", entityId: "sensor.bear_grills_probe_probe0", icon: "mdi:thermometer"),
            .init(title: "Pellet Level", entityId: "sensor.d8478fa2ad0a_pellet_level", icon: "mdi:percent"),
            .init(title: "Keep Warm", entityId: "switch.d8478fa2ad0a_keep_warm_enabled", icon: "mdi:fire"),
            .init(title: "Super Smoke", entityId: "switch.d8478fa2ad0a_super_smoke_enabled", icon: "mdi:smoke"),
        ]
    )
}
