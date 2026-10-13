import Foundation

// MARK: - Room grid

/// One tile in the room navigation grid (web `RoomNavigationConfig`).
public struct RoomNavigationItem: Hashable, Sendable, Identifiable {
    public var title: String
    /// The room page's web path.
    public var path: String
    /// Web MDI icon.
    public var icon: String
    public var color: RoomColor
    /// The key `script.increment_room_access` counts under.
    public var accessKey: String
    /// The counter that ranks the grid.
    public var accessCounterEntityId: String

    public var id: String { path }
}

/// The Rooms grid in Quick Links, ranked by how often each room is opened.
///
/// Source: `ha-sfenton-react-dash@9ac2a46:src/constants/atAGlance.ts:324` (`AREA_ITEMS`),
/// `src/components/hass/RoomNavigationGrid.tsx`, `roomAccessRanking.ts`.
public enum RoomNavigation {
    /// The script that counts a room visit (`ROOM_ACCESS_INCREMENT_SCRIPT_ENTITY_ID`).
    public static let accessIncrementScript = "script.increment_room_access"

    /// Rooms in configured order.
    public static let items: [RoomNavigationItem] = [
        item("Living Room", "living-room", "mdi:sofa", (218, 206, 164)),
        item("Guest Room", "guest-room", "mdi:bed", (51, 193, 146)),
        item("Gym", "gym", "mdi:dumbbell", (213, 117, 26)),
        item("Master Bedroom", "master-bedroom", "mdi:bed-king", (20, 33, 215)),
        item("Office", "office", "mdi:desktop-tower", (20, 219, 206)),
        item("Hallway", "hallway", "mdi:door-open", (65, 49, 31)),
        item("Kitchen", "kitchen", "mdi:stove", (177, 200, 60)),
        item("Music Room", "music-room", "mdi:music", (183, 18, 186)),
        item("Garage", "garage", "mdi:garage", (223, 12, 12)),
        item("Theater Room", "theater-room", "mdi:movie-open", (0, 0, 1)),
        item("Back Deck", "back-deck", "mdi:grill", (5, 77, 6)),
        item("Downstairs Hallway", "downstairs-hallway", "mdi:stairs", (234, 236, 203)),
        item("Guest Bathroom", "guest-bathroom", "mdi:shower", (43, 227, 224)),
        item("Master Bathroom", "master-bathroom", "mdi:bathtub", (95, 93, 93)),
        item("Dining Room", "dining-room", "mdi:silverware-fork-knife", (217, 179, 115)),
        item("Entryway", "entryway", "mdi:door", (250, 217, 0)),
    ]

    /// The grid item for a room path.
    public static func item(for path: String) -> RoomNavigationItem? { items.first { $0.path == path } }

    private static func item(_ title: String, _ path: String, _ icon: String, _ rgb: (Double, Double, Double)) -> RoomNavigationItem {
        let key = path.replacingOccurrences(of: "-", with: "_")
        return RoomNavigationItem(title: title, path: path, icon: icon, color: RoomColor(rgb.0, rgb.1, rgb.2),
                                  accessKey: path, accessCounterEntityId: "counter.room_access_\(key)")
    }

    /// A counter's visit count: a non-negative whole-number state ("3" or "3.0", like JavaScript's `Number`), else 0
    /// (web `roomAccessCount`).
    public static func accessCount(_ state: String?) -> Int {
        guard let text = state?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let value = Double(text), value >= 0, value <= 9_007_199_254_740_991, value.rounded() == value else { return 0 }
        return Int(value)
    }

    /// Rooms most-visited first; ties keep configured order (web `rankRoomsByAccess`).
    /// - Parameter counterState: Reads a counter entity's state.
    public static func ranked(counterState: (String) -> String?) -> [RoomNavigationItem] {
        items.enumerated()
            .map { (index: $0.offset, count: accessCount(counterState($0.element.accessCounterEntityId)), item: $0.element) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.index < $1.index }
            .map(\.item)
    }

    /// The call that counts a visit when a room is opened from the grid (web `RoomNavigationGrid.handleNavigate`).
    public static func accessIncrementCall(for item: RoomNavigationItem) -> ServiceCall {
        ServiceCall("script", "turn_on", target: accessIncrementScript,
                    data: ["variables": .object(["room": .string(item.accessKey)])])
    }
}

// MARK: - Quick Links

/// One Quick Links tile (web `QuickAccessConfig`).
public struct QuickLink: Hashable, Sendable, Identifiable {
    /// What the tile does.
    public enum Action: Hashable, Sendable {
        /// Opens a page inside the Quick Links sheet.
        case detail(Detail)
        /// Navigates to a web route path.
        case navigate(String)
    }

    /// In-sheet pages (web `QuickAccessModalPage`).
    public enum Detail: String, Hashable, Sendable {
        case rooms
        case securitySystem = "security-system"
    }

