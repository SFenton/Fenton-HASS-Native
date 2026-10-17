import HassCore
import SwiftUI

/// Publishes the viewer's overdue chore count to the shell for the Chores tab's badge (web `BADGED_NAV_PATH` = `chores`,
/// `useDailyReportContext().overdueCount`). It is the same count the Profile button and the Your Summary sheet read: the
/// open items of the resident's `…_past_due_with_unassigned` list, so the badge, the summary, the Chores tab and the
/// resident's page always agree. Nothing for a viewer who is not a resident (the web shows no badge either).
struct OverdueChoresBadge: ViewModifier {
    @Environment(ShellNavigator.self) private var navigator: ShellNavigator?
    @Environment(EntityStore.self) private var store: EntityStore?
    @AppStorage(ChoresModel.viewerDefaultsKey) private var viewerUserId: String?

    /// The overdue count, or `nil` while the viewer is not a known resident.
    static func overdue(viewerUserId: String?, store: EntityStore?) -> Int? {
        guard let store, let viewer = ChoresConfig.Resident.forUserId(viewerUserId) else { return nil }
        return ProfileSummary.openCount(store.entity(ProfileSummary.lists(for: viewer).overdue.entityId).state)
    }

    private var overdue: Int? { Self.overdue(viewerUserId: viewerUserId, store: store) }

    func body(content: Content) -> some View {
        content.onChange(of: overdue, initial: true) { _, count in
            navigator?.overdueChores = count
        }
    }
}
