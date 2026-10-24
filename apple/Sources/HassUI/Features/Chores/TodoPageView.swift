import HassCore
import HassDesign
import SwiftUI

/// A page of todo lists: Chores, Groceries, each resident's chores, Home Improvement and the admin To-Do
/// (web `TodoPageContent`, `ha-sfenton-react-dash:src/pages/DashboardViewPage.tsx`).
///
/// Lists with nothing open are hidden; when every list is, the page shows its empty state. DoneTick rows open
/// the task form to edit and the admin To-Do's rows open a rename sheet. The floating Add button opens the
/// page's create sheet. Direction G (mockups n5): each list is a 20 pt bold header over an inset list on the wallpaper.
struct TodoPageView<Header: View>: View {
    var page: ChoresConfig.Page
    @ViewBuilder var header: () -> Header

    @Environment(ChoresModel.self) private var model
    @Environment(EntityStore.self) private var store
    @State private var sheet: TodoSheet?
    /// Bumped after a save or delete so every list reloads (web `todoReloadVersion`).
    @State private var reloadVersion = 0
    /// The task a swipe or menu asked to delete, until the confirmation answers.
    @State private var deletion: TodoDeletion?
    /// How wide the list's plain rows are, for the quick links header to line up with (``AlignedToListMargins``).
    @State private var rowMetrics = TodoRowMetrics()

    var body: some View {
        let sections = TodoPageLayout.sections(for: page, viewerUserId: model.viewerUserId, store: store, todos: model.todos)
        let shown = sections.filter(\.isShown)
        // A real `List` (not a ScrollView of stacks): swipe actions need one before iOS 27. Rows draw their own module card
        // (`ModuleRowBackground`); everything else is a plain row on the wallpaper.
        List {
            if Header.self != EmptyView.self {
                // A section header, not a row: a row of several `NavigationLink`s (the Chores quick links) activates
                // every one of them on any tap, and a button-driven destination hung the page in the debug gallery
                // (2026-10-16). The system sets the header in from the list's margin by its own amount; the modifier
                // measures that against a plain row and takes it back, so the tiles share the modules' edges.
                Section {} header: {
                    header()
                        .textCase(nil)
                        .modifier(AlignedToListMargins())
                }
            }
            if TodoPageLayout.showsEmptyState(sections) {
                emptyState.modifier(TodoPlainRow(top: HassTokens.Spacing.m, bottom: 0))
            }
            ForEach(shown) { section in
                TodoListSection(
                    list: section.list,
                    controller: section.controller,
                    showsHeader: !page.hideListHeaders,
                    leadsPage: section.id == shown.first?.id && Header.self == EmptyView.self,
                    editor: { editAction(for: section.list, item: $0) },
                    deleter: page.deletesItems ? { deletion = TodoDeletion(controller: section.controller, item: $0, isGrocery: page.id == ChoresConfig.groceries.id) } : nil
                )
            }
        }
        .groupedListStyle()
        .environment(\.todoRowMetrics, rowMetrics)
        .environment(\.defaultMinListRowHeight, 1)
        // Chores animate away when completed and back in if the call fails (owner, 2026-10-16). Under Reduce Motion the
        // rows fade instead of sliding (HIG Motion).
        .motionSafeAnimation(MotionTokens.standard, reduced: MotionTokens.quick, value: TodoPageLayout.animationKey(shown))
        .background {
            // Every visible list loads, drawn or not, so a hidden list reappears when its entity says
            // it has items again.
            ForEach(page.lists.filter { $0.isVisible(to: model.viewerUserId, openItems: store.entity($0.entityId).state) }) { list in
                Color.clear
                    .task(id: TodoReloadKey(entity: store.entity(list.entityId).state, version: reloadVersion)) {
                        await model.todos.controller(for: list.entityId).load()
                    }
            }
            .accessibilityHidden(true)
        }
        .scrollTelemetry("Chores · \(page.id)")
        .accessibilityIdentifier("todo.page.\(page.id)")
        .floatingActionBar([
            FloatingAction(id: "add", title: TodoPageLayout.addTitle(page.addAction), symbol: "plus") { sheet = .create },
        ])
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
                .hassSheet(.form, fitKey: "todo.\(sheet.id)")
        }
        .todoDeletionDialog($deletion)
    }

    private var emptyState: some View {
        let vacation = store.entity(ChoresConfig.vacationModeEntityId).state?.state == "on"
        // Centred on the wallpaper with the checklist glyph (mockup n5-empty).
        return ContentUnavailableView {
            Label(page.emptyTitle, systemImage: "checklist")
        } description: {
            Text(page.emptyDescription(viewer: model.viewer, vacationModeOn: vacation))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, HassTokens.Spacing.xl)
        .accessibilityIdentifier("todo.empty")
    }

    /// DoneTick rows edit through the task form (only rows whose uid carries a task id); admin To-Do rows rename.
    private func editAction(for list: ChoresConfig.TodoList, item: TodoItem) -> (() -> Void)? {
        if page.isDonetick {
            guard let target = DonetickEditTarget(item: item, listEntityId: list.entityId) else { return nil }
            return { sheet = .editTask(target) }
        }
        guard page.editsAdminTodo else { return nil }
        return { sheet = .renameTodo(AdminTodoEditTarget(itemUid: item.uid, originalTitle: item.summary ?? "", todoEntityId: list.entityId)) }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: TodoSheet) -> some View {
        let reload = { reloadVersion += 1 }
        switch sheet {
        case .create:
            switch page.addAction {
            case let .donetickTask(defaultAssignee):
                DonetickTaskSheet(mode: .create(defaultAssignee: defaultAssignee), onSaved: reload)
            case let .groceryItem(entityId):
                AddGroceryItemSheet(entityId: entityId)
            case let .adminTodo(entityId):
                AddAdminTodoSheet(entityId: entityId)
            }
        case let .editTask(target):
            DonetickTaskSheet(mode: .edit(target), onSaved: reload)
        case let .renameTodo(target):
            RenameTodoItemSheet(target: target, onSaved: reload)
        }
    }
}

