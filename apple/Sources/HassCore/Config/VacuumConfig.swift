import Foundation

/// One robot vacuum and the Home Assistant entities around it (web `VacuumConfig`).
///
/// Source: `ha-sfenton-react-dash@9ac2a46:src/constants/portedDashboard.ts:99` and `VACUUMS` (`:516`).
public struct VacuumConfig: Sendable, Identifiable, Hashable {
    /// Drawing a rectangle on the map and cleaning only that area.
    public struct AreaCleaning: Sendable, Hashable {
        /// The smallest side of a drawn area, in centimetres.
        public var minimumSizeCm: Double
        /// Script that cleans a zone (`x_min_cm`, `x_max_cm`, `y_min_cm`, `y_max_cm`).
        public var script: String
    }

    /// The mop dock's wash and dry actions.
    public struct DockControls: Sendable, Hashable {
        public var cleanScript: String
        public var dockStatusEntityId: String
        public var dryScript: String
        public var mopAttachmentEntityId: String
    }

    /// One consumable or dock-component sensor.
    public struct Consumable: Sendable, Hashable, Identifiable {
        /// Minutes remaining, or an `ok`-style status.
        public enum ValueKind: Sendable, Hashable { case duration, status }
        public var title: String
        public var entityId: String
        public var icon: String
        public var valueKind: ValueKind
        public var id: String { entityId }
    }

    /// One selectable room (an `input_boolean` the clean script reads).
    public struct Zone: Sendable, Hashable, Identifiable {
        public var title: String
        public var entityId: String
        public var icon: String
        /// The Valetudo segment name, when it differs from ``title``.
        public var mapName: String?
        /// Whether the room needs mopping when no live hint says otherwise.
        public var mopRequired: Bool?
        /// A coordinator sensor whose `mop_required` attribute overrides ``mopRequired``.
        public var mopRequiredEntityId: String?
        public var id: String { entityId }

        /// The segment name on the Valetudo map.
        public var segmentName: String { mapName ?? title }
    }

    /// A room the away-clean coordinator can be told to skip.
    public struct AutoCleanRoom: Sendable, Hashable, Identifiable {
        public var title: String
        public var entityId: String
        public var icon: String
        public var id: String { entityId }
    }

    /// Segments the map may crop to when nothing outside them matters (web `VacuumMapFocusConfig`).
    public struct MapFocus: Sendable, Hashable {
        public struct Segment: Sendable, Hashable {
            public var id: String
            public var name: String?
        }
        public var maximumViewAreaRatio: Double?
        public var minimumExcludedAreaM2: Double?
        public var minimumExcludedFraction: Double?
        public var paddingCm: Double?
        public var requiredSegments: [Segment]
        public var wallAssociationCm: Double?
    }

    public var title: String
    public var entityId: String
    public var batteryEntityId: String
    public var cleanScript: String
    public var consumables: [Consumable]
    public var coordinatorSessionEntityId: String?
    public var dockButtonEntityId: String?
    public var dockControls: DockControls?
    public var errorEntityId: String
    public var fanEntityId: String?
    public var areaCleaning: AreaCleaning?
    public var autoCleanDisabledRooms: [AutoCleanRoom]
    public var mapFocus: MapFocus?
    public var mapRoomSelection: Bool
    public var mapRotationDegrees: Double
    public var mapScale: Double
    public var modeEntityId: String?
    public var modeTextEntityId: String?
    public var outcomeRoomNames: [String: String]
    public var passesEntityId: String
    public var statusEntityId: String
    public var statusFlagEntityId: String
    /// The Valetudo id, e.g. `valetudo_exaltedsneakydeer`.
    public var vacuumMapId: String
    public var waterEntityId: String?
    public var zoneDescription: [String]
    public var zones: [Zone]

    public var id: String { entityId }

    /// The camera entity whose image carries the Valetudo map (`mapCameraEntityId`).
    public var mapCameraEntityId: String { "camera.\(vacuumMapId)_map_data" }
}

/// The house's robot vacuums and auto-clean switches.
public enum Vacuums {
    // MARK: - Builders

