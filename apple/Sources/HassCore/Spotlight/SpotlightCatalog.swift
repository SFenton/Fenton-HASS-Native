import Foundation

/// One page of the app that Spotlight can open: a root section or a room.
public struct SpotlightEntry: Equatable, Sendable, Identifiable {
    /// Stable identifier handed back to the app when the result is tapped (`section.climate`, `room.living-room`).
    public var id: String
    /// The result's title.
    public var title: String
    /// The second line of the result.
    public var summary: String
    /// Words that find this page, besides its title.
    public var keywords: [String]
    /// The web icon the page uses, which the indexer draws as the result's thumbnail.
    public var mdiIcon: String
    /// Where tapping the result goes.
    public var destination: PushDestination
}

/// The small set of pages the app puts in Spotlight (`CSSearchableItem`), and the way back from a tapped result.
///
/// Core Spotlight gives an installed app's own pages, not the app icon, extra search words. Every entry carries
/// ``AppBranding/searchTerms`` so "Home Assistant", "HASS", "Fenton" or "Smart Home" lists the app's pages, each of
/// which opens S+H on that page.
public enum SpotlightCatalog {
    /// Groups the app's items so they can all be removed at once (sign-out).
    public static let domainIdentifier = "com.sfenton.home.pages"

    /// Every item: the five root sections, then the sixteen rooms.
    public static let entries: [SpotlightEntry] = sections + rooms

    /// The page a tapped result opens.
    /// - Parameter identifier: The tapped item's unique identifier.
    /// - Returns: The destination, or nil for an identifier from an older version of the app.
    public static func destination(forIdentifier identifier: String) -> PushDestination? {
        entriesById[identifier]?.destination
    }

    private static let entriesById = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })

    // MARK: - Sections

    private static let sections: [SpotlightEntry] = [
        section(.home, "Home", "Rooms, lights and everything in the house",
                ["rooms", "lights", "house", "dashboard", "overview"], "mdi:home"),
        section(.security, "Security", "Cameras, locks, doors and alarms",
                ["cameras", "locks", "doors", "alarm", "garage"], "mdi:shield"),
        section(.climate, "Climate", "Thermostat, humidity and air quality",
                ["thermostat", "temperature", "heat", "cooling", "humidity", "air quality"], "mdi:thermostat"),
        section(.chores, "Chores", "Tasks, groceries and what is overdue",
                ["tasks", "to do", "groceries", "overdue"], "mdi:clipboard-list"),
        section(.settings, "Settings", "Profile, household settings and feedback",
                ["preferences", "account", "feedback", "profile"], "mdi:cog"),
    ]

    private static func section(_ section: PushSection, _ title: String, _ summary: String, _ words: [String],
                                _ icon: String) -> SpotlightEntry {
        SpotlightEntry(id: "section.\(section.rawValue)", title: title, summary: summary,
                       keywords: words + AppBranding.searchTerms, mdiIcon: icon, destination: .section(section))
    }

    // MARK: - Rooms

    private static let rooms: [SpotlightEntry] = RoomsConfig.pages.map { page in
        SpotlightEntry(id: "room.\(page.id)", title: page.title, summary: "\(page.title) lights, climate and devices",
                       keywords: [page.title, "room"] + AppBranding.searchTerms, mdiIcon: "mdi:home",
                       destination: .homePage(page.id))
    }
}

/// Reads which item a Spotlight tap was for.
public enum SpotlightLink {
    /// The `userInfo` key Core Spotlight puts the tapped item's unique identifier under
    /// (`CSSearchableItemActivityIdentifier`); kept as text so this module needs no Core Spotlight import.
    public static let userInfoKey = "kCSSearchableItemActivityIdentifier"

    /// The tapped item's identifier.
    /// - Parameter userInfo: The `NSUserActivity.userInfo` of a `CSSearchableItemActionType` continuation.
    public static func identifier(in userInfo: [AnyHashable: Any]?) -> String? {
        userInfo?[userInfoKey] as? String
    }
}