extension TodoPageView where Header == EmptyView {
    /// A page without a header.
    init(page: ChoresConfig.Page) {
        self.init(page: page) { EmptyView() }
    }
}

// MARK: - Sheets

/// The sheets a todo page presents.
enum TodoSheet: Identifiable, Hashable {
    case create
    case editTask(DonetickEditTarget)
    case renameTodo(AdminTodoEditTarget)

    var id: String {
        switch self {
        case .create: "create"
        case let .editTask(target): "edit-\(target.todoEntityId)-\(target.itemUid)"
        case let .renameTodo(target): "rename-\(target.todoEntityId)-\(target.itemUid ?? target.originalTitle)"
        }
    }
}

/// A DoneTick task opened from a list row (web `DonetickTaskEditTarget`).
struct DonetickEditTarget: Hashable, Sendable {
    var itemUid: String
    var taskId: Int
    var todoEntityId: String

    init(itemUid: String, taskId: Int, todoEntityId: String) {
        self.itemUid = itemUid
        self.taskId = taskId
        self.todoEntityId = todoEntityId
    }

    /// The target for a DoneTick row (only rows whose uid carries a task id can be edited), else `nil`. The Chores pages
    /// and the Summary sheet open the same form from it.
    init?(item: TodoItem, listEntityId: String) {
        guard let taskId = item.donetickTaskId, let uid = item.uid else { return nil }
        self.init(itemUid: uid, taskId: taskId, todoEntityId: listEntityId)
    }
}

/// An admin to-do opened for renaming (web `AdminTodoEditTarget`).
struct AdminTodoEditTarget: Hashable, Sendable {
    var itemUid: String?
    var originalTitle: String
    var todoEntityId: String
}

/// A task a swipe, menu or VoiceOver action asked to delete, awaiting confirmation.
struct TodoDeletion {
    var controller: TodoListController
    var item: TodoItem
    var isGrocery: Bool
}