    /// Valetudo's consumable sensors (`VALETUDO_CONSUMABLES`, portedDashboard.ts:354).
    static func consumables(_ mapId: String) -> [VacuumConfig.Consumable] {
        [
            ("Main Brush", "main_brush", "mdi:brush", VacuumConfig.Consumable.ValueKind.duration),
            ("Side Brush", "right_brush", "mdi:brush-variant", .duration),
            ("Main Filter", "main_filter", "mdi:air-filter", .duration),
            ("Sensors", "sensor_cleaning", "mdi:radar", .duration),
            ("Wheels", "wheel_cleaning", "mdi:tire", .duration),
            ("Dustbag", "dustbag_dock_component", "mdi:delete", .status),
            ("Fresh Water", "freshwater_dock_component", "mdi:water", .status),
            ("Waste Water", "wastewater_dock_component", "mdi:water-off", .status),
            ("Detergent", "detergent_dock_component", "mdi:bottle-tonic", .status),
        ].map { .init(title: $0.0, entityId: "sensor.\(mapId)_\($0.1)", icon: $0.2, valueKind: $0.3) }
    }

    static func dockControls(_ prefix: String, _ mapId: String) -> VacuumConfig.DockControls {
        .init(cleanScript: "script.\(prefix)_vacuum_mop_dock_clean",
              dockStatusEntityId: "sensor.\(mapId)_dock_status",
              dryScript: "script.\(prefix)_vacuum_mop_dock_dry",
              mopAttachmentEntityId: "binary_sensor.\(mapId)_mop_attachment")
    }

    private static func mainFloorZone(_ title: String, _ roomId: String, _ entityId: String, _ icon: String, mapName: String? = nil) -> VacuumConfig.Zone {
        .init(title: title, entityId: entityId, icon: icon, mapName: mapName ?? title,
              mopRequiredEntityId: "sensor.main_floor_vacuum_coordinator_\(roomId)_last_cleaned")
    }

    private static func mainFloorAutoClean(_ title: String, _ roomId: String, _ icon: String) -> VacuumConfig.AutoCleanRoom {
        .init(title: title, entityId: "switch.main_floor_vacuum_coordinator_\(roomId)_auto_clean_disabled", icon: icon)
    }

    // MARK: - Vacuums

    public static let musicRoom = VacuumConfig(
        title: "Music Room",
        entityId: "vacuum.valetudo_elatedusedram",
        batteryEntityId: "sensor.valetudo_elatedusedram_battery_level",
        cleanScript: "script.music_room_vacuum_clean_selected_segments",
        consumables: consumables("valetudo_elatedusedram"),
        dockButtonEntityId: "button.valetudo_elatedusedram_trigger_auto_empty_dock",
        dockControls: dockControls("music_room", "valetudo_elatedusedram"),
        errorEntityId: "sensor.valetudo_elatedusedram_error",
        fanEntityId: "select.valetudo_elatedusedram_fan",
        areaCleaning: .init(minimumSizeCm: 25, script: "script.music_room_vacuum_clean_zone"),
        autoCleanDisabledRooms: [],
        mapFocus: .init(paddingCm: 15, requiredSegments: [
            .init(id: "3", name: "Music Room"),
            .init(id: "10", name: "Downstairs Hallway"),
            .init(id: "12", name: "Downstairs Bathroom"),
        ], wallAssociationCm: 20),
        mapRoomSelection: true,
        mapRotationDegrees: 0,
        mapScale: 2.4,
        modeEntityId: "select.valetudo_elatedusedram_mode",
        modeTextEntityId: "input_text.music_room_vacuum_mode",
        outcomeRoomNames: [:],
        passesEntityId: "input_select.music_room_vacuum_cleaning_passes",
        statusEntityId: "sensor.music_room_vacuum_status",
        statusFlagEntityId: "sensor.valetudo_elatedusedram_status_flag",
        vacuumMapId: "valetudo_elatedusedram",
        waterEntityId: "select.valetudo_elatedusedram_water",
        zoneDescription: [
            "Select any zones to focus cleaning in those areas. If you press clean and no zones are selected, we will clean all zones in the Music Room.",
            "Zones are not selectable or changeable while cleaning is ongoing.",
        ],
        zones: [
            .init(title: "Clean Music Room", entityId: "input_boolean.clean_music_room", icon: "mdi:guitar-electric", mapName: "Music Room", mopRequired: true),
            .init(title: "Clean Downstairs Hallway", entityId: "input_boolean.clean_downstairs_hallway", icon: "mdi:wardrobe", mapName: "Downstairs Hallway", mopRequired: true),
            .init(title: "Clean Downstairs Bathroom", entityId: "input_boolean.clean_downstairs_bathroom", icon: "mdi:shower-head", mapName: "Downstairs Bathroom", mopRequired: true),
        ]
    )

