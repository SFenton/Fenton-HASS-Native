#if DEBUG
import Foundation
import HassCore
import HassDesign
import SwiftUI

/// Gallery page for Chores, Groceries and To-Do on fixture lists with a recording service, so journeys,
/// audits and screenshots reach every page and sheet without touching the house.
/// `FENTON_GALLERY_TODO_PAGE=<page id>` opens another page as the root (e.g. `to-do`);
/// `FENTON_GALLERY_VIEWER=steph` signs the fixtures in as Steph; `FENTON_GALLERY_EMPTY=1` empties every list;
/// `FENTON_GALLERY_FAIL_COMPLETE=1` makes every check-off fail after 4 s, to show a row leave and come back;
/// `FENTON_GALLERY_CHORES=<n>` adds `n` more chores to each of Stephen's lists, as many as the real house has, for the
/// scroll cost probe.
struct ChoresGallery: View {
    @State private var store: EntityStore
    @State private var model: ChoresModel
    @State private var service: ChoresFixtureService
    private let page: ChoresConfig.Page

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let empty = environment["FENTON_GALLERY_EMPTY"] == "1"
        let store = EntityStore()
        let service = ChoresFixtureService(store: store, lists: empty ? [:] : ChoresFixtures.lists(extra: Int(environment["FENTON_GALLERY_CHORES"] ?? "") ?? 0),
                                           failsCompletion: environment["FENTON_GALLERY_FAIL_COMPLETE"] == "1")
        store.replaceAll(service.entityStates())
        let viewer = environment["FENTON_GALLERY_VIEWER"].flatMap(ChoresConfig.Resident.init(rawValue:)) ?? .stephen
        _store = State(initialValue: store)
        _service = State(initialValue: service)
        _model = State(initialValue: ChoresModel(service: service, todos: TodoStore(service: service), viewerUserId: viewer.haUserId))
        page = environment["FENTON_GALLERY_TODO_PAGE"].flatMap(ChoresConfig.page) ?? ChoresConfig.chores
    }

    var body: some View {
        // Owns its stack with the fixtures injected above it, as the app injects the store above its section
        // stacks, so pushed pages inherit them. The last-call line stays inside, on the root page, so the
        // floating Add bar sits above it (outside the stack it covered the bar at AX5, 2026-10-13).
        NavigationStack {
            Group {
                if page == ChoresConfig.chores {
                    ChoresContent()
                } else {
                    TodoPageScreen(page: page)
                }
            }
            // The house backdrop and header fade the app's section stack gives its root (direction G): on the system's
            // ground G's translucent rows measured 3.1:1.
            .pageChrome()
            .safeAreaInset(edge: .bottom) {
                // FENTON_GALLERY_CLEAN=1 (screenshots) leaves the debug line out.
                if !GalleryEnvironment.isClean {
                    GalleryLastCall(text: service.lastCall)
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .background(.bar)
                }
            }
        }
        .environment(store)
        .environment(model)
        .preferredColorScheme(.dark)
    }
}

/// Fixture todo lists keyed by entity id, due dates relative to now.
enum ChoresFixtures {
    static func iso(_ offset: TimeInterval, from now: Date = .now) -> String {
        ISO8601DateFormatter().string(from: now.addingTimeInterval(offset))
    }

    /// - Parameter extra: More chores for each of Stephen's lists (a house as long as the real one, for the scroll cost probe).
    static func lists(now: Date = .now, extra: Int = 0) -> [String: [TodoItem]] {
        let hour = 3600.0, day = 86_400.0
        func task(_ id: Int, _ summary: String, due: TimeInterval?, description: String? = nil) -> TodoItem {
            TodoItem(uid: "\(id)--fixture", summary: summary, description: description, due: due.map { iso($0, from: now) })
        }
        var lists: [String: [TodoItem]] = [
            "todo.stephen_s_past_due_with_unassigned": [task(11, "Take out the recycling", due: -3 * hour), task(12, "Clean the gutters", due: -9 * day)],
            "todo.stephen_s_evening_with_unassigned": [task(13, "Run the dishwasher", due: 5 * hour)],
            "todo.stephen_s_no_due_date_with_unassigned": [
                task(14, "Replace battery", due: nil, description: "Front door lock battery is at 18%. Maintenance reference: BATT-FD01"),
            ],
            "todo.stephen_s_upcoming_today_by_time_and_future_with_unassigned": [task(15, "Water the plants", due: 2 * day)],
            "todo.shopping_list": [
                TodoItem(uid: "g1", summary: "Oat milk"), TodoItem(uid: "g2", summary: "Coffee beans"), TodoItem(uid: "g3", summary: "Lemons"),
            ],
            // A resident's page reads the `_with_unassigned` views, which hold the same chores here.
            "todo.stephen_s_due_today_with_unassigned": [task(13, "Run the dishwasher", due: 5 * hour)],
            "todo.stephen_s_upcoming_with_unassigned": [task(15, "Water the plants", due: 2 * day)],
            "todo.steph_s_due_today_with_unassigned": [task(21, "Fold laundry", due: 3 * hour)],
            "todo.steph_s_upcoming_with_unassigned": [task(22, "Book the vet", due: 30 * day)],
            "todo.stephen_s_past_due": [task(11, "Take out the recycling", due: -3 * hour), task(12, "Clean the gutters", due: -9 * day)],
            "todo.stephen_s_due_today": [task(13, "Run the dishwasher", due: 5 * hour)],
            "todo.stephen_s_upcoming": [task(15, "Water the plants", due: 2 * day)],
            "todo.stephen_s_no_due_date": [task(14, "Replace battery", due: nil, description: "Front door lock battery is at 18%. Maintenance reference: BATT-FD01")],
            "todo.steph_s_due_today": [task(21, "Fold laundry", due: 3 * hour)],
            "todo.steph_s_upcoming": [task(22, "Book the vet", due: 30 * day)],
            "todo.unassigned_past_due": [task(31, "Vacuum the stairs", due: -2 * day)],
            "todo.unassigned_no_due_date": [task(32, "Organize the garage", due: nil)],
            "todo.home_improvement_s_upcoming": [task(41, "Paint the deck", due: 75 * day)],
            "todo.groceries": [TodoItem(uid: "a1", summary: "Port the Chores page"), TodoItem(uid: "a2", summary: "Check the backup job")],
        ]
        for key in lists.keys where extra > 0 && key.hasPrefix("todo.stephen_s_") {
            // Alternating overdue and upcoming, so the page shows both due-label tones.
            lists[key, default: []] += (0..<extra).map { n in
                task(1000 + n, "Fixture chore \(n + 1)", due: n.isMultiple(of: 2) ? -Double(n + 1) * day : Double(n + 1) * day)
            }
        }
        return lists
    }

