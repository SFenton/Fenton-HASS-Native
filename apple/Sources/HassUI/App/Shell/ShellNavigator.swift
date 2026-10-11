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
    /// The flyout is showing.
    private(set) var isFlyoutOpen = false
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

    /// Whether a section is showing its root page.
    func isAtRoot(_ section: AppSection) -> Bool {
        paths[section]?.isEmpty ?? true
    }

    // MARK: - Intents

    /// Shows the flyout.
    func openFlyout() { isFlyoutOpen = true }

    /// Hides the flyout without choosing a destination; focus returns to Open Navigation.
    func dismissFlyout() {
        guard isFlyoutOpen else { return }
        isFlyoutOpen = false
        focusReturnToken &+= 1
    }

    /// Chooses a section from the flyout or tab bar. Choosing the current section pops it to its root
    /// (the web's nav links always land on the section root).
    func select(_ section: AppSection) {
        if section == selection {
            paths[section] = NavigationPath()
        }
        selection = section
        isFlyoutOpen = false
    }
}
