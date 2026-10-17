import HassCore
import HassDesign
import SwiftUI

// MARK: - Sections

/// The app's root sections, from the web's `PRIMARY_NAV_ROUTES`
/// (`ha-sfenton-react-dash:src/constants/routes.ts`): Home, Security, Climate, Chores, Settings. Settings is the last
/// tab, its own page like the web's (owner, 2026-10-16, reversing the 2026-10-14 decision that put it in the Account
/// sheet; `.agents/design/direction-g.md`, Navigation).
enum AppSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case home, security, climate, chores, settings

    var id: String { rawValue }

    /// Visible name (web `shell.json` `navigation.items.*`).
    var title: String {
        switch self {
        case .home: "Home"
        case .security: "Security"
        case .climate: "Climate"
        case .chores: "Chores"
        case .settings: "Settings"
        }
    }

    /// SF Symbol mapped from the web's MDI icon.
    var symbol: String { SymbolMap.symbol(for: mdiIcon) }

    /// The web's icon name.
    var mdiIcon: String {
        switch self {
        case .home: "mdi:home"
        case .security: "mdi:shield"
        case .climate: "mdi:thermostat"
        case .chores: "mdi:clipboard-list"
        case .settings: "mdi:cog"
        }
    }

    /// Accessibility identifier for this section's navigation item (tab and flyout row alike).
    var navigationIdentifier: String { "nav.\(rawValue)" }

    /// The section a notification opens.
    init(_ section: PushSection) {
        switch section {
        case .home: self = .home
        case .security: self = .security
        case .climate: self = .climate
        case .chores: self = .chores
        case .settings: self = .settings
        }
    }
}

extension EnvironmentValues {
    /// The root section whose stack this view is in; nil outside the shell (galleries, sheets).
    @Entry var shellSection: AppSection?
    /// Whether the view's section is the one on screen. The tab bar keeps the other sections' views alive without calling
    /// their `onDisappear`, so work that should stop behind another tab (camera streams) watches this. True outside the shell.
    @Entry var sectionIsShowing = true
}

// MARK: - Menu

/// The flyout's rows (direction G, Navigation: the overlay glass flyout lists the same five as the tab bar).
enum NavigationMenu {
    /// The section rows, in order.
    static let primary: [AppSection] = AppSection.allCases

    /// VoiceOver label for a navigation item. Only Chores carries a badge (web `BADGED_NAV_PATH`), and
    /// the count is spoken after the name like the web's `tabs.overdue` label.
    /// - Parameters:
    ///   - section: The item's section.
    ///   - overdue: Overdue chore count; nil or zero adds nothing.
    static func accessibilityLabel(for section: AppSection, overdue: Int?) -> String {
        guard section == .chores, let overdue, overdue > 0 else { return section.title }
        return "\(section.title), \(overdue) overdue"
    }

    /// The badge shown on an item, if any.
    static func badge(for section: AppSection, overdue: Int?) -> Int? {
        guard section == .chores, let overdue, overdue > 0 else { return nil }
        return overdue
    }
}

// MARK: - Shell style

/// How the app presents its root navigation (owner rules, 2026-10-10; `.agents/design/apple/ipados.md`).
///
/// | Window | Navigation |
/// |---|---|
/// | Compact width (iPhone, Duo folded) | Bottom tab bar (web `bottom` layout) |
/// | Regular width (iPad, Duo unfolded) | Overlay flyout opened from the toolbar or a leading-edge swipe |
///
/// The style follows the horizontal size class only, so rotating an iPad or a Duo never swaps
/// the navigation model. Splits are a separate, per-page decision (``SplitPolicy``).
enum ShellNavigationStyle: Equatable, Sendable {
    case tabBar
    case flyout

    /// Picks the style for a window.
    /// - Parameter isRegularWidth: Horizontal size class is regular.
    static func resolve(isRegularWidth: Bool) -> ShellNavigationStyle {
        isRegularWidth ? .flyout : .tabBar
    }
}

// MARK: - Chrome

/// Where the shell puts navigation chrome for a window (pure, so it can be unit tested).
///
/// Profile and Quick Links are header buttons on every page in every window (owner, 2026-10-16), so only the
/// leading menu button and where the title sits vary with the window.
struct ShellChrome: Equatable, Sendable {
    /// Show the leading menu button that opens ``NavigationFlyout``.
    var showsMenuButton: Bool
    /// The page title sits in the header row beside the trailing buttons (``HeaderTitleStyle``): where nothing but
    /// the trailing buttons shares the row, which is every window without the menu button.
    var titleInHeader: Bool

    /// Resolves the chrome.
    /// - Parameter style: The root navigation style.
    static func resolve(style: ShellNavigationStyle) -> ShellChrome {
        switch style {
        case .flyout: ShellChrome(showsMenuButton: true, titleInHeader: false)
        case .tabBar: ShellChrome(showsMenuButton: false, titleInHeader: true)
        }
    }
}