    /// How the subtitle is computed (web `status`).
    public enum Status: Hashable, Sendable {
        /// The entity's compact state.
        case entityState
        /// The pantry summary (Food lane).
        case allFood
    }

    public var id: String
    public var title: String
    public var icon: String
    public var tone: RoomTone
    public var action: Action
    public var entityId: String?
    public var status: Status?
    /// Shown only while this entity is `on`.
    public var visibilityEntityId: String?
    /// A fixed background wash (Food).
    public var backgroundColor: RoomColor?
}

/// The Quick Links sheet's tiles, in web order.
///
/// Source: `ha-sfenton-react-dash@9ac2a46:src/constants/atAGlance.ts:220-279` (`QUICK_ACCESS_ITEMS`) and
/// `src/components/shell/GlobalQuickLinksAction.tsx`.
public enum QuickLinks {
    /// The sheet's title (`shell.json` `quickLinks.title`).
    public static let title = "Quick Links"
    /// The alarm panel the Security System tile reflects.
    public static let securityEntityId = "alarm_control_panel.aqara_hub_m3_0056_security_system_2"

    public static let items: [QuickLink] = [
        QuickLink(id: "rooms", title: "Rooms", icon: "mdi:floor-plan", tone: .climate, action: .detail(.rooms)),
        QuickLink(id: "security-system", title: "Security System", icon: "mdi:shield-outline", tone: .neutral,
                  action: .detail(.securitySystem), entityId: securityEntityId, status: .entityState),
        QuickLink(id: "food", title: "Food & Recipes", icon: "mdi:food-fork-drink", tone: .neutral, action: .navigate("food"),
                  status: .allFood, backgroundColor: foodBackground),
        QuickLink(id: "vacuums", title: "Vacuums", icon: "mdi:robot-vacuum", tone: .vacuum, action: .navigate("vacuums")),
        QuickLink(id: "media", title: "Media", icon: "mdi:remote", tone: .media, action: .navigate("media")),
        QuickLink(id: "custom-lights", title: "Custom Lights", icon: "mdi:lightbulb-group", tone: .light, action: .navigate("custom-lights")),
        QuickLink(id: "sprinklers", title: "Sprinklers", icon: "mdi:sprinkler-variant", tone: .neutral, action: .navigate("sprinklers"),
                  visibilityEntityId: SprinklersConfig.visibilityEntityId),
    ]

    /// `FOOD_CARD_BACKGROUND_COLOR` (`everShelfFood.ts:10`).
    public static let foodBackground = RoomColor(155, 110, 64, opacity: 0.72)

    // MARK: Subtitles

    /// EverShelf counters (`everShelfFood.ts:11-21`).
    public static let totalItemsEntityId = "sensor.evershelf_total_items"
    public static let expiringSoonEntityId = "sensor.evershelf_expiring_soon"
    public static let foodSpaceEntityIds = [
        "sensor.evershelf_items_in_pantry", "sensor.evershelf_items_in_fridge", "sensor.evershelf_items_in_freezer",
        "sensor.kitchen_evershelf_items_in_spice_rack", "sensor.kitchen_evershelf_items_in_cabinet",
    ]

    /// "12 Items • 2 Expiring Soon" (web `allFoodSubtitle`): the total counter, else the sum of the spaces.
    public static func allFoodSubtitle(state: (String) -> String?) -> String {
        func count(_ id: String) -> Int { state(id).flatMap(Double.init).map { Int($0) } ?? 0 }
        let total = count(totalItemsEntityId)
        let items = total != 0 ? total : foodSpaceEntityIds.map(count).reduce(0, +)
        let expiring = count(expiringSoonEntityId)
        return "\(items) \(items == 1 ? "Item" : "Items") • \(expiring) Expiring Soon"
    }

    /// The Security System tile's look for an alarm state (web `securityState.ts`).
    public static func securityAppearance(_ state: String?) -> (icon: String, color: RoomColor) {
        switch state {
        case "armed_away": ("mdi:shield", RoomColor(229, 57, 53))
        case "armed_home": ("mdi:shield-home", RoomColor(30, 136, 229))
        case "armed_night": ("mdi:shield-moon", RoomColor(142, 36, 170))
        case "disarmed": ("mdi:shield-off", RoomColor(67, 160, 71))
        case "triggered": ("mdi:shield-alert", RoomColor(229, 57, 53))
        default: ("mdi:shield-outline", RoomColor(84, 110, 122))
        }
    }

    /// Tiles shown for the current states: those without a visibility entity, or whose entity is `on`.
    public static func visible(state: (String) -> String?) -> [QuickLink] {
        items.filter { item in item.visibilityEntityId.map { state($0) == "on" } ?? true }
    }
}
