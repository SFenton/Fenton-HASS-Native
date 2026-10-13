import Foundation

/// The Sprinklers page (web route `/at-a-glance/sprinklers`): the two Orbit B-hyve faucet controllers.
///
/// Source: `ha-sfenton-react-dash@9ac2a46:src/constants/sprinklers.ts`; copy from
/// `src/i18n/locales/en/pages/sprinklers.json`. State reading is in ``SprinklerSnapshot``.
public enum SprinklersConfig {
    /// One watering zone (a valve, its program switch and its history sensor).
    public struct Zone: Hashable, Sendable {
        public var historyEntityId: String
        public var programEntityId: String
        public var valveEntityId: String
    }

    /// One B-hyve controller.
    public struct Controller: Hashable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var batteryEntityId: String
        public var faultEntityId: String
        public var hubConnectedEntityId: String
        public var modeEntityId: String
        public var nextWateringEntityId: String
        public var rainDelayEntityId: String
        public var smartWateringEntityId: String
        public var stateEntityId: String
        public var zones: [Zone]
    }

    /// Shows the Sprinklers link on Home (web Quick Access `visibilityEntityId`).
    public static let visibilityEntityId = "input_boolean.show_outdoor_faucets"
    /// At or below this battery percent the controller warns.
    public static let lowBatteryPercent = 20.0
    /// Manual run time stepper (minutes).
    public static let manualRunTime = (default: 15, min: 1, max: 60)
    /// Watering budget stepper (percent).
    public static let budgetRange = (min: 0, max: 200, step: 5)
    /// A new start time's default.
    public static let defaultStartTime = "07:00"
    /// Optimistic values give way after this long (SprinklerController.tsx `OPTIMISTIC_REVERT_MS`).
    public static let optimisticRevert: Duration = .seconds(10)

    public static let frontYard = Controller(
        id: "frontYard",
        title: "Front Yard",
        batteryEntityId: "sensor.front_yard_battery_level",
        faultEntityId: "binary_sensor.front_yard_fault",
        hubConnectedEntityId: "binary_sensor.front_yard_hub_connected",
        modeEntityId: "select.front_yard_device_mode",
        nextWateringEntityId: "sensor.front_yard_next_watering",
        rainDelayEntityId: "switch.front_yard_rain_delay",
        smartWateringEntityId: "switch.front_yard_smart_watering",
        stateEntityId: "sensor.front_yard_state",
        zones: [
            Zone(historyEntityId: "sensor.front_yard_zone_history",
                 programEntityId: "switch.front_yard_front_yard_program",
                 valveEntityId: "valve.front_yard_zone"),
        ]
    )

    public static let backyard = Controller(
        id: "backyard",
        title: "Backyard Faucet",
        batteryEntityId: "sensor.backyard_faucet_battery_level",
        faultEntityId: "binary_sensor.backyard_faucet_fault",
        hubConnectedEntityId: "binary_sensor.wi_fi_hub_connected",
        modeEntityId: "select.backyard_faucet_device_mode",
        nextWateringEntityId: "sensor.backyard_faucet_next_watering",
        rainDelayEntityId: "switch.backyard_faucet_rain_delay",
        smartWateringEntityId: "switch.backyard_faucet_bushes_smart_watering",
        stateEntityId: "sensor.backyard_faucet_state",
        zones: [
            Zone(historyEntityId: "sensor.bushes_zone_history",
                 programEntityId: "switch.backyard_faucet_bushes_program",
                 valveEntityId: "valve.backyard_faucet_bushes_zone"),
            Zone(historyEntityId: "sensor.house_zone_history",
                 programEntityId: "switch.backyard_faucet_house_program",
                 valveEntityId: "valve.backyard_faucet_house_zone"),
            Zone(historyEntityId: "sensor.backyard_zone_history",
                 programEntityId: "switch.backyard_faucet_backyard_program",
                 valveEntityId: "valve.backyard_faucet_backyard_zone"),
            Zone(historyEntityId: "sensor.sidewalk_zone_history",
                 programEntityId: "switch.backyard_faucet_sidewalk_program",
                 valveEntityId: "valve.backyard_faucet_sidewalk_zone"),
        ]
    )

    /// Both controllers, front yard first (SprinklersPage.tsx).
    public static let controllers = [frontYard, backyard]

    // MARK: - Service calls (SprinklerController.tsx)

    /// Waters a zone for `minutes`.
    public static func startWatering(valve: String, minutes: Int) -> ServiceCall {
        ServiceCall("bhyve", "start_watering", data: ["entity_id": .string(valve), "minutes": .number(Double(minutes))])
    }

    /// Stops watering on a valve.
    public static func stopWatering(valve: String) -> ServiceCall {
        ServiceCall("bhyve", "stop_watering", data: ["entity_id": .string(valve)])
    }

    /// Runs a program now.
    public static func startProgram(_ program: String) -> ServiceCall {
        ServiceCall("bhyve", "start_program", data: ["entity_id": .string(program)])
    }

    /// Turns a switch (rain delay, smart watering or a program) on or off.
    public static func setSwitch(_ entityId: String, on: Bool) -> ServiceCall {
        ServiceCall("switch", on ? "turn_on" : "turn_off", target: entityId)
    }

    /// Saves a program's days (0 = Sunday), start times (`HH:mm`) and budget.
    public static func updateProgram(_ program: String, days: [Int], startTimes: [String], budget: Int) -> ServiceCall {
        ServiceCall("bhyve", "update_program", data: [
            "budget": .number(Double(budget)),
            "entity_id": .string(program),
            "frequency": .object(["days": .array(days.map { .number(Double($0)) }), "type": .string("days")]),
            "start_times": .array(startTimes.map(JSONValue.string)),
        ])
    }
}
