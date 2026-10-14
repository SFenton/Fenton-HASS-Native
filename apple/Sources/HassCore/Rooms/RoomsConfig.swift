import Foundation

/// The sixteen config-driven room pages, ported card for card.
///
/// Source: `ha-sfenton-react-dash@9ac2a46:src/constants/roomPages.ts:156` (`ROOM_PAGE_CONFIGS`). Bathroom fans,
/// the humidifier, the wake light and garage doors come from `bathroomFans.ts`, `humidifiers.ts`, `wakeLights.ts`
/// and `garageDoors.ts`.
public enum RoomsConfig {
    /// Every room page in web order.
    public static let pages: [RoomPage] = [
        livingRoom, guestRoom, masterBedroom, gym, hallway, office, kitchen, diningRoom,
        backDeck, musicRoom, theaterRoom, downstairsHallway, garage, guestBathroom, masterBathroom, entryway,
    ]

    /// The page for a web route path (`living-room`), if it is a room.
    public static func page(id: String) -> RoomPage? { pagesById[id] }

    private static let pagesById: [String: RoomPage] = Dictionary(uniqueKeysWithValues: pages.map { ($0.id, $0) })

    // MARK: - Shared entity ids

    /// Bathroom fan power switches and sheets (`bathroomFans.ts`).
    public enum BathroomFan {
        public static let guestPower = "switch.guest_bathroom_fan_switch_top"
        public static let guestSheet = "fan-guest-bathroom"
        public static let masterPower = "switch.master_bathroom_fan_switch_top"
        public static let masterSheet = "fan-master-bathroom"
    }

    /// The Master Bedroom humidifier (`MASTER_BEDROOM_HUMIDIFIER`, `humidifiers.ts:47`).
    public enum Humidifier {
        public static let powerEntityId = "switch.lv600s_humidifier_power"
        public static let currentHumidityEntityId = "sensor.lv600s_humidifier_current_humidity"
    }

    /// The Master Bedroom wake light (`MASTER_BEDROOM_WAKE_LIGHT`, `wakeLights.ts:28`).
    public enum WakeLight {
        public static let statusEntityId = "sensor.master_bedroom_wake_light"
        public static let sheet = "wake-light-alarms-master-bedroom"
        public static let title = "Wake-Light Alarms"
        public static let sectionTitle = "Sleep & Wake"
    }

    /// Garage door covers (`GARAGE_DOOR_ENTITY_IDS`).
    public enum GarageDoor {
        public static let left = "cover.garage_left_door"
        public static let right = "cover.garage_right_door"
    }

    /// The dishwasher's program select, which marks the dishwasher card (web `isDishwasherSourceCard`).
    public static let dishwasherProgramEntityId = "select.dishwasher_selected_program"

    /// Towel racks glow this color while on (web `stateColors`).
    static let towelRackOn = RoomColor(136, 64, 26, opacity: 0.6)

    // MARK: - Card builders

    static func lights(_ title: String, _ entityId: String, sheet: String?, icon: String = "mdi:lightbulb-group") -> RoomCard {
        RoomCard(title, entityId, icon: icon, kind: .light, sheet: sheet).with { $0.showState = true }
    }

    static func climate(_ entityId: String, sheet: String) -> RoomCard {
        RoomCard("Climate", entityId, icon: "mdi:thermometer", kind: .climate, sheet: sheet).with { $0.showState = true }
    }

    static func occupancy(_ entityId: String, sheet: String?) -> RoomCard {
        RoomCard("Occupancy", entityId, icon: "mdi:motion-sensor", kind: .occupancy, sheet: sheet).with { $0.showState = true }
    }

    static func contact(_ title: String, _ entityId: String, icon: String, sheet: String, showState: Bool = false) -> RoomCard {
        RoomCard(title, entityId, icon: icon, kind: .contact, sheet: sheet).with { $0.showState = showState }
    }

    static func airQuality(_ pm25EntityId: String) -> RoomCard {
        RoomCard("Air Quality", pm25EntityId, icon: "mdi:air-purifier", kind: .air, sheet: "air-purifier").with { $0.showState = true }
    }