    public static let theaterRoom = VacuumConfig(
        title: "Theater Room",
        entityId: "vacuum.valetudo_politefatherlykingfisher",
        batteryEntityId: "sensor.valetudo_politefatherlykingfisher_battery_level",
        cleanScript: "script.theater_room_vacuum_clean_selected_segments",
        consumables: consumables("valetudo_politefatherlykingfisher"),
        dockButtonEntityId: "button.valetudo_politefatherlykingfisher_trigger_auto_empty_dock",
        dockControls: dockControls("theater_room", "valetudo_politefatherlykingfisher"),
        errorEntityId: "sensor.valetudo_politefatherlykingfisher_error",
        fanEntityId: "select.valetudo_politefatherlykingfisher_fan",
        areaCleaning: .init(minimumSizeCm: 25, script: "script.theater_room_vacuum_clean_zone"),
        autoCleanDisabledRooms: [],
        mapRoomSelection: false,
        mapRotationDegrees: 0,
        mapScale: 2.4,
        modeEntityId: "select.valetudo_politefatherlykingfisher_mode",
        outcomeRoomNames: [:],
        passesEntityId: "input_select.theater_room_vacuum_cleaning_passes",
        statusEntityId: "sensor.theater_room_vacuum_status",
        statusFlagEntityId: "sensor.valetudo_politefatherlykingfisher_status_flag",
        vacuumMapId: "valetudo_politefatherlykingfisher",
        waterEntityId: "select.valetudo_politefatherlykingfisher_water",
        zoneDescription: [],
        zones: []
    )

    public static let mainFloor = VacuumConfig(
        title: "Main Floor",
        entityId: "vacuum.valetudo_exaltedsneakydeer",
        batteryEntityId: "sensor.valetudo_exaltedsneakydeer_battery_level",
        cleanScript: "script.main_floor_vacuum_clean_selected_segments",
        consumables: consumables("valetudo_exaltedsneakydeer"),
        coordinatorSessionEntityId: "sensor.main_floor_vacuum_coordinator_session_state",
        dockButtonEntityId: "button.valetudo_exaltedsneakydeer_trigger_auto_empty_dock",
        dockControls: dockControls("main_floor", "valetudo_exaltedsneakydeer"),
        errorEntityId: "sensor.valetudo_exaltedsneakydeer_error",
        fanEntityId: "select.valetudo_exaltedsneakydeer_fan",
        areaCleaning: .init(minimumSizeCm: 25, script: "script.main_floor_vacuum_clean_zone"),
        autoCleanDisabledRooms: [
            mainFloorAutoClean("Living Room", "living_room", "mdi:sofa"),
            mainFloorAutoClean("Master Bedroom", "master_bedroom", "mdi:bed-double"),
            mainFloorAutoClean("Kitchen", "kitchen", "mdi:fridge"),
            mainFloorAutoClean("Office", "office", "mdi:laptop"),
            mainFloorAutoClean("Hallway", "hallway", "mdi:wardrobe"),
            mainFloorAutoClean("Guest Room", "guest_room", "mdi:bed"),
            mainFloorAutoClean("Master Bathroom", "master_bathroom", "mdi:shower"),
            mainFloorAutoClean("Guest Bathroom", "guest_bathroom", "mdi:shower"),
            mainFloorAutoClean("Gym", "gym", "mdi:weight-lifter"),
            mainFloorAutoClean("Closet", "master_bedroom_closet", "mdi:wardrobe"),
            mainFloorAutoClean("Dining Room", "dining_room", "mdi:silverware-fork-knife"),
        ],
        mapRoomSelection: true,
        mapRotationDegrees: 180,
        mapScale: 1.2,
        modeEntityId: "select.valetudo_exaltedsneakydeer_mode",
        modeTextEntityId: "input_text.main_floor_vacuum_mode",
        outcomeRoomNames: [
            "dining_room": "Dining Room", "guest_bathroom": "Guest Bathroom", "guest_room": "Guest Room",
            "gym": "Gym", "hallway": "Hallway", "kitchen": "Kitchen", "living_room": "Living Room",
            "master_bathroom": "Master Bathroom", "master_bedroom": "Master Bedroom",
            "master_bedroom_closet": "Master Bedroom Closet", "office": "Office",
        ],
        passesEntityId: "input_select.main_floor_vacuum_cleaning_passes",
        statusEntityId: "sensor.main_floor_vacuum_status",
        statusFlagEntityId: "sensor.valetudo_exaltedsneakydeer_status_flag",
        vacuumMapId: "valetudo_exaltedsneakydeer",
        waterEntityId: "select.valetudo_exaltedsneakydeer_water",
        zoneDescription: [
            "Select any zones to focus cleaning in those areas. If you press clean and no zones are selected, we will clean all zones on the Main Floor.",
            "Zones are not selectable or changeable while cleaning is ongoing.",
        ],
        zones: [
            mainFloorZone("Living Room", "living_room", "input_boolean.roborock_living_room_toggle", "mdi:sofa"),
            mainFloorZone("Master Bedroom", "master_bedroom", "input_boolean.roborock_master_bedroom_toggle", "mdi:bed-double"),
            mainFloorZone("Kitchen", "kitchen", "input_boolean.roborock_kitchen_toggle", "mdi:fridge"),
            mainFloorZone("Office", "office", "input_boolean.roborock_office_toggle", "mdi:laptop"),
            mainFloorZone("Hallway", "hallway", "input_boolean.roborock_hallway_toggle", "mdi:wardrobe"),
            mainFloorZone("Guest Room", "guest_room", "input_boolean.roborock_guest_room_toggle", "mdi:bed"),
            mainFloorZone("Master Bathroom", "master_bathroom", "input_boolean.roborock_master_bathroom_toggle", "mdi:shower"),
            mainFloorZone("Guest Bathroom", "guest_bathroom", "input_boolean.roborock_guest_bathroom_toggle", "mdi:shower"),
            mainFloorZone("Gym", "gym", "input_boolean.roborock_gym_toggle", "mdi:weight-lifter"),
            mainFloorZone("Closet", "master_bedroom_closet", "input_boolean.roborock_master_bedroom_closet_toggle", "mdi:wardrobe", mapName: "Master Bedroom Closet"),
            mainFloorZone("Dining Room", "dining_room", "input_boolean.roborock_dining_room_toggle", "mdi:silverware-fork-knife"),
        ]
    )

