import HassCore
import HassDesign
import SwiftUI

/// The Summary sheet's Overdue Chores and Upcoming Chores tabs (web `DailyReportTodoTab` and `DailyReportUpcomingTab`).
///
/// Rows are the Chores page's own: ``TodoListSection`` draws the same module list with the canonical ``TodoItemRow`` (its
/// check, due label and edit button), the same swipe actions (complete one way, edit and delete the other) and the same
/// completion animation. Edit opens the Chores page's Donetick form (``DonetickTaskSheet``); delete asks first, through
/// the page's own dialog. Upcoming has two sections, each hidden when empty; when nothing is left the tab says so, and
/// says "Enjoy vacation!" while Vacation Mode is on.
///
/// Never completes, edits or deletes anything by itself: every change is the reader's swipe, tap or button, and goes
/// through the shared ``TodoListController`` and the sheet's form like the Chores page.
struct SummaryChoresTab: View {
    var tab: SummaryTab
    var lists: ProfileSummary.ResidentLists
    var viewer: ChoresConfig.Resident
    var store: EntityStore
    @Environment(ChoresModel.self) private var chores
    @State private var sheet: TodoSheet?
    /// Bumped after a save or delete so every list reloads (web `todoReloadVersion`).
    @State private var reloadVersion = 0
    @State private var deletion: TodoDeletion?

    /// The lists this tab reads, in order: Overdue has one; Upcoming has due today, then no due date.
    private var tabLists: [ChoresConfig.TodoList] {
        tab == .overdue ? [lists.overdue] : [lists.dueToday, lists.noDueDate]
    }

    var body: some View {
        let sections = tabLists.compactMap {
            TodoPageLayout.section(for: $0, viewerUserId: viewer.haUserId, store: store, todos: chores.todos)
        }
        let shown = sections.filter(\.isShown)
        let vacation = store.entity(ChoresConfig.vacationModeEntityId).state?.state == "on"
        List {
            if TodoPageLayout.showsEmptyState(sections) {
                SummaryEmptyState(copy: ProfileSummary.choresEmpty(tab, vacationMode: vacation),
                                  symbol: vacation ? "airplane" : (tab == .overdue ? "checkmark.circle" : "checklist"),
                                  identifier: "summary.empty.\(tab.id)")
                    .modifier(TodoPlainRow(top: HassTokens.Spacing.m, bottom: 0))
            }
            ForEach(shown) { section in
                TodoListSection(
                    list: section.list,
                    controller: section.controller,
                    showsHeader: true,
                    leadsPage: section.id == shown.first?.id,
                    editor: { editAction(for: section.list, item: $0) },
                    deleter: { deletion = TodoDeletion(controller: section.controller, item: $0, isGrocery: false) }
                )
            }
        }
        .groupedListStyle()
        .environment(\.defaultMinListRowHeight, 1)
        // Chores animate away when completed and back in if the call fails; under Reduce Motion they fade (HIG Motion).
        .motionSafeAnimation(MotionTokens.standard, reduced: .easeInOut(duration: 0.2), value: TodoPageLayout.animationKey(shown))
        .background {
            // Every list loads, drawn or not, so a hidden one reappears when its entity says it has items again.
            ForEach(tabLists) { list in
                Color.clear
                    .task(id: TodoReloadKey(entity: store.entity(list.entityId).state, version: reloadVersion)) {
                        await chores.todos.controller(for: list.entityId).load()
                    }
            }
            .accessibilityHidden(true)
        }
        .accessibilityIdentifier("summary.\(tab.id)")
        .sheet(item: $sheet) { sheet in
            if case let .editTask(target) = sheet {
                DonetickTaskSheet(mode: .edit(target)) { reloadVersion += 1 }
                    .hassSheet(.form, fitKey: "summary.\(sheet.id)")
            }
        }
        .todoDeletionDialog($deletion)
    }

    /// Every row is a DoneTick task, so it edits through the task form (only rows whose uid carries a task id).
    private func editAction(for list: ChoresConfig.TodoList, item: TodoItem) -> (() -> Void)? {
        guard let target = DonetickEditTarget(item: item, listEntityId: list.entityId) else { return nil }
        return { sheet = .editTask(target) }
    }
}