    /// An air purifier card named by the purifier's entity prefix (`living_room_air_purifier`).
    static func purifier(_ prefix: String) -> RoomCard {
        RoomCard("Air Purifier", "select.\(prefix)_fan_mode", icon: "mdi:fan", kind: .air, sheet: "air-purifier").with {
            $0.modalEntityId = "sensor.\(prefix)_pm2_5"
            $0.subtitleEntityIds = ["select.\(prefix)_fan_mode", "fan.\(prefix)_levoit_purifier"]
        }
    }

    static func vents(_ title: String, _ entityId: String, items: [(String, String)]) -> RoomCard {
        RoomCard(title, entityId, icon: "mdi:air-filter", kind: .vent, sheet: "vents").with {
            $0.showState = true
            $0.modalItems = items.map { RoomModalItem($0.0, $0.1, icon: "mdi:air-filter") }
        }
    }

    /// A one-vent card whose sheet lists that vent.
    static func vent(_ entityId: String, title: String = "Vent") -> RoomCard {
        vents(title, entityId, items: [("Vent", entityId)])
    }

    static func vacuum(_ title: String, _ entityId: String) -> RoomCard {
        RoomCard(title, entityId, icon: "mdi:robot-vacuum", kind: .vacuum, sheet: "robot-vacuum").with {
            $0.modalTitle = "Robot Vacuum"
            $0.isFullWidth = true
        }
    }

    static func remoteOpener(_ title: String, _ entityId: String, icon: String, remote: String) -> RoomCard {
        RoomCard(title, entityId, icon: icon, kind: .media, sheet: remote).with {
            $0.semantics = .modal
            $0.showState = true
        }
    }

    static func pc(_ title: String, prefix: String, icon: String, resident: HouseholdResident? = nil) -> RoomCard {
        RoomCard(title, "input_boolean.\(prefix)_power", icon: icon, kind: .power).with {
            $0.subtitleEntityIds = ["input_text.\(prefix)_power_state"]
            $0.action = .remote(MediaRemotes.pcPowerAction(on: "input_button.\(prefix)_on", off: "input_button.\(prefix)_off"))
            $0.resident = resident
            $0.residentLabel = resident == nil ? nil : .pc
        }
    }

    static func towelRack(_ entityId: String) -> RoomCard {
        RoomCard("Towel Rack", entityId, icon: "mdi:heat-wave", kind: .light).with {
            $0.showState = true
            $0.stateColors = ["on": towelRackOn]
            $0.action = .flip
        }
    }

    static func bathroomFan(_ entityId: String, sheet: String) -> RoomCard {
        RoomCard("Fan", entityId, icon: "mdi:fan", kind: .fan, sheet: sheet).with {
            $0.control = .bathroomFan
            $0.showState = true
            $0.isFullWidth = true
        }
    }

    // MARK: - Pages

    static let livingRoom = RoomPage(
        id: "living-room", title: "Living Room",
        overviewCards: [
            lights("Lights", "light.living_room", sheet: "lights-living-room"),
            climate("input_text.living_room_climate_range", sheet: "climate-living-room"),
            occupancy("binary_sensor.living_room_occupancy_sensors", sheet: "living-room-occupancy"),
            contact("Window", "binary_sensor.living_room_window_contact_sensor_contact", icon: "mdi:window-closed", sheet: "window-living-room"),
            airQuality("sensor.living_room_air_purifier_pm2_5"),
        ],
        sections: [
            RoomSection("Climate", cards: [
                vents("Vents", "cover.living_room_vents", items: [("Vent 1", "cover.living_room_vent_1_vent"), ("Vent 2", "cover.living_room_vent_2_vent")]),
                purifier("living_room_air_purifier"),
            ]),
            RoomSection("Devices", cards: [vacuum("Main Floor", "vacuum.valetudo_exaltedsneakydeer")]),
            RoomSection("Remote", cards: [
                remoteOpener("Living Room Remote", "media_player.living_room_shield", icon: "mdi:remote", remote: "living-room-shield"),
            ]),
            RoomSection("Quick App Launch", layout: .appLaunch(remoteId: "living-room-shield")),
        ]
    )

    static let guestRoom = RoomPage(
        id: "guest-room", title: "Guest Room",
        overviewCards: [
            lights("Lights", "light.guest_room", sheet: "lights-guest-room"),
            climate("input_text.guest_room_climate_range", sheet: "climate-guest-room"),
            occupancy("binary_sensor.guest_room_occupancy_sensors", sheet: "guest-room-occupancy"),
            contact("Window", "binary_sensor.guest_room_window_contact_sensor_contact", icon: "mdi:window-closed", sheet: "window-guest-room"),
            airQuality("sensor.guest_room_air_purifier_pm2_5"),
        ],
        sections: [
            RoomSection("Climate", cards: [vent("cover.guest_room_vent_vent"), purifier("guest_room_air_purifier")]),
        ]
    )

