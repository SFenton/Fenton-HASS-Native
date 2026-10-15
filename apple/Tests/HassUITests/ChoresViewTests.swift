import Foundation
@preconcurrency import HAKit
@preconcurrency import HAKit_Mocks
@testable import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// Hosted renders of the Chores tab, every todo page and sheet, plus their pure policies, on fixture lists.
@MainActor
struct ChoresViewTests {
    static let phone = CGSize(width: 402, height: 874)
    static let tablet = CGSize(width: 1210, height: 834)

    private struct Fixture {
        var store: EntityStore
        var service: ChoresFixtureService
        var model: ChoresModel
    }

    private func fixture(empty: Bool = false, viewer: ChoresConfig.Resident? = .stephen) -> Fixture {
        let store = EntityStore()
        let service = ChoresFixtureService(store: store, lists: empty ? [:] : ChoresFixtures.lists())
        store.replaceAll(service.entityStates())
        let model = ChoresModel(service: service, todos: TodoStore(service: service), viewerUserId: viewer?.haUserId)
        return Fixture(store: store, service: service, model: model)
    }

    private func render(_ view: some View, _ fixture: Fixture, size: CGSize = phone, typeSize: DynamicTypeSize = .large) -> CGImage? {
        let hosted = view
            .environment(fixture.store)
            .environment(fixture.model)
            .dynamicTypeSize(typeSize)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: hosted)
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.cgImage
    }

    /// Loads every list so pages render rows instead of spinners.
    private func loadAll(_ fixture: Fixture) async {
        for page in ChoresConfig.pages {
            for list in page.lists { await fixture.model.todos.controller(for: list.entityId).load() }
        }
    }

    // MARK: Pages

    @Test func choresTabRendersLoadingLoadedAndLarge() async {
        let fixture = fixture()
        #expect(render(NavigationStack { ChoresContent() }, fixture) != nil, "Before loading")
        await loadAll(fixture)
        #expect(render(NavigationStack { ChoresContent() }, fixture) != nil)
        #expect(render(NavigationStack { ChoresContent() }, fixture, size: Self.tablet) != nil)
        #expect(render(NavigationStack { ChoresContent() }, fixture, typeSize: .accessibility5) != nil)
    }

    @Test func everyPageRendersFullAndEmpty() async {
        let full = fixture()
        await loadAll(full)
        let empty = fixture(empty: true, viewer: .steph)
        await loadAll(empty)
        for page in ChoresConfig.pages {
            #expect(render(NavigationStack { TodoPageScreen(page: page) }, full) != nil, "\(page.id)")
            #expect(render(NavigationStack { TodoPageScreen(page: page) }, empty) != nil, "\(page.id) empty")
        }
    }

    @Test func galleryRendersEachVariant() {
        for environment in [[:], ["FENTON_GALLERY_TODO_PAGE": "to-do", "FENTON_GALLERY_VIEWER": "steph", "FENTON_GALLERY_EMPTY": "1"]] {
            let renderer = ImageRenderer(content: NavigationStack { ChoresGallery(environment: environment) }.frame(width: 402, height: 874))
            #expect(renderer.cgImage != nil)
        }
    }

    // MARK: Layout policy

    @Test func sectionsHideEmptyListsAndShowTheEmptyStateWhenSettled() async {
        let fixture = fixture()
        let page = ChoresConfig.stephsChores
        var sections = TodoPageLayout.sections(for: page, viewerUserId: nil, store: fixture.store, todos: fixture.model.todos)
        // Steph has items only in Due Today and Upcoming; the others report 0 and are settled already.
        #expect(sections.map(\.isShown) == [false, true, true, false])
        #expect(sections.map(\.isSettled) == [true, false, false, true])
        #expect(!TodoPageLayout.showsEmptyState(sections))
        await loadAll(fixture)
        sections = TodoPageLayout.sections(for: page, viewerUserId: nil, store: fixture.store, todos: fixture.model.todos)
        #expect(sections.map(\.isShown) == [false, true, true, false])
        #expect(sections.allSatisfy { $0.isSettled })
        #expect(sections[1].id == "todo.steph_s_due_today")

        let empty = self.fixture(empty: true)
        let emptySections = TodoPageLayout.sections(for: page, viewerUserId: nil, store: empty.store, todos: empty.model.todos)
        #expect(TodoPageLayout.showsEmptyState(emptySections))
        // The Chores tab shows no lists to a viewer who isn't a resident.
        #expect(TodoPageLayout.sections(for: ChoresConfig.chores, viewerUserId: nil, store: fixture.store, todos: fixture.model.todos).isEmpty)
        #expect(TodoPageLayout.showsEmptyState([]))
    }

    @Test func unavailableListsMayHaveItems() {
        let fixture = fixture()
        fixture.store.replaceAll([EntityState(entityId: "todo.shopping_list", state: "unavailable")])
        let sections = TodoPageLayout.sections(for: ChoresConfig.groceries, viewerUserId: nil, store: fixture.store, todos: fixture.model.todos)
        #expect(sections.first?.isShown == true)
        #expect(sections.first?.isSettled == false)
    }

    @Test func loadedListWithOnlyCompletedItemsHides() async {
        let fixture = fixture()
        let controller = fixture.model.todos.controller(for: "todo.shopping_list")
        await controller.load()
        for item in controller.items! { try? await fixture.service.callService("todo", "update_item", data: ["entity_id": "todo.shopping_list", "item": item.identity, "status": "completed"]) }
        fixture.store.replaceAll([EntityState(entityId: "todo.shopping_list", state: "3")])
        await controller.load()
        let sections = TodoPageLayout.sections(for: ChoresConfig.groceries, viewerUserId: nil, store: fixture.store, todos: fixture.model.todos)
        #expect(sections.first?.isShown == false)
        #expect(TodoPageLayout.showsEmptyState(sections))
    }

    /// Groceries moves last, where it spans the final row; each kind of list has its own glyph (mockup n5-chores).
    @Test func quickLinksPutGroceriesLastWithGlyphs() {
        let links = ChoreQuickLinks.links
        #expect(links.count == ChoresConfig.quickLinks.count)
        #expect(links.last?.countsGroceries == true)
        #expect(Set(links.map(ChoreQuickLinks.symbol(for:))).count == 4, "Person, tray, hammer and cart")
    }

    /// Add Grocery and rename open at the medium detent; the task form opens full height (direction G, Sheets).
    @Test func shortPromptsOpenAtMediumHeight() {
        let target = DonetickEditTarget(itemUid: "1", taskId: 1, todoEntityId: "todo.x")
        let rename = AdminTodoEditTarget(itemUid: "a1", originalTitle: "Port", todoEntityId: "todo.groceries")
        #expect(TodoPageLayout.isShortPrompt(.create, addAction: ChoresConfig.groceries.addAction))
        #expect(!TodoPageLayout.isShortPrompt(.create, addAction: ChoresConfig.chores.addAction))
        #expect(!TodoPageLayout.isShortPrompt(.create, addAction: ChoresConfig.adminTodo.addAction))
        #expect(TodoPageLayout.isShortPrompt(.renameTodo(rename), addAction: ChoresConfig.adminTodo.addAction))
        #expect(!TodoPageLayout.isShortPrompt(.editTask(target), addAction: ChoresConfig.chores.addAction))
    }

    @Test func addTitlesFollowTheWeb() {
        #expect(TodoPageLayout.addTitle(ChoresConfig.groceries.addAction) == "Add Groceries")
        #expect(TodoPageLayout.addTitle(ChoresConfig.chores.addAction) == "Add Task")
        #expect(TodoPageLayout.addTitle(ChoresConfig.adminTodo.addAction) == "Add Task")
    }

    // MARK: Rows

    @Test func rowsRenderEveryStateAndRead() {
        let fixture = fixture()
        let now = Date()
        let rows: [TodoItem] = [
            TodoItem(uid: "1", summary: "Late", due: ChoresFixtures.iso(-3600, from: now)),
            TodoItem(uid: "2", summary: "Very late", due: ChoresFixtures.iso(-9 * 86_400, from: now)),
            TodoItem(uid: "3", summary: "Soon", due: ChoresFixtures.iso(3600, from: now)),
            TodoItem(uid: "4", summary: "Done", status: .completed),
        ]
        for item in rows {
            #expect(render(TodoItemRow(item: item, now: now, onToggle: {}, onEdit: {}), fixture, size: CGSize(width: 402, height: 120)) != nil)
            #expect(render(TodoItemRow(item: item, now: now, onToggle: {}), fixture, size: CGSize(width: 402, height: 300), typeSize: .accessibility5) != nil)
        }
        #expect(TodoListSection.hasLateItem([rows[0]], now: now))
        #expect(TodoListSection.hasLateItem([rows[1]], now: now))
        #expect(!TodoListSection.hasLateItem([rows[2], rows[3]], now: now), "Due soon and done rows stay on the thin module")
        #expect(DueLabel.color(.overdueLong) == HassTokens.Ink.error)
        #expect(DueLabel.color(.overdueHours) == HassTokens.Ink.warning)
        #expect(TodoItemRow.accessibilityValue(completed: true, due: "Due in 1 hour") == "Done")
        #expect(TodoItemRow.accessibilityValue(completed: false, due: "Due in 1 hour") == "Not done, Due in 1 hour")
        #expect(TodoItemRow.accessibilityValue(completed: false, due: nil) == "Not done")
    }

    @Test func sectionRendersErrorAndList() async {
        let fixture = fixture()
        let list = ChoresConfig.stephensChores.lists[0]
        let controller = fixture.model.todos.controller(for: list.entityId)
        #expect(render(TodoListSection(list: list, controller: controller), fixture) != nil, "Loading")
        await controller.load()
        #expect(render(TodoListSection(list: list, controller: controller, editSymbol: "pencil", editor: { _ in {} }), fixture) != nil)
        let items = controller.visibleItems(hideCompleted: list.hideCompleted)
        #expect(TodoListSection.hasLateItem(items, now: .now), "Past Due rows are late: the module turns dense")
        let failing = MockFailingService()
        let broken = TodoListController(entityId: list.entityId, service: failing, cached: [])
        await broken.load()
        #expect(broken.error != nil)
        #expect(render(TodoListSection(list: list, controller: broken, showsHeader: false), fixture) != nil)
    }

    // MARK: Sheets

    @Test func sheetsRender() {
        let fixture = fixture()
        let target = DonetickEditTarget(itemUid: "11--fixture", taskId: 11, todoEntityId: "todo.stephen_s_past_due")
        let sheets: [AnyView] = [
            AnyView(DonetickTaskSheet(mode: .create(defaultAssignee: "1"))),
            AnyView(DonetickTaskSheet(mode: .edit(target))),
            AnyView(AddGroceryItemSheet(entityId: ChoresConfig.groceryEntityId)),
            AnyView(AddAdminTodoSheet(entityId: ChoresConfig.adminTodoEntityId)),
            AnyView(RenameTodoItemSheet(target: AdminTodoEditTarget(itemUid: "a1", originalTitle: "Port", todoEntityId: "todo.groceries"))),
            AnyView(RenameTodoItemSheet(target: AdminTodoEditTarget(itemUid: nil, originalTitle: "Port", todoEntityId: "todo.groceries"))),
            AnyView(AdminTodoImageRow(image: .init(data: Data(), filename: "a.png", mimeType: "image/png")) {}),
        ]
        for sheet in sheets {
            #expect(render(sheet, fixture) != nil)
            #expect(render(sheet, fixture, typeSize: .accessibility5) != nil)
        }
        #expect(DonetickTaskSheet.Mode.create(defaultAssignee: "").editTarget == nil)
        #expect(DonetickTaskSheet.Mode.edit(target).editTarget == target)
    }

    @Test func formFieldsRenderEveryRecurrence() {
        let fixture = fixture()
        for recurrence in ["no_repeat", "interval", "days_of_the_week"] {
            var form = DonetickTaskForm()
            form.setRecurrence(recurrence)
            form.dueDate = "2026-10-11"
            form.dueTime = "08:30"
            form.recurrenceDays = ["monday"]
            let fields = DonetickTaskFormFields(form: .constant(form), editing: true, viewer: .stephen, error: "Unable to save task", onDelete: {})
            #expect(render(fields, fixture) != nil, "\(recurrence)")
        }
    }

    @Test func renameNeedsANewNonEmptyName() {
        let target = AdminTodoEditTarget(itemUid: "a", originalTitle: "Port ", todoEntityId: "todo.groceries")
        #expect(!RenameTodoItemSheet.canSave(target: target, draft: "Port"))
        #expect(!RenameTodoItemSheet.canSave(target: target, draft: "   "))
        #expect(RenameTodoItemSheet.canSave(target: target, draft: "Ship"))
        #expect(!RenameTodoItemSheet.canSave(target: AdminTodoEditTarget(itemUid: nil, originalTitle: "", todoEntityId: "x"), draft: "Ship"))
    }

    @Test func sheetIdsAreDistinct() {
        let target = DonetickEditTarget(itemUid: "1--x", taskId: 1, todoEntityId: "todo.a")
        let ids = [TodoSheet.create, .editTask(target), .renameTodo(AdminTodoEditTarget(itemUid: nil, originalTitle: "T", todoEntityId: "todo.b")),
                   .renameTodo(AdminTodoEditTarget(itemUid: "u", originalTitle: "T", todoEntityId: "todo.b"))].map(\.id)
        #expect(Set(ids).count == 4)
    }

    @Test func dueBindingsConvertDatesAndTimes() {
        var form = DonetickTaskForm()
        let binding = Binding(get: { form }, set: { form = $0 })
        let noon = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 9, minute: 15))!
        DonetickDueBinding.hasDate(binding, now: noon).wrappedValue = true
        #expect(form.dueDate == "2026-10-11")
        #expect(DonetickDueBinding.hasDate(binding).wrappedValue)
        DonetickDueBinding.hasTime(binding).wrappedValue = true
        #expect(form.dueTime == "12:00")
        DonetickDueBinding.time(binding).wrappedValue = noon
        #expect(form.dueTime == "09:15")
        #expect(DonetickDueBinding.time(binding).wrappedValue != Date.distantPast)
        let later = noon.addingTimeInterval(86_400)
        DonetickDueBinding.date(binding).wrappedValue = later
        #expect(form.dueDate == "2026-10-12")
        #expect(DonetickDueBinding.date(binding).wrappedValue != Date.distantPast)
        DonetickDueBinding.hasDate(binding).wrappedValue = false
        DonetickDueBinding.hasTime(binding).wrappedValue = false
        #expect(form.dueDate.isEmpty && form.dueTime.isEmpty)
        #expect(!DonetickDueBinding.hasTime(binding).wrappedValue)
    }

    // MARK: Model and fixtures

    @Test func modelRefreshesTheViewer() async {
        let fixture = fixture(viewer: nil)
        var answer: String? = ChoresConfig.Resident.steph.haUserId
        let model = ChoresModel(service: fixture.service, todos: fixture.model.todos, viewerUserId: nil, loadViewer: { answer })
        #expect(model.viewer == nil)
        await model.refreshViewer()
        #expect(model.viewer == .steph)
        answer = nil
        await model.refreshViewer()
        #expect(model.viewer == .steph, "A failed lookup keeps the cached viewer")
        await #expect(throws: (any Error).self) { _ = try await model.accessToken() }
    }

    @Test func liveModelUsesTheConnection() async {
        let defaults = UserDefaults(suiteName: "chores-\(UUID())")!
        defaults.set(ChoresConfig.Resident.stephen.haUserId, forKey: ChoresModel.viewerDefaultsKey)
        let connection = HassConnection(server: .fentonHome, tokens: TokenManager(store: InMemoryTokenStore()), store: EntityStore())
        let model = ChoresModel.live(connection: connection, session: nil, defaults: defaults)
        #expect(model.viewer == .stephen)
        #expect(model.todos === TodoStore.shared(for: connection))
        await #expect(throws: (any Error).self) { _ = try await model.accessToken() }
    }

    @Test func fixtureServiceActsLikeHomeAssistant() async throws {
        let fixture = fixture()
        let service = fixture.service
        try await service.callService("todo", "add_item", data: ["entity_id": "todo.shopping_list", "item": "Eggs"])
        #expect(fixture.store.value("todo.shopping_list")?.state == "4")
        try await service.callService("todo", "update_item", data: ["entity_id": "todo.shopping_list", "item": "g1", "rename": "Milk"])
        try await service.callService("todo", "update_item", data: ["entity_id": "todo.shopping_list", "item": "g2", "status": "completed"])
        #expect(fixture.store.value("todo.shopping_list")?.state == "3")
        try await service.callService("todo", "remove_item", data: ["entity_id": "todo.shopping_list", "item": "g3"])
        try await service.callService("script", "complete_admin_todo_item", data: ["item": "a1"])
        try await service.callService("light", "turn_on", data: [:])
        #expect(service.lastCall == "light.turn_on")
        let items = try await service.todoItems(entityId: "todo.shopping_list")
        #expect(items.map(\.summary) == ["Milk", "Coffee beans", "Eggs"])
        #expect(try await service.todoItems(entityId: "todo.groceries").first?.status == .completed)
        let task = try await service.callServiceForResponse("donetick", "get_task", data: ["task_id": 11])
        #expect(try DonetickTask(response: task).name == "Take out the recycling")
        try await service.uploadAdminTodo(AdminTodoUpload(entityId: "todo.groceries", item: "Pic", images: []), accessToken: "t")
        #expect(service.lastCall == "upload Pic (0 images)")
    }
}

/// Fails every call, for error states.
@MainActor
private final class MockFailingService: TodoServicing {
    struct Failure: Error {}
    func todoItems(entityId: String) async throws -> [TodoItem] { throw Failure() }
    func callServiceForResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue { throw Failure() }
    func uploadAdminTodo(_ upload: AdminTodoUpload, accessToken: String) async throws { throw Failure() }
    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws { throw Failure() }
}
