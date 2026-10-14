import HassDesign
import SwiftUI

// MARK: - Sections

/// The app's root sections, matching the web's `PRIMARY_NAV_ROUTES`
/// (`ha-sfenton-react-dash:src/constants/routes.ts`): Home, Security, Climate, Chores, Settings.
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
}

// MARK: - Menu

/// The flyout's grouping, from the web rail and drawer (`AdaptiveNavigation.tsx`): the four primary
/// sections at the top, Settings pinned to the bottom (`margin-top: auto`).
enum NavigationMenu {
    /// Rows at the top of the flyout.
    static let primary: [AppSection] = [.home, .security, .climate, .chores]
    /// Rows pinned at the bottom of the flyout.
    static let footer: [AppSection] = [.settings]

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

// MARK: - Compact tab bar

/// A section page pushed on another section's stack because it is not a tab in this window: Settings, chosen
/// from the menu where the compact bar leaves it out (FestivalNativeApps' drawer pushes a dropped section the
/// same way). A hidden tab can't be selected: UIKit asserts.
enum ShellRoute: Hashable, Sendable {
    case settings
}

/// A tab in the root tab view: a section, or the trailing Quick Links tab.
enum RootTab: Hashable, Sendable {
    case section(AppSection)
    /// Quick Links (web `GlobalQuickLinksAction`), the tab bar's trailing accessory tab on iOS 26 and later.
    case quickLinks
}

/// Which tabs the compact (iPhone, folded Duo) tab bar shows (owner, 2026-10-13: "Quick Links should be an
/// accessory like search button is in FestivalNativeApps and profile goes in top right ... show
/// Home/Security/Climate/Chores as the primary four and Settings can be accessed via flyout").
///
/// iOS 26 and later separate a trailing tab (`Tab(role: .search)`) from the bar, as FestivalNativeApps does for
/// Search. A phone shows five tabs before "More", and the trailing tab counts toward them (FestivalNativeApps
/// measured on iOS 26.5: five sections plus Search moved Search into More), so Settings leaves the bar and opens
/// from the menu button (``NavigationFlyout``). HIG Tab bars: "Avoid overflow" and "A dedicated Search tab may be
/// trailing."
enum CompactTabLayout: Equatable, Sendable {
    /// All five sections as tabs; Quick Links is a toolbar button (before iOS 26).
    case allSections
    /// The four primary sections and the trailing Quick Links tab; Settings is in the menu.
    case primaryWithQuickLinks

    /// The layout for the running system.
    /// - Parameter supportsTrailingTab: The system draws a role tab apart from the bar (iOS 26 and later).
    static func resolve(supportsTrailingTab: Bool) -> CompactTabLayout {
        supportsTrailingTab ? .primaryWithQuickLinks : .allSections
    }

    /// Sections shown as tabs, in order.
    var visibleSections: [AppSection] {
        switch self {
        case .allSections: AppSection.allCases
        case .primaryWithQuickLinks: NavigationMenu.primary
        }
    }

    /// Whether Quick Links is a tab rather than a toolbar button.
    var hasQuickLinksTab: Bool { self == .primaryWithQuickLinks }
}

/// Where the shell puts navigation chrome for a window (pure, so it can be unit tested).
struct ShellChrome: Equatable, Sendable {
    /// Show the leading menu button that opens ``NavigationFlyout``.
    var showsMenuButton: Bool
    /// Quick Links is a toolbar button on section roots (otherwise it is the trailing tab).
    var showsQuickLinksButton: Bool

    /// Resolves the chrome.
    /// - Parameters:
    ///   - style: The root navigation style.
    ///   - layout: The compact tab layout.
    static func resolve(style: ShellNavigationStyle, layout: CompactTabLayout) -> ShellChrome {
        switch style {
        case .flyout:
            ShellChrome(showsMenuButton: true, showsQuickLinksButton: true)
        case .tabBar:
            ShellChrome(showsMenuButton: layout == .primaryWithQuickLinks, showsQuickLinksButton: !layout.hasQuickLinksTab)
        }
    }
}