    static let masterBedroom = RoomPage(
        id: "master-bedroom", title: "Master Bedroom",
        overviewCards: [
            lights("Lights", "light.master_bedroom", sheet: "lights-master-bedroom"),
            climate("input_text.master_bedroom_climate_range", sheet: "climate-master-bedroom"),
            occupancy("binary_sensor.master_bedroom_occupancy_sensors", sheet: "master-bedroom-occupancy"),
            contact("Window", "binary_sensor.master_bedroom_street_window_contact_sensor_contact", icon: "mdi:window-closed", sheet: "window-master-bedroom"),
            airQuality("sensor.master_bedroom_air_purifier_pm2_5"),
        ],
        sections: [
            RoomSection(WakeLight.sectionTitle, layout: .twoColumnFill, cards: [
                RoomCard(WakeLight.title, WakeLight.statusEntityId, icon: "mdi:weather-sunset-up", kind: .wakeLight, sheet: WakeLight.sheet).with {
                    $0.semantics = .modal
                    $0.showState = true
                },
            ]),
            RoomSection("SleepyPod", layout: .twoColumnFill, cards: [
                bed("Stephen's Bed", "climate.sleepypod_eight_pod_left_side", sheet: "stephens-bed", resident: .stephen),
                bed("Steph's Bed", "climate.sleepypod_eight_pod_right_side", sheet: "stephs-bed", resident: .steph),
            ]),
            RoomSection("Media", cards: [
                RoomCard("Apple TV", "media_player.master_bedroom_apple_tv", icon: "mdi:apple", kind: .media, sheet: "master-bedroom-apple-tv").with {
                    $0.showState = true
                    $0.isFullWidth = true
                    $0.activeStates = ["idle", "paused", "playing"]
                },
            ]),
            RoomSection("Climate", layout: .twoColumnFill, cards: [
                vents("Vents", "cover.master_bedroom_vents", items: [("Vent 1", "cover.master_bedroom_vent_2_vent"), ("Vent 2", "cover.master_bedroom_vent_3_vent")]),
                purifier("master_bedroom_air_purifier"),
                RoomCard("Humidifier", Humidifier.powerEntityId, icon: "mdi:air-humidifier", kind: .humidifier, sheet: "humidifier-master-bedroom").with {
                    $0.showState = true
                    $0.subtitleEntityIds = [Humidifier.powerEntityId, Humidifier.currentHumidityEntityId]
                },
            ]),
        ]
    )

    static func bed(_ title: String, _ entityId: String, sheet: String, resident: HouseholdResident) -> RoomCard {
        RoomCard(title, entityId, icon: "mdi:bed", kind: .climate, sheet: sheet).with {
            $0.resident = resident
            $0.residentLabel = .bedSide
            $0.showState = true
            $0.climateActionTone = true
        }
    }

    static let gym = RoomPage(
        id: "gym", title: "Gym",
        overviewCards: [
            lights("Light", "light.gym_light", sheet: "lights-gym", icon: "mdi:lightbulb"),
            climate("input_text.gym_climate_range", sheet: "climate-gym"),
            occupancy("binary_sensor.gym_presence_sensor_presence", sheet: "gym-occupancy"),
            contact("Window", "binary_sensor.gym_window_contact_sensor_contact", icon: "mdi:window-closed", sheet: "window-gym"),
        ],
        sections: [RoomSection("Climate", cards: [vent("cover.gym_vent_vent")])]
    )

    static let hallway = RoomPage(
        id: "hallway", title: "Hallway",
        overviewCards: [
            lights("Lights", "light.hallway_lights", sheet: "lights-hallway"),
            climate("input_text.hallway_climate_range", sheet: "climate-hallway"),
            occupancy("binary_sensor.hallway_occupancy_sensors", sheet: "hallway-occupancy"),
        ],
        sections: []
    )

