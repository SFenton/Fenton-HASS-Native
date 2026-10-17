import AppIntents
import HassCore
import HassUI

// MARK: - Pages

/// The pages an App Shortcut can open: the app's five root sections.
enum AppPageOption: String, AppEnum {
    case home, security, climate, chores, settings

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Page")

    static let caseDisplayRepresentations: [AppPageOption: DisplayRepresentation] = [
        .home: DisplayRepresentation(title: "Home", image: .init(systemName: "house.fill")),
        .security: DisplayRepresentation(title: "Security", image: .init(systemName: "shield.fill")),
        .climate: DisplayRepresentation(title: "Climate", image: .init(systemName: "thermometer.medium")),
        .chores: DisplayRepresentation(title: "Chores", image: .init(systemName: "list.clipboard.fill")),
        .settings: DisplayRepresentation(title: "Settings", image: .init(systemName: "gearshape.fill")),
    ]

    /// The section this option opens.
    var destination: PushDestination {
        switch self {
        case .home: .section(.home)
        case .security: .section(.security)
        case .climate: .section(.climate)
        case .chores: .section(.chores)
        case .settings: .section(.settings)
        }
    }
}

// MARK: - Intent

/// Opens S+H on one of its root pages. The system runs it in the app's own process (`openAppWhenRun`), so the page
/// opens through the same path as a notification's link (``AppShortcutRouter``).
struct OpenPageIntent: AppIntent {
    static let title: LocalizedStringResource = "Open a Page"
    static let description = IntentDescription(
        "Opens a page of S+H: Home, Security, Climate, Chores or Settings.",
        categoryName: "Navigation",
        searchKeywords: ["Home Assistant", "HASS", "Fenton Home", "Smart Home", "thermostat", "cameras", "tasks"]
    )
    static let openAppWhenRun = true

    @Parameter(title: "Page") var page: AppPageOption

    init() {}

    init(page: AppPageOption) {
        self.page = page
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppShortcutRouter.route(to: page.destination)
        return .result()
    }
}

// MARK: - Shortcuts

/// The shortcuts that appear in Spotlight, Siri and the Shortcuts app as soon as the app is installed.
///
/// Every phrase must contain the app's name (`\(.applicationName)`); Siri accepts the `INAlternativeAppNames` in its
/// place ("Open Climate in Home Assistant", "... in HASS"). Apple's limits: at most ten shortcuts per app.
struct SHShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenPageIntent(page: .home),
            phrases: [
                "Open \(.applicationName)",
                "Open Home in \(.applicationName)",
                "Show my house in \(.applicationName)",
            ],
            shortTitle: "Open Home",
            systemImageName: "house.fill"
        )
        AppShortcut(
            intent: OpenPageIntent(page: .security),
            phrases: [
                "Open Security in \(.applicationName)",
                "Show cameras in \(.applicationName)",
                "Check the locks in \(.applicationName)",
            ],
            shortTitle: "Open Security",
            systemImageName: "shield.fill"
        )
        AppShortcut(
            intent: OpenPageIntent(page: .climate),
            phrases: [
                "Open Climate in \(.applicationName)",
                "Show the thermostat in \(.applicationName)",
            ],
            shortTitle: "Open Climate",
            systemImageName: "thermometer.medium"
        )
        AppShortcut(
            intent: OpenPageIntent(page: .chores),
            phrases: [
                "Open Chores in \(.applicationName)",
                "Show my chores in \(.applicationName)",
            ],
            shortTitle: "Open Chores",
            systemImageName: "list.clipboard.fill"
        )
    }
}
