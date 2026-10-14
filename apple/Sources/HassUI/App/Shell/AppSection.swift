import HassDesign
import SwiftUI

// MARK: - Sections

/// The app's root sections, from the web's `PRIMARY_NAV_ROUTES`
/// (`ha-sfenton-react-dash:src/constants/routes.ts`): Home, Security, Climate, Chores. Settings is not a section:
/// direction G moves it into the Account sheet behind the profile avatar (`.agents/design/direction-g.md`,
/// Navigation).
enum AppSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case home, security, climate, chores

    var id: String { rawValue }

    /// Visible name (web `shell.json` `navigation.items.*`).
    var title: String {
        switch self {
        case .home: "Home"
        case .security: "Security"
        case .climate: "Climate"
        case .chores: "Chores"
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
        }
    }

    /// Accessibility identifier for this section's navigation item (tab and flyout row alike).
    var navigationIdentifier: String { "nav.\(rawValue)" }
}

extension EnvironmentValues {
    /// The root section whose stack this view is in; nil outside the shell (galleries, sheets).
    @Entry var shellSection: AppSection?
}

// MARK: - Menu

/// The flyout's rows (direction G, Navigation: "an overlay glass flyout that lists the four tabs and then Quick
/// Links").
enum NavigationMenu {
    /// The section rows, in order; Quick Links follows them.
    static let primary: [AppSection] = [.home, .security, .climate, .chores]

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

/// A tab in the root tab view: a section, or the trailing Quick Links circle.
enum RootTab: Hashable, Sendable {
    case section(AppSection)
    /// Quick Links (web `GlobalQuickLinksAction`), the tab bar's trailing tab on iOS 26 and later.
    case quickLinks
}

/// How the compact (iPhone, folded Duo) tab bar carries Quick Links (direction G, Navigation: "a floating glass
/// tab bar with Home, Security, Climate and Chores ... Quick Links ... trails the tab bar").
///
/// iOS 26 and later show it as the trailing role tab (`Tab(role: .search)`), its own page; direction G's circle that
/// presents a sheet is a recorded departure (``MainTabView``). Before iOS 26 Quick Links is a toolbar button that
/// presents the sheet. HIG Tab bars: "A dedicated Search tab may be trailing."
enum CompactTabLayout: Equatable, Sendable {
    /// The four sections as tabs; Quick Links is a toolbar button (before iOS 26).
    case sectionsOnly
    /// The four sections and the trailing Quick Links tab.
    case sectionsWithQuickLinks

    /// The layout for the running system.
    /// - Parameter supportsTrailingTab: The system draws a role tab apart from the bar (iOS 26 and later).
    static func resolve(supportsTrailingTab: Bool) -> CompactTabLayout {
        supportsTrailingTab ? .sectionsWithQuickLinks : .sectionsOnly
    }

    /// Whether Quick Links is the trailing tab rather than a toolbar button.
    var hasQuickLinksTab: Bool { self == .sectionsWithQuickLinks }
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
        // iPad: "Quick Links is a floating button" (direction G), and also the flyout's last row.
        case .flyout: ShellChrome(showsMenuButton: true, showsQuickLinksButton: true)
        case .tabBar: ShellChrome(showsMenuButton: false, showsQuickLinksButton: !layout.hasQuickLinksTab)
        }
    }
}