    static let office = RoomPage(
        id: "office", title: "Office",
        overviewCards: [
            lights("Light", "light.office_light", sheet: "lights-office", icon: "mdi:lightbulb"),
            climate("input_text.office_climate_range", sheet: "climate-office"),
            occupancy("binary_sensor.office_occupancy_sensors", sheet: "office-occupancy"),
            contact("Windows", "binary_sensor.office_windows", icon: "mdi:window-closed", sheet: "windows-office"),
            airQuality("sensor.office_air_purifier_pm2_5"),
        ],
        sections: [
            RoomSection("Climate", cards: [vent("cover.office_vent_vent"), purifier("office_air_purifier")]),
            RoomSection("Office PCs", cards: [
                pc("Stephen's PC", prefix: "stephen_s_pc", icon: "mdi:controller", resident: .stephen),
                pc("Steph's PC", prefix: "steph_s_pc", icon: "mdi:controller", resident: .steph),
            ]),
        ]
    )

    static let kitchen = RoomPage(
        id: "kitchen", title: "Kitchen",
        overviewCards: [
            lights("Lights", "light.kitchen", sheet: "lights-kitchen"),
            climate("input_text.kitchen_climate_range", sheet: "climate-kitchen"),
            occupancy("binary_sensor.kitchen_presence_sensor_presence", sheet: "kitchen-occupancy"),
            contact("Door", "binary_sensor.kitchen_door_contact_sensor_contact", icon: "mdi:door", sheet: "door-kitchen"),
        ],
        sections: [
            RoomSection("Appliances", cards: [
                RoomCard("Dishwasher", dishwasherProgramEntityId, icon: "mdi:dishwasher", kind: .appliance, sheet: "dishwasher").with {
                    $0.isFullWidth = true
                    $0.subtitleEntityIds = ["sensor.dishwasher_door", dishwasherProgramEntityId]
                    $0.alternate = RoomCardAlternate(
                        whenEntityId: "sensor.dishwasher_operation_state", whenStates: ["run", "pause"],
                        entityId: "sensor.dishwasher_program_progress", showState: true,
                        subtitleEntityIds: [dishwasherProgramEntityId, "sensor.dishwasher_program_progress"])
                },
            ]),
            RoomSection("Climate", cards: [vent("cover.kitchen_vent_vent")]),
        ]
    )

    static let diningRoom = RoomPage(
        id: "dining-room", title: "Dining Room",
        overviewCards: [
            lights("Light", "light.dining_room_dimmer_switch", sheet: "lights-dining-room", icon: "mdi:lightbulb"),
            climate("input_text.dining_room_climate_range", sheet: "climate-dining-room"),
            occupancy("binary_sensor.dining_room_presence_sensor_presence", sheet: "dining-room-occupancy"),
            contact("Door", "binary_sensor.dining_room_door_contact_sensor_contact", icon: "mdi:door", sheet: "door-dining-room"),
        ],
        sections: [RoomSection("Climate", cards: [vent("cover.dining_room_vent_vent")])]
    )

    static let backDeck = RoomPage(
        id: "back-deck", title: "Back Deck",
        overviewCards: [
            lights("Lights", "light.back_deck", sheet: "lights-back-deck"),
            occupancy("binary_sensor.upper_deck_camera_person_occupancy", sheet: nil),
            contact("Doors", "binary_sensor.back_deck_doors", icon: "mdi:door", sheet: "doors-back-deck", showState: true),
        ],
        sections: [
            RoomSection("Grill", cards: [
                RoomCard("Bear Grills", "sensor.d8478fa2ad0a_grill_state", icon: "mdi:grill", kind: .grill, sheet: "bear-grills").with {
                    $0.showState = true
                    $0.disabledStates = ["off", "unavailable", "unknown"]
                    $0.stateLabels = ["off": "Off", "unavailable": "Off", "unknown": "Off"]
                },
            ]),
        ]
    )