extension View {
    /// The confirmation a swipe, menu or VoiceOver delete asks before removing a task. One dialog for the Chores pages and
    /// the Summary sheet's chore tabs.
    func todoDeletionDialog(_ deletion: Binding<TodoDeletion?>) -> some View {
        confirmationDialog(
            deletion.wrappedValue.map { "Delete \($0.item.displayTitle)?" } ?? "",
            isPresented: deletion.isPresent(),
            titleVisibility: .visible,
            presenting: deletion.wrappedValue
        ) { deletion in
            Button(deletion.isGrocery ? "Delete Item" : "Delete Task", role: .destructive) {
                Task { await deletion.controller.remove(deletion.item) }
            }
            .accessibilityIdentifier("todo.delete.confirm")
        } message: { _ in
            Text("This can't be undone.")
        }
    }
}

/// Reloads a list when its entity changes or a sheet saved.
struct TodoReloadKey: Hashable {
    var entity: EntityState?
    var version: Int
}

// MARK: - Layout policy

/// Which lists a page shows, separated from the view so it can be unit tested.
enum TodoPageLayout {
    /// One list as the page sees it.
    struct Section: Identifiable {
        var list: ChoresConfig.TodoList
        var controller: TodoListController
        /// The list has (or may have) open items, so it is drawn.
        var isShown: Bool
        /// Whether the list is known: loaded or cached, or its entity says it is empty.
        var isSettled: Bool
        var id: String { list.entityId }
    }

    /// The page's lists the viewer can see, with whether each is drawn (web `TodoSection` visibility).
    @MainActor
    static func sections(for page: ChoresConfig.Page, viewerUserId: String?, store: EntityStore, todos: TodoStore) -> [Section] {
        page.lists.compactMap { section(for: $0, viewerUserId: viewerUserId, store: store, todos: todos) }
    }

    /// One list as the page sees it, or `nil` when the viewer doesn't see it. The Summary sheet's chore tabs read their
    /// lists through this too, so a list shows and hides by the same rule on every surface.
    @MainActor
    static func section(for list: ChoresConfig.TodoList, viewerUserId: String?, store: EntityStore, todos: TodoStore) -> Section? {
        let entity = store.entity(list.entityId).state
        guard list.isVisible(to: viewerUserId, openItems: entity) else { return nil }
        let controller = todos.controller(for: list.entityId)
        // The entity's state is its open-item count; zero hides the list before any fetch.
        let mayHaveItems = entity.map { $0.isUnavailable || ($0.numericState ?? 0) > 0 } ?? true
        if !mayHaveItems { return Section(list: list, controller: controller, isShown: false, isSettled: true) }
        guard controller.items != nil else { return Section(list: list, controller: controller, isShown: true, isSettled: false) }
        let hasItems = !controller.visibleItems(hideCompleted: list.hideCompleted).isEmpty
        return Section(list: list, controller: controller, isShown: hasItems, isSettled: true)
    }

    /// Everything that makes a row appear or leave, so one implicit animation covers a completion, its rollback, a
    /// delete and a list appearing.
    @MainActor
    static func animationKey(_ sections: [Section]) -> [String] {
        sections.flatMap { section in
            [section.id] + section.controller.visibleItems(hideCompleted: section.list.hideCompleted).map { "\(section.id)/\($0.id)" }
        }
    }

    /// The empty state shows once every list is known and none is drawn, or when no list is visible at all.
    static func showsEmptyState(_ sections: [Section]) -> Bool {
        sections.allSatisfy { $0.isSettled && !$0.isShown }
    }

    /// Adding a grocery and renaming a to-do are one-field prompts. Every todo sheet is content-fitted now (owner,
    /// 2026-10-16), so this is no longer a sizing input; kept for the tests that name the short prompts.
    static func isShortPrompt(_ sheet: TodoSheet, addAction: ChoresConfig.AddAction) -> Bool {
        switch sheet {
        case .create:
            if case .groceryItem = addAction { return true }
            return false
        case .renameTodo: return true
        case .editTask: return false
        }
    }

    /// The Add button's label.
    static func addTitle(_ action: ChoresConfig.AddAction) -> String {
        if case .groceryItem = action { return "Add Groceries" }
        return "Add Task"
    }
}