    /// A `donetick.get_task` response for a fixture task.
    static func task(id: Int, name: String) -> JSONValue {
        .object([
            "id": .number(Double(id)), "name": .string(name), "description": .string("Fixture task"),
            "assignees": .array([.number(1)]), "assigned_to": .number(1), "frequency": .number(1),
            "frequency_type": .string("weekly"), "frequency_metadata": .object([:]), "hide_on_vacation": .bool(true),
            "next_due_date": .string(iso(2 * 86_400)), "priority": .number(3),
        ])
    }
}

/// Serves fixture lists and records calls, applying check-offs, adds and renames like Home Assistant would.
@MainActor
@Observable
final class ChoresFixtureService: TodoServicing {
    private(set) var lastCall = "none"
    private var lists: [String: [TodoItem]]
    private let store: EntityStore
    private var nextId = 100
    /// Check-offs fail after 4 s (the optimistic rollback journey).
    private let failsCompletion: Bool

    /// A call the fixture refuses.
    struct Refused: Error {}

    init(store: EntityStore, lists: [String: [TodoItem]], failsCompletion: Bool = false) {
        self.store = store
        self.lists = lists
        self.failsCompletion = failsCompletion
    }

    /// One entity per configured list; its state is the open-item count, like Home Assistant's todo entities.
    func entityStates() -> [EntityState] {
        let ids = Set(ChoresConfig.pages.flatMap(\.lists).map(\.entityId))
        return ids.map { EntityState(entityId: $0, state: String(lists[$0, default: []].filter { $0.status != .completed }.count)) }
            + [EntityState(entityId: ChoresConfig.vacationModeEntityId, state: "off")]
    }

    func todoItems(entityId: String) async throws -> [TodoItem] { lists[entityId, default: []] }

    func callServiceForResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        lastCall = "\(domain).\(service)"
        let id = data["task_id"] as? Int ?? 0
        let name = lists.values.joined().first { $0.donetickTaskId == id }?.summary ?? "Task"
        return .object(["response": ChoresFixtures.task(id: id, name: name)])
    }

    func uploadAdminTodo(_ upload: AdminTodoUpload, accessToken: String) async throws {
        lastCall = "upload \(upload.item) (\(upload.images.count) images)"
        add(upload.item, to: upload.entityId)
    }

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        let entityId = data["entity_id"] as? String ?? ""
        let item = data["item"] as? String ?? ""
        lastCall = "\(domain).\(service) \(item)".trimmingCharacters(in: .whitespaces)
        switch (domain, service) {
        case ("todo", "update_item"):
            if failsCompletion, data["status"] as? String == "completed" {
                // Long enough for the row to be seen leaving before it comes back.
                try await Task.sleep(for: .seconds(4))
                lastCall += " failed"
                throw Refused()
            }
            if let status = (data["status"] as? String).flatMap(TodoItem.Status.init(rawValue:)) { update(entityId, item) { $0.status = status } }
            if let rename = data["rename"] as? String { update(entityId, item) { $0.summary = rename } }
        case ("todo", "add_item"):
            add(item, to: entityId)
        case ("todo", "remove_item"):
            lists[entityId]?.removeAll { $0.identity == item }
        case ("script", _):
            update(ChoresConfig.adminTodoEntityId, item) { $0.status = .completed }
        default:
            break
        }
        store.replaceAll(entityStates())
    }

    private func add(_ summary: String, to entityId: String) {
        nextId += 1
        lists[entityId, default: []].append(TodoItem(uid: "new-\(nextId)", summary: summary))
        store.replaceAll(entityStates())
    }

    private func update(_ entityId: String, _ identity: String, _ change: (inout TodoItem) -> Void) {
        guard let index = lists[entityId]?.firstIndex(where: { $0.identity == identity }) else { return }
        change(&lists[entityId]![index])
    }
}
#endif
