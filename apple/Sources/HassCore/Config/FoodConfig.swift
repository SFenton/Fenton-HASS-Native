import Foundation

/// Entity configuration for the Food & Recipes hub, ported from the React dashboard.
///
/// Source: `ha-sfenton-react-dash@9ac2a46:src/constants/everShelfFood.ts` and `src/pages/FoodHubPage.tsx`.
public enum FoodConfig {
    // MARK: - Entities

    /// Items expiring soon; its `expiring_list` attribute carries each item's location and days left.
    public static let expiringSoonEntityId = "sensor.evershelf_expiring_soon"
    /// Every item in EverShelf.
    public static let totalItemsEntityId = "sensor.evershelf_total_items"

    /// One storage place (web `EVERSHELF_FOOD_SPACES`).
    public struct Space: Sendable, Identifiable, Hashable {
        public var title: String
        public var entityId: String
        /// EverShelf's location key (Italian upstream names: `dispensa`, `frigo`).
        public var location: String
        /// Web MDI icon name.
        public var icon: String
        /// Tile tint, from the web's tile color.
        public var red: Double, green: Double, blue: Double
        public var id: String { location }
    }

    /// Pantry, Fridge, Freezer, Spice Rack and Cabinet, in web order (everShelfFood.ts:16).
    public static let spaces: [Space] = [
        .init(title: "Pantry", entityId: "sensor.evershelf_items_in_pantry", location: "dispensa", icon: "mdi:food-fork-drink", red: 155, green: 110, blue: 64),
        .init(title: "Fridge", entityId: "sensor.evershelf_items_in_fridge", location: "frigo", icon: "mdi:fridge", red: 42, green: 126, blue: 180),
        .init(title: "Freezer", entityId: "sensor.evershelf_items_in_freezer", location: "freezer", icon: "mdi:snowflake", red: 52, green: 103, blue: 176),
        .init(title: "Spice Rack", entityId: "sensor.kitchen_evershelf_items_in_spice_rack", location: "spice_rack", icon: "mdi:shaker-outline", red: 183, green: 98, blue: 56),
        .init(title: "Cabinet", entityId: "sensor.kitchen_evershelf_items_in_cabinet", location: "cabinet", icon: "mdi:cupboard", red: 118, green: 96, blue: 72),
    ]

    /// Hub tile tints (FoodHubPage.tsx): All Recipes blue, All Food green.
    public static let allRecipesTint = (red: 42.0, green: 126.0, blue: 180.0)
    public static let allFoodTint = (red: 88.0, green: 128.0, blue: 94.0)

    // MARK: - Subtitles

    // Each helper reads entities through `state`, so a view passing `{ store.entity($0).state }` observes them.

    /// `12 Items • 3 Expiring Soon` for one space (web `groceryPlaceSubtitle`).
    public static func spaceSubtitle(_ space: Space, state: (String) -> EntityState?, now: Date = .now, calendar: Calendar = .current) -> String {
        summary(items: count(state(space.entityId)), expiring: expiringCount(location: space.location, state: state, now: now, calendar: calendar))
    }

    /// The whole inventory: total items (or the spaces' sum) and the expiring sensor (web `allFoodSubtitle`).
    public static func allFoodSubtitle(state: (String) -> EntityState?) -> String {
        let fallback = spaces.reduce(0) { $0 + count(state($1.entityId)) }
        let total = count(state(totalItemsEntityId))
        return summary(items: total > 0 ? total : fallback, expiring: count(state(expiringSoonEntityId)))
    }

    /// Every space's items and expiring items (web `foodSummarySubtitle`, the Kitchen page's Food tile).
    public static func foodSummarySubtitle(state: (String) -> EntityState?, now: Date = .now, calendar: Calendar = .current) -> String {
        summary(
            items: spaces.reduce(0) { $0 + count(state($1.entityId)) },
            expiring: spaces.reduce(0) { $0 + expiringCount(location: $1.location, state: state, now: now, calendar: calendar) }
        )
    }

    /// `1 Item • 0 Expiring Soon` (web `pageFood.inventory.*`).
    public static func summary(items: Int, expiring: Int) -> String {
        "\(items) \(items == 1 ? "Item" : "Items") • \(expiring) Expiring Soon"
    }

    // MARK: - Private

    /// A positive whole count from a sensor, else 0 (web `numericEntityState`).
    static func count(_ state: EntityState?) -> Int {
        guard let value = state?.numericState, value.isFinite, value > 0 else { return 0 }
        return Int(value)
    }

    /// Items in `location` that expire within a week (web `expiringSoonCountForLocation`).
    static func expiringCount(location: String, state: (String) -> EntityState?, now: Date, calendar: Calendar) -> Int {
        guard let list = state(expiringSoonEntityId)?.attributes["expiring_list"]?.array else { return 0 }
        return list.filter { item in
            normalizedLocation(item["location"]?.string ?? "") == location && expiresWithinWeek(item, now: now, calendar: calendar)
        }.count
    }

    static func normalizedLocation(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespaces).lowercased()
        switch normalized {
        case "pantry": return "dispensa"
        case "fridge": return "frigo"
        case "spice rack", "spice-rack": return "spice_rack"
        default: return normalized
        }
    }

    static func expiresWithinWeek(_ item: JSONValue, now: Date, calendar: Calendar) -> Bool {
        if let days = item["days_remaining"]?.finiteNumber { return days >= 0 && days <= 7 }
        guard let text = item["expiry_date"]?.string, text.count >= 10 else { return false }
        let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let expiry = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return false }
        let today = calendar.startOfDay(for: now)
        guard let nextWeek = calendar.date(byAdding: .day, value: 7, to: today) else { return false }
        return expiry >= today && expiry <= nextWeek
    }
}
