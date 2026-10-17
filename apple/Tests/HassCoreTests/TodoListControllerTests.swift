import Foundation
@testable import HassCore
import Testing

/// Serves canned items and records calls; set `failure` to make the next calls throw.
@MainActor
final class MockTodoService: TodoServicing {
    var items: [String: [TodoItem]] = [:]
    var calls: [String] = []
    var failure: (any Error)?
    var response: JSONValue = .null
    var uploads: [AdminTodoUpload] = []
    /// Suspends `todoItems` until resumed, to test overlapping loads.
    var gate: CheckedContinuation<Void, Never>?
    var holdsLoads = false

    struct Failure: Error, LocalizedError {
        var errorDescription: String? { "Server said no" }
    }

    func todoItems(entityId: String) async throws -> [TodoItem] {
        if holdsLoads { await withCheckedContinuation { continuation in MainActor.assumeIsolated { gate = continuation } } }
        if let failure { throw failure }
        return items[entityId, default: []]
    }

    func callServiceForResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        calls.append("\(domain).\(service)")
        if let failure { throw failure }
        return response
    }

    func uploadAdminTodo(_ upload: AdminTodoUpload, accessToken: String) async throws {
        if let failure { throw failure }
        uploads.append(upload)
    }

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        let described = data.keys.sorted().map { "\($0)=\(data[$0]!)" }.joined(separator: ",")
        calls.append("\(domain).\(service) \(described)")
        if let failure { throw failure }
    }
}

@MainActor
struct TodoListControllerTests {
    private let list = "todo.list"

    private func controller(_ service: MockTodoService, cached: [TodoItem]? = nil, onChange: @escaping (String, [TodoItem]) -> Void = { _, _ in }) -> TodoListController {
        TodoListController(entityId: list, service: service, cached: cached, onItemsChange: onChange)
    }

    @Test func loadSortsAndReportsChanges() async {
        let service = MockTodoService()
        service.items[list] = [TodoItem(uid: "b", summary: "B"), TodoItem(uid: "a", summary: "A", due: "2026-01-01")]
        var changes = 0
        let controller = controller(service) { _, _ in changes += 1 }
        #expect(controller.items == nil)
        #expect(controller.id == list)
        await controller.load()
        #expect(controller.items?.map(\.identity) == ["a", "b"])
        await controller.load()
        #expect(changes == 1, "An unchanged reload does not republish")
    }

    @Test func loadErrorKeepsItems() async {
        let service = MockTodoService()
        let controller = controller(service, cached: [TodoItem(uid: "a", summary: "A")])
        service.failure = MockTodoService.Failure()
        await controller.load()
        #expect(controller.error == "Server said no")
        #expect(controller.items?.count == 1)
        service.failure = nil
        await controller.load()
        #expect(controller.error == nil)
    }

    @Test func messageFallsBackForPlainErrors() {
        struct Plain: Error {}
        #expect(TodoListController.message(Plain(), fallback: "Unable") == "Unable")
    }

    @Test func overlappingLoadsKeepTheNewest() async {
        let service = MockTodoService()
        service.items[list] = [TodoItem(uid: "old", summary: "Old")]
        service.holdsLoads = true
        let controller = controller(service)
        let first = Task { await controller.load() }
        while service.gate == nil { await Task.yield() }
        let firstGate = service.gate
        service.gate = nil
        service.items[list] = [TodoItem(uid: "new", summary: "New")]
        let second = Task { await controller.load() }
        while service.gate == nil { await Task.yield() }
        service.gate?.resume()
        await second.value
        firstGate?.resume()
        await first.value
        #expect(controller.items?.map(\.identity) == ["new"])
    }

    @Test func toggleShowsOptimisticStatusThenConfirms() async {
        let service = MockTodoService()
        let item = TodoItem(uid: "a", summary: "A")
        service.items[list] = [item]
        let controller = controller(service)
        await controller.load()
        await controller.toggle(item)
        #expect(service.calls == ["todo.update_item entity_id=todo.list,item=a,status=completed"])
        #expect(controller.visibleItems(hideCompleted: true).isEmpty)
        #expect(controller.visibleItems(hideCompleted: false).first?.status == .completed)
        service.items[list] = [TodoItem(uid: "a", summary: "A", status: .completed)]
        await controller.load()
        #expect(controller.optimistic.pending.isEmpty)
        // Unchecking a completed item sends needs_action.
        await controller.toggle(controller.items![0])
        #expect(service.calls.last == "todo.update_item entity_id=todo.list,item=a,status=needs_action")
    }

    @Test func completionScriptRunsInsteadOfUpdate() async {
        let service = MockTodoService()
        let controller = controller(service)
        await controller.toggle(TodoItem(uid: "a", summary: "A"), completionScript: "script.complete_admin_todo_item")
        await controller.toggle(TodoItem(uid: "b", summary: "B"), completionScript: "finish")
        #expect(service.calls == ["script.complete_admin_todo_item item=a", "script.finish item=b"])
        await controller.toggle(TodoItem(uid: "c", summary: "C", status: .completed), completionScript: "finish")
        #expect(service.calls.last == "todo.update_item entity_id=todo.list,item=c,status=needs_action")
    }

