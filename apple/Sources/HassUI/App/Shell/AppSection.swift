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
