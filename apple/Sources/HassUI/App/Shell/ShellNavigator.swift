import HassCore
import Observation
import SwiftUI

/// Root navigation state shared by the tab bar, the flyout and every section stack.
///
/// The root owns selection and each section's path, so the flyout and toolbar only emit intents
/// (FestivalNativeApps `DrawerIntent` model).
@MainActor
@Observable
final class ShellNavigator {
    /// The selected root section.
    var selection: AppSection
    /// Each section's push path; a section at its root has an empty path.
    var paths: [AppSection: NavigationPath] = [:]
    /// The section whose stack is presenting the Quick Links sheet (header button, flyout row), or nil. The sheet
    /// opens over the selected section so a page it links pushes on that section's stack.
    var quickLinksSection: AppSection?
    /// The section whose stack is presenting the Account sheet (the header's Profile button), or nil.
    var accountSection: AppSection?
    /// The flyout is showing.
    private(set) var isFlyoutOpen = false
    /// The signed-in user's display name for the profile button, kept between launches so the button never
    /// changes after the first frame (``ProfileButton``).
    var profileName: String? = UserDefaults.standard.string(forKey: ShellNavigator.profileNameKey) {
        didSet { UserDefaults.standard.set(profileName, forKey: Self.profileNameKey) }
    }
    /// Defaults key for ``profileName``.
    nonisolated static let profileNameKey = "shell.profileName"
    /// Overdue chore count for the Chores badge (web `useDailyReportContext().overdueCount`);
    /// nil until the Chores feature provides it.
    var overdueChores: Int?
    /// Per section, a counter bumped when a second tap on the selected tab (at its root) asks the page to scroll to its top
    /// (``scrollsToTop(whenRequested:)``).
    private(set) var scrollToTopRequests: [AppSection: Int] = [:]
    /// Bumped when the flyout closes without choosing a destination, so the Open Navigation button
    /// takes VoiceOver focus back (HIG VoiceOver: "Inform VoiceOver of visible content or layout changes").
    private(set) var focusReturnToken = 0

    init(selection: AppSection = .home) {
        self.selection = selection
    }

    /// A binding to one section's path.
    func path(for section: AppSection) -> Binding<NavigationPath> {
        Binding(
            get: { self.paths[section] ?? NavigationPath() },
            set: { self.paths[section] = $0 }
        )
    }

    /// Presents the Quick Links sheet over the selected section, closing the flyout.
    func openQuickLinks() {
        isFlyoutOpen = false
        quickLinksSection = selection
    }

    /// Presents the Account sheet over the selected section, closing the flyout.
    func openAccount() {
        isFlyoutOpen = false
        accountSection = selection
    }

    /// Whether a section is the one on screen.
    func isShowing(_ section: AppSection) -> Bool { selection == section }

    /// Whether a section is showing its root page.
    func isAtRoot(_ section: AppSection) -> Bool {
        paths[section]?.isEmpty ?? true
    }

    // MARK: - Intents

    /// Shows the flyout.
    func openFlyout() { isFlyoutOpen = true }

    /// Opens the flyout for a finished leading-edge drag, only while the selected section is at its root
    /// (deeper, the system's back swipe owns that edge).
    /// - Parameters:
    ///   - startX: Where the drag began, from the leading edge.
    ///   - translation: Total movement.
    func edgeSwipeEnded(startX: CGFloat, translation: CGSize) {
        guard isAtRoot(selection), !isFlyoutOpen,
              NavigationFlyoutMetrics.edgeSwipeOpens(startX: startX, translation: translation)
        else { return }
        openFlyout()
    }

    /// Hides the flyout without choosing a destination; focus returns to Open Navigation.
    func dismissFlyout() {
        guard isFlyoutOpen else { return }
        isFlyoutOpen = false
        focusReturnToken &+= 1
    }

    /// Opens the page a notification points at, on its section's root (web `primaryNavPathForRoute`). A Home page
    /// is pushed on Home's root; a route the app has no page for opens Home.
    func open(_ destination: PushDestination) {
        isFlyoutOpen = false
        switch destination {
        case let .section(section):
            let target = AppSection(section)
            paths[target] = NavigationPath()
            select(target)
        case let .homePage(path):
            var stack = NavigationPath()
            if let route = HomeRoute(pushPath: path) { stack.append(route) }
            paths[.home] = stack
            selection = .home
        }
    }

    /// What choosing the selected section did.
    enum ReselectOutcome: Equatable {
        /// The stack was deeper than its root and popped to it.
        case poppedToRoot
        /// The stack was at its root: the page was asked to scroll to its top.
        case scrolledToTop
    }

    /// Chooses a section from the flyout. Choosing the current section is the standard second tap: it pops the stack to its
    /// root, and once it is at the root it scrolls the page to the top (``reselect(_:)``).
    func select(_ section: AppSection) {
        tabTapped(section)
        isFlyoutOpen = false
    }

    /// A tap on the tab bar: another section is a cut (no animation on the content); the selected one is ``reselect(_:)``.
    func tabTapped(_ section: AppSection) {
        if section == selection {
            reselect(section)
        } else {
            selection = section
        }
    }

    /// The standard second tap on the selected tab: the first tap pops to the root; at the root the next scrolls to the top.
    @discardableResult
    func reselect(_ section: AppSection) -> ReselectOutcome {
        guard isAtRoot(section) else {
            paths[section] = NavigationPath()
            return .poppedToRoot
        }
        scrollToTopRequests[section, default: 0] += 1
        return .scrolledToTop
    }
}