    @Test func failedToggleRevertsAndShowsError() async {
        let service = MockTodoService()
        service.failure = MockTodoService.Failure()
        let item = TodoItem(uid: "a", summary: "A")
        let controller = controller(service, cached: [item])
        await controller.toggle(item)
        #expect(controller.visibleItems(hideCompleted: true) == [item])
        #expect(controller.error == "Server said no")
    }

    /// A swipe-to-delete removes the row at once, calls `todo.remove_item` and caches the shorter list.
    @Test func removeDropsTheRowAndCallsRemoveItem() async {
        let service = MockTodoService()
        let a = TodoItem(uid: "a", summary: "A"), b = TodoItem(uid: "b", summary: "B")
        var cached: [TodoItem] = []
        let controller = controller(service, cached: [a, b]) { _, items in cached = items }
        await controller.remove(a)
        #expect(controller.items == [b])
        #expect(cached == [b])
        #expect(service.calls == ["todo.remove_item entity_id=todo.list,item=a"])
        #expect(controller.error == nil)
    }

    /// A rejected delete puts the row back with the error, like a rejected check-off.
    @Test func failedRemoveBringsTheRowBack() async {
        let service = MockTodoService()
        service.failure = MockTodoService.Failure()
        let a = TodoItem(uid: "a", summary: "A")
        let controller = controller(service, cached: [a])
        await controller.remove(a)
        #expect(controller.items == [a])
        #expect(controller.error == "Server said no")
        await controller.remove(TodoItem(uid: nil, summary: nil))
        #expect(service.calls.count == 1, "An item without an identity sends nothing")
    }

    @Test func toggleIgnoresItemsWithoutIdentity() async {
        let service = MockTodoService()
        await controller(service).toggle(TodoItem(uid: nil, summary: nil))
        #expect(service.calls.isEmpty)
    }

    @Test func unconfirmedStatusRevertsAfterTheDelay() async throws {
        let service = MockTodoService()
        let item = TodoItem(uid: "a", summary: "A")
        let controller = controller(service, cached: [item])
        controller.revertDelay = .milliseconds(20)
        await controller.toggle(item)
        #expect(controller.visibleItems(hideCompleted: true).isEmpty)
        for _ in 0..<200 where controller.visibleItems(hideCompleted: true).isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(controller.visibleItems(hideCompleted: true) == [item])
    }
}

struct TodoOptimisticStatusesTests {
    @Test func newerRequestsOwnTheStatus() {
        var statuses = TodoOptimisticStatuses()
        let first = statuses.commit("a", .completed)
        let second = statuses.commit("a", .needsAction)
        statuses.clear("a", requestId: first)
        #expect(statuses.pending["a"]?.status == .needsAction)
        statuses.clear("a", requestId: second)
        #expect(statuses.pending.isEmpty)
        _ = statuses.commit("b", .completed)
        statuses.clear("b")
        #expect(statuses.pending.isEmpty)
        statuses.clear("missing")
    }

    @Test func confirmDropsMatchedAndMissingItems() {
        var statuses = TodoOptimisticStatuses()
        _ = statuses.commit("done", .completed)
        _ = statuses.commit("waiting", .completed)
        _ = statuses.commit("gone", .completed)
        statuses.confirm([TodoItem(uid: "done", summary: nil, status: .completed), TodoItem(uid: "waiting", summary: nil)])
        #expect(Array(statuses.pending.keys) == ["waiting"])
        let applied = statuses.apply(to: [TodoItem(uid: "waiting", summary: nil), TodoItem(uid: "other", summary: nil)])
        #expect(applied.map(\.status) == [.completed, .needsAction])
        #expect(TodoOptimisticStatuses().apply(to: applied) == applied)
    }
}

@MainActor
struct TodoStoreTests {
    private func temporaryCache(server: HassServer? = .fentonHome) -> (TodoItemsCache, URL) {
        let url = FileManager.default.temporaryDirectory.appending(path: "todo-\(UUID()).json")
        return (TodoItemsCache(server: server, fileURL: url), url)
    }

    @Test func controllersAreSharedAndLoadsAreCached() async throws {
        let (cache, url) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: url) }
        let service = MockTodoService()
        service.items["todo.a"] = [TodoItem(uid: "1", summary: "One")]
        let store = TodoStore(service: service, cache: cache)
        #expect(store.controller(for: "todo.a") === store.controller(for: "todo.a"))
        await store.controller(for: "todo.a").load()
        #expect(cache.load()["todo.a"]?.first?.summary == "One")
        // A new store (relaunch) starts from the cache.
        let relaunched = TodoStore(service: service, cache: cache)
        #expect(relaunched.controller(for: "todo.a").items?.count == 1)
    }

    @Test func cacheIgnoresOtherServersAndClears() throws {
        let (cache, url) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: url) }
        try cache.save(["todo.a": [TodoItem(uid: "1", summary: "One")]])
        #expect(cache.load().count == 1)
        let other = TodoItemsCache(server: HassServer(baseURL: URL(string: "https://example.com")!), fileURL: url)
        #expect(other.load().isEmpty)
        cache.clear()
        #expect(cache.load().isEmpty)
        #expect(TodoItemsCache.defaultURL.lastPathComponent == "TodoItems.json")
        #expect(TodoItemsCache().load() == TodoItemsCache().load())
    }
}
