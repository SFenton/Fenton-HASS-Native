import Foundation

// MARK: - Shared vocabulary

/// A side of the Master Bedroom Pod (web `SleepypodSide`).
public enum BedSide: String, CaseIterable, Codable, Hashable, Sendable {
    case left, right
}

/// A day of the week as Home Assistant's schedules spell it, Sunday first (web `SCHEDULE_WEEKDAYS`).
public enum Weekday: String, CaseIterable, Codable, Hashable, Sendable, Comparable {
    case sunday, monday, tuesday, wednesday, thursday, friday, saturday

    /// Position in the week, Sunday = 0.
    public var index: Int { Self.allCases.firstIndex(of: self)! }

    /// `Monday`.
    public var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// `Mon`.
    public var shortLabel: String { String(label.prefix(3)) }

    /// Monday through Friday (web `WAKE_LIGHT_WEEKDAY_GROUPS.WEEKDAYS`, also the schedule editors' default days).
    public static let workdays: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday]
    /// Saturday and Sunday in week order (Sunday first).
    public static let weekend: [Weekday] = [.sunday, .saturday]

    /// The weekday of `date` in `calendar`.
    public init(date: Date, calendar: Calendar = .current) {
        self = Self.allCases[calendar.component(.weekday, from: date) - 1]
    }

    /// `days` in week order without duplicates.
    public static func ordered(_ days: some Sequence<Weekday>) -> [Weekday] {
        let set = Set(days)
        return allCases.filter(set.contains)
    }

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.index < rhs.index }
}

/// A household member whose bed side and Solo Trip scope the app tracks (web `HOUSEHOLD_RESIDENT`).
public enum HouseholdResident: String, CaseIterable, Codable, Hashable, Sendable {
    case stephen, steph

    /// Display name.
    public var name: String { self == .stephen ? "Stephen" : "Steph" }
}

// MARK: - Wake light

/// One bed alarm source the wake light can follow (web `WakeLightSourceConfig`).
public struct WakeLightSource: Hashable, Sendable {
    /// `sleepypod:left`.
    public var id: String
    public var side: BedSide
    /// `Stephen's Alarm`.
    public var alarmLabel: String
    /// `Stephen's Alarms`.
    public var alarmsLabel: String
    /// The bed side whose alarm editor this source opens.
    public var bedId: String
}

/// A room's wake light (web `WakeLightConfig`, `src/constants/wakeLights.ts`).
public struct WakeLightConfig: Hashable, Sendable, Identifiable {
    public var id: String
    /// `Wake-Light Alarms`.
    public var title: String
    /// `Master Bedroom`.
    public var roomTitle: String
    /// The integration's status sensor, which carries the whole contract in its attributes.
    public var statusEntityId: String
    public var sources: [WakeLightSource]

    /// The source bound to `side`.
    public func source(for side: BedSide) -> WakeLightSource? { sources.first { $0.side == side } }

    /// The source with `id`.
    public func source(id: String) -> WakeLightSource? { sources.first { $0.id == id } }
}

// MARK: - Bed sides

/// One side of the SleepyPod Eight Pod (web `EightSleepSideConfig`, sleepypod adapter fields only).
public struct BedSideConfig: Hashable, Sendable, Identifiable {
    /// `stephens-bed` (the web hash without `#`).
    public var id: String
    /// `Stephen's Bed`.
    public var title: String
    public var side: BedSide
    public var owner: HouseholdResident

    public var climateEntityId: String
    public var targetLevelEntityId: String
    public var schedulePhaseEntityId: String
    /// `input_number` per stage; the recurring Bedtime, Asleep and Dawn levels.
    public var stageLevelEntityIds: [SchedulePhase: String]
    /// Script that sets tonight's target for the active stage (`script.sleepypod_<owner>_temperature_tonight`).
    public var tonightScript: String
    /// Script that sets the target outside the schedule.
    public var outsideScheduleScript: String

    public var alarmStateEntityId: String
    public var alarmSnoozeButtonEntityId: String
    public var alarmStopButtonEntityId: String

    public var hotFlashActiveEntityId: String
    public var hotFlashButtonEntityId: String
    public var hotFlashCancelButtonEntityId: String
    public var hotFlashRestoreAtEntityId: String
    public var hotFlashTimerEntityId: String

    public var heartRateEntityId: String
    public var breathingRateEntityId: String
    public var hrvEntityId: String
    public var pumpClogEntityId: String
    public var pumpStallEntityId: String
    public var pumpLoopTemperatureEntityId: String
    public var pumpRpmEntityId: String
}

