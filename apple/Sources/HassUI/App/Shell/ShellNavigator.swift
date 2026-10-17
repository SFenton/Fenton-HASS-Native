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
    /// The trailing Quick Links tab is showing (``RootTab/quickLinks``); ``selection`` keeps the section under it.
    private(set) var isQuickLinksActive = false
    /// The section whose root is presenting the Quick Links sheet (flyout row, toolbar button), or nil. The sheet
    /// opens over the selected section so a page it links pushes on that section's stack.
    var quickLinksSection: AppSection?
    /// The section whose root is presenting the Account sheet (profile avatar, or a notification that opens
    /// Settings), or nil (``SectionRootChrome``).
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

    /// The root tab view's selection: Quick Links while its trailing tab shows, otherwise the selected section.
    var rootTab: RootTab {
        get { isQuickLinksActive ? .quickLinks : .section(selection) }
        set {
            switch newValue {
            case .quickLinks:
                isQuickLinksActive = true
            case let .section(section):
                isQuickLinksActive = false
                selection = section
            }
        }
    }

    /// Whether a section is the one on screen: selected, and not covered by the Quick Links tab.
    func isShowing(_ section: AppSection) -> Bool { selection == section && !isQuickLinksActive }

    /// Leaves the Quick Links tab for the section under it (the window grew into flyout style).
    func closeQuickLinks() { isQuickLinksActive = false }

    /// Presents the Quick Links sheet over the selected section, closing the flyout.
    func openQuickLinks() {
        isFlyoutOpen = false
        quickLinksSection = selection
    }

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
            guard let target = AppSection(section) else {
                // Settings: the Account sheet over the section on screen (direction G).
                isQuickLinksActive = false
                accountSection = selection
                return
            }
            paths[target] = NavigationPath()
            select(target)
        case let .homePage(path):
            var stack = NavigationPath()
            if let route = HomeRoute(pushPath: path) { stack.append(route) }
            paths[.home] = stack
            selection = .home
            isQuickLinksActive = false
        }
    }

    /// Chooses a section from the flyout or tab bar. Choosing the current section pops it to its root
    /// (the web's nav links always land on the section root).
    func select(_ section: AppSection) {
        if section == selection && !isQuickLinksActive {
            paths[section] = NavigationPath()
        }
        selection = section
        isQuickLinksActive = false
        isFlyoutOpen = false
    }
}
