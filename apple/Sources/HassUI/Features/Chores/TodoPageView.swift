import HassCore
import HassDesign
import SwiftUI

/// A page of todo lists: Chores, Groceries, each resident's chores, Home Improvement and the admin To-Do
/// (web `TodoPageContent`, `ha-sfenton-react-dash:src/pages/DashboardViewPage.tsx`).
///
/// Lists with nothing open are hidden; when every list is, the page shows its empty state. DoneTick rows open
/// the task form to edit and the admin To-Do's rows open a rename sheet. The floating Add button opens the
/// page's create sheet.
struct TodoPageView<Header: View>: View {
    var page: ChoresConfig.Page
    @ViewBuilder var header: () -> Header

    @Environment(ChoresModel.self) private var model
    @Environment(EntityStore.self) private var store
    @State private var sheet: TodoSheet?
    /// Bumped after a save or delete so every list reloads (web `todoReloadVersion`).
    @State private var reloadVersion = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
                header()
                let sections = TodoPageLayout.sections(for: page, viewerUserId: model.viewerUserId, store: store, todos: model.todos)
                if TodoPageLayout.showsEmptyState(sections) {
                    emptyState
                }
                ForEach(sections.filter(\.isShown)) { section in
                    TodoListSection(
                        list: section.list,
                        controller: section.controller,
                        showsHeader: !page.hideListHeaders,
                        layout: page.isDonetick ? .grid : .list,
                        editor: { editAction(for: section.list, item: $0) }
                    )
                }
            }
            .padding(.horizontal, HassTokens.Spacing.l)
            .padding(.vertical, HassTokens.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        }
        .scrollTelemetry("Chores · \(page.id)")
        .accessibilityIdentifier("todo.page.\(page.id)")
        .floatingActionBar([
            FloatingAction(id: "add", title: TodoPageLayout.addTitle(page.addAction), symbol: "plus") { sheet = .create },
        ])
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
                .presentationDragIndicator(.visible)
        }
    }

    private var emptyState: some View {
        let vacation = store.entity(ChoresConfig.vacationModeEntityId).state?.state == "on"
        return ContentUnavailableView {
            Label(page.emptyTitle, systemImage: "checkmark.circle")
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
            guard let taskId = item.donetickTaskId, let uid = item.uid else { return nil }
            return { sheet = .editTask(DonetickEditTarget(itemUid: uid, taskId: taskId, todoEntityId: list.entityId)) }
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
}

/// An admin to-do opened for renaming (web `AdminTodoEditTarget`).
struct AdminTodoEditTarget: Hashable, Sendable {
    var itemUid: String?
    var originalTitle: String
    var todoEntityId: String
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
        page.lists.compactMap { list in
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
    }

    /// The empty state shows once every list is known and none is drawn, or when no list is visible at all.
    static func showsEmptyState(_ sections: [Section]) -> Bool {
        sections.allSatisfy { $0.isSettled && !$0.isShown }
    }

    /// The Add button's label.
    static func addTitle(_ action: ChoresConfig.AddAction) -> String {
        if case .groceryItem = action { return "Add Groceries" }
        return "Add Task"
    }
}