    static let musicRoom: RoomPage = {
        typealias M = MediaRemotes.MusicRoom
        func source(_ title: String, icon: String, active: [String], action: MediaRemoteAction) -> RoomCard {
            RoomCard(title, M.activeMediaSourceEntityId, icon: icon, kind: .media).with {
                $0.showState = true
                $0.activeStates = active
                $0.stateLabels = Dictionary(uniqueKeysWithValues: M.Source.all.map { ($0, active.contains($0) ? "On" : "Off") })
                $0.semantics = .rule(.selectedWhen(active))
                $0.action = .remote(action)
            }
        }
        return RoomPage(
            id: "music-room", title: "Music Room",
            overviewCards: [
                lights("Lights", "light.music_room", sheet: "lights-music-room"),
                climate("input_text.music_room_climate_range", sheet: "climate-music-room"),
                occupancy("binary_sensor.music_room_occupancy_sensors", sheet: "music-room-occupancy"),
                contact("Door", "binary_sensor.music_room_door_contact_sensor_contact", icon: "mdi:door", sheet: "door-music-room"),
                airQuality("sensor.air_purifier_pm2_5"),
            ],
            sections: [
                RoomSection("Climate", cards: [vents("Vents", "cover.music_room_vent_vent", items: [("Vent", "cover.music_room_vent_vent")]), purifier("air_purifier")]),
                RoomSection("Remote", layout: .leadRow, cards: [
                    remoteOpener("Music Room Remote", M.controlEntityId, icon: "mdi:remote", remote: "music-room-remote"),
                    source("Xbox", icon: "mdi:microsoft-xbox", active: [M.Source.xbox, M.Source.fortnite], action: M.xboxSourceToggle),
                    source("Server", icon: "mdi:server", active: [M.Source.server], action: M.serverToggle),
                    source("Windows PC", icon: "mdi:microsoft-windows", active: [M.Source.windowsPC], action: M.windowsPCToggle),
                ]),
                RoomSection("Quick App Launch", layout: .appLaunch(remoteId: "music-room-remote"), showOnRoomPage: false),
                RoomSection("Devices", cards: [vacuum("Music Room", "vacuum.valetudo_elatedusedram")]),
            ],
            optimisticRemoteId: "music-room-remote"
        )
    }()

    static let theaterRoom = RoomPage(
        id: "theater-room", title: "Theater Room",
        overviewCards: [
            lights("Lights", "light.theater_room", sheet: "lights-theater-room"),
            climate("input_text.theater_room_climate_range", sheet: "climate-theater-room"),
            occupancy("binary_sensor.theater_room_presence_sensor_presence", sheet: "theater-room-occupancy"),
            contact("Door", "binary_sensor.theater_room_door_contact_sensor_contact", icon: "mdi:door", sheet: "door-theater-room"),
            airQuality("sensor.theater_room_air_purifier_pm2_5"),
        ],
        sections: [
            RoomSection("Climate", cards: [
                vents("Vents", "cover.theater_room_vents", items: [("Vent 1", "cover.theater_room_vent_1_vent"), ("Vent 2", "cover.theater_room_vent_2_vent")]),
                purifier("theater_room_air_purifier"),
            ]),
            RoomSection("Remote", layout: .leadRow, cards: [
                remoteOpener("Theater Room Remote", "media_player.sony_projector", icon: "mdi:projector", remote: "theater-room-shield"),
                RoomCard("Nintendo Switch", "input_boolean.is_nintendo_switch_active", icon: "mdi:gamepad", kind: .media).with {
                    $0.semantics = .command
                    $0.showState = true
                    $0.action = .remote(.service("script", "theater_room_nintendo_switch"))
                },
                RoomCard("Theater SHIELD", "input_boolean.is_theater_shield_active", icon: "mdi:television", kind: .media).with {
                    $0.semantics = .command
                    $0.showState = true
                    $0.action = .remote(.service("script", "theater_room_tv_movie"))
                },
            ]),
            RoomSection("Quick App Launch", layout: .appLaunch(remoteId: "theater-room-shield")),
            RoomSection("Theater Room PCs", cards: [pc("Theater Room PC", prefix: "theater_pc", icon: "mdi:projector")]),
            RoomSection("Devices", cards: [vacuum("Theater Room", "vacuum.valetudo_politefatherlykingfisher")]),
        ]
    )

    static let downstairsHallway = RoomPage(
        id: "downstairs-hallway", title: "Downstairs Hallway",
        overviewCards: [
            lights("Light", "light.downstairs_hallway_light", sheet: "light-downstairs-hallway", icon: "mdi:lightbulb"),
            climate("input_text.downstairs_hallway_climate_range", sheet: "climate-downstairs-hallway"),
            occupancy("binary_sensor.downstairs_hallway_presence_sensor_presence", sheet: "downstairs-hallway-occupancy"),
            contact("Door", "binary_sensor.garage_door_contact_sensor_contact", icon: "mdi:door", sheet: "door-downstairs-hallway"),
        ],
        sections: []
    )