/// The Master Bedroom's wake light and Pod (web `MASTER_BEDROOM_WAKE_LIGHT`, `EIGHT_SLEEP_SIDE_CONFIGS`,
/// `ha-sfenton-react-dash@9ac2a46:src/pages/DashboardViewPage.tsx:3522`).
public enum MasterBedroom {
    /// Both sides' schedules, as the SleepyPod adapter reports them.
    public static let scheduleEntityId = "sensor.master_bedroom_sleepypod_eight_pod_schedules"
    /// MQTT topic that replaces one side's schedule.
    public static let scheduleSetTopic = "sleepypod/eight-pod/cmd/set-schedules"
    /// Script that powers a side on or off through the hot-flash broker.
    public static let hotFlashBrokerScript = "sleepypod_hot_flash_broker"
    /// Household Away (Solo Trip) status.
    public static let householdAwayEntityId = "sensor.household_away_status"
    /// Household Away command script (returns a response).
    public static let householdAwayScript = "household_away_command"

    public static let wakeLight = WakeLightConfig(
        id: "master-bedroom",
        title: "Wake-Light Alarms",
        roomTitle: "Master Bedroom",
        statusEntityId: "sensor.master_bedroom_wake_light",
        sources: [
            WakeLightSource(id: "sleepypod:left", side: .left, alarmLabel: "Stephen's Alarm", alarmsLabel: "Stephen's Alarms", bedId: "stephens-bed"),
            WakeLightSource(id: "sleepypod:right", side: .right, alarmLabel: "Steph's Alarm", alarmsLabel: "Steph's Alarms", bedId: "stephs-bed"),
        ]
    )

    public static let stephensBed = side(id: "stephens-bed", title: "Stephen's Bed", side: .left, owner: .stephen)
    public static let stephsBed = side(id: "stephs-bed", title: "Steph's Bed", side: .right, owner: .steph)

    /// Both sides, left first.
    public static let beds = [stephensBed, stephsBed]

    /// The side config for `side`.
    public static func bed(_ side: BedSide) -> BedSideConfig { side == .left ? stephensBed : stephsBed }

    /// The side config with `id` (`stephens-bed`).
    public static func bed(id: String) -> BedSideConfig? { beds.first { $0.id == id } }

    private static func side(id: String, title: String, side: BedSide, owner: HouseholdResident) -> BedSideConfig {
        let pod = "master_bedroom_sleepypod_eight_pod_\(side.rawValue)"
        let sensor = "sleepypod_eight_pod_\(side.rawValue)"
        let person = owner.rawValue
        return BedSideConfig(
            id: id, title: title, side: side, owner: owner,
            climateEntityId: "climate.sleepypod_eight_pod_\(side.rawValue)_side",
            targetLevelEntityId: "number.\(pod)_target_level",
            schedulePhaseEntityId: "sensor.sleepypod_\(person)_schedule_phase",
            stageLevelEntityIds: [
                .bedtime: "input_number.eight_sleep_\(person)_bedtime_level",
                .asleep: "input_number.eight_sleep_\(person)_asleep_level",
                .dawn: "input_number.eight_sleep_\(person)_dawn_level",
            ],
            tonightScript: "sleepypod_\(person)_temperature_tonight",
            outsideScheduleScript: "sleepypod_\(person)_temperature_outside_schedule",
            alarmStateEntityId: "sensor.\(pod)_alarm_state",
            alarmSnoozeButtonEntityId: "button.\(pod)_alarm_snooze",
            alarmStopButtonEntityId: "button.\(pod)_alarm_stop",
            hotFlashActiveEntityId: "input_boolean.eight_sleep_\(person)_hot_flash_active",
            hotFlashButtonEntityId: "input_button.eight_sleep_\(person)_hot_flash",
            hotFlashCancelButtonEntityId: "input_button.eight_sleep_\(person)_cancel_hot_flash",
            hotFlashRestoreAtEntityId: "input_datetime.eight_sleep_\(person)_hot_flash_restore_at",
            hotFlashTimerEntityId: "timer.eight_sleep_\(person)_hot_flash",
            heartRateEntityId: "sensor.\(sensor)_heart_rate",
            breathingRateEntityId: "sensor.\(sensor)_breathing_rate",
            hrvEntityId: "sensor.\(sensor)_hrv",
            pumpClogEntityId: "binary_sensor.\(sensor)_pump_clog_detected",
            pumpStallEntityId: "binary_sensor.\(sensor)_pump_stall",
            pumpLoopTemperatureEntityId: "sensor.\(sensor)_pump_loop_temp",
            pumpRpmEntityId: "sensor.\(sensor)_pump_rpm"
        )
    }
}