    // MARK: - Page

    /// One Auto-Clean tile (`VACUUM_AUTO_CLEAN_CONTROLS`, `src/constants/vacuumAutoClean.ts`).
    public struct AutoCleanControl: Sendable, Hashable, Identifiable {
        /// A plain automation (on = enabled), or the Main Floor coordinator's pause switch (off = enabled).
        public enum Kind: Sendable, Hashable { case automation, mainFloorPause }
        public var title: String
        public var entityId: String
        public var icon: String
        public var kind: Kind
        public var id: String { entityId }

        /// Whether auto-clean runs for this state.
        public func isEnabled(state: String) -> Bool {
            kind == .mainFloorPause ? state == "off" : state == "on"
        }

        /// The service domain that flips it.
        public var domain: String { kind == .automation ? "automation" : "switch" }
    }

    /// Auto-Clean tiles in web order; it also orders the vacuum tiles (`ORDERED_VACUUMS`).
    public static let autoCleanControls: [AutoCleanControl] = [
        .init(title: "Main Floor", entityId: "switch.main_floor_vacuum_coordinator_pause", icon: "mdi:robot-vacuum", kind: .mainFloorPause),
        .init(title: "Music Room", entityId: "automation.automatically_vacuum_or_mop_music_room", icon: "mdi:robot-vacuum", kind: .automation),
        .init(title: "Theater Room", entityId: "automation.automatically_vacuum_theater_room_on_schedule", icon: "mdi:robot-vacuum", kind: .automation),
    ]

    /// Vacuums in page order: Auto-Clean order, then title (`DashboardViewPage.tsx:346`).
    public static let all: [VacuumConfig] = {
        let order = Dictionary(uniqueKeysWithValues: autoCleanControls.enumerated().map { ($1.title, $0) })
        return [musicRoom, theaterRoom, mainFloor].sorted {
            let left = order[$0.title] ?? .max, right = order[$1.title] ?? .max
            return left != right ? left < right : $0.title < $1.title
        }
    }()

    /// Finds a vacuum by entity id.
    public static func config(entityId: String) -> VacuumConfig? { all.first { $0.entityId == entityId } }

    /// `input_text` markers that reconcile a failed outcome room as done (`VACUUM_OUTCOME_RECONCILIATIONS`, portedDashboard.ts:844).
    public static func outcomeReconciliations(_ vacuumMapId: String) -> [(roomId: String, entityId: String)] {
        guard vacuumMapId == mainFloor.vacuumMapId else { return [] }
        return ["living_room", "master_bedroom", "kitchen", "office", "hallway", "guest_room", "master_bathroom",
                "guest_bathroom", "gym", "master_bedroom_closet", "dining_room"]
            .map { ($0, "input_text.main_floor_vacuum_\($0)_reconciled_attempt") }
    }
}