    static let garage = RoomPage(
        id: "garage", title: "Garage",
        overviewCards: [
            contact("Doors", "binary_sensor.garage_doors", icon: "mdi:door", sheet: "doors-garage", showState: true),
        ],
        sections: [
            RoomSection("Appliances", cards: [
                RoomCard("Washing Machine", "input_boolean.washer_started_helper", icon: "mdi:washing-machine", kind: .laundry).with { $0.showState = true },
                RoomCard("Dryer", "input_boolean.dryer_started_helper", icon: "mdi:tumble-dryer", kind: .laundry).with { $0.showState = true },
            ]),
            RoomSection("Garage Doors", cards: [
                RoomCard("Left Door", GarageDoor.left, icon: "mdi:garage", kind: .contact).with { $0.showState = true; $0.control = .garageDoor },
                RoomCard("Right Door", GarageDoor.right, icon: "mdi:garage", kind: .contact).with { $0.showState = true; $0.control = .garageDoor },
            ]),
        ]
    )

    static let guestBathroom = RoomPage(
        id: "guest-bathroom", title: "Guest Bathroom",
        overviewCards: [
            lights("Light", "light.guest_bathroom_dimmer_switch", sheet: "lights-guest-bathroom", icon: "mdi:lightbulb"),
            climate("input_text.all_climate_range", sheet: "climate-overview"),
            occupancy("binary_sensor.guest_bathroom_occupancy_sensors", sheet: "guest-bathroom-occupancy"),
        ],
        sections: [
            RoomSection("Climate", layout: .leadRow, cards: [
                bathroomFan(BathroomFan.guestPower, sheet: BathroomFan.guestSheet),
                vent("cover.guest_bathroom_vent_vent"),
                towelRack("switch.guest_bathroom_towel_rack_switch_top"),
            ]),
        ]
    )

    static let masterBathroom = RoomPage(
        id: "master-bathroom", title: "Master Bathroom",
        overviewCards: [
            lights("Light", "light.master_bathroom_dimmer_switch", sheet: "lights-master-bathroom", icon: "mdi:lightbulb"),
            climate("input_text.all_climate_range", sheet: "climate-overview"),
            occupancy("binary_sensor.master_bathroom_presence_sensor_presence", sheet: "master-bathroom-occupancy"),
        ],
        sections: [
            RoomSection("Climate", layout: .leadRow, cards: [
                bathroomFan(BathroomFan.masterPower, sheet: BathroomFan.masterSheet),
                vent("cover.master_bathroom_vent_vent"),
                towelRack("switch.master_bathroom_towel_rack_switch_top"),
            ]),
        ]
    )

    static let entryway = RoomPage(
        id: "entryway", title: "Entryway",
        overviewCards: [
            lights("Light", "switch.upper_entryway_light_switch_top", sheet: "lights-entryway", icon: "mdi:lightbulb"),
            occupancy("binary_sensor.entryway_presence_sensors", sheet: "entryway-occupancy"),
            climate("input_text.front_door_climate_range", sheet: "climate-overview"),
            contact("Door", "binary_sensor.front_door_contact_sensor_contact", icon: "mdi:door", sheet: "door-entryway"),
        ],
        sections: []
    )
}

// MARK: - Builder

extension RoomCard {
    /// A copy with `change` applied, so configs read like the web's object literals.
    func with(_ change: (inout RoomCard) -> Void) -> RoomCard {
        var copy = self
        change(&copy)
        return copy
    }
}

// MARK: - Kitchen groceries

public extension RoomsConfig {
    /// The Kitchen page's Groceries section (web `KitchenGroceriesSection`, `DashboardViewPage.tsx:1823`).
    enum Groceries {
        /// The grocery to-do list (`TODO_PAGES.groceries.lists[0]`, `portedDashboard.ts:458`).
        public static let listEntityId = ChoresConfig.groceryEntityId
        public static let listTitle = "Grocery List"
        /// The grocery tile's wash.
        public static let listBackground = RoomColor(155, 67, 72, opacity: 0.72)

        /// "3 items", or "No groceries listed" (web `groceryCountSubtitle`).
        public static func subtitle(count state: String?) -> String {
            let count = state.flatMap(Double.init).map { Int($0) } ?? 0
            guard count > 0 else { return "No groceries listed" }
            return "\(count) \(count == 1 ? "item" : "items")"
        }
    }
}
