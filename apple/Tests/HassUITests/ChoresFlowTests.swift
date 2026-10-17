#if os(macOS)
import AppKit
import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// Adds, checks off, renames and creates tasks through the Chores gallery's pages the way the journeys do, reading
/// the call the fixture service recorded from the gallery's last-call line.
@MainActor
@Suite(.serialized, .enabled(if: AXWindow.isAvailable, "Needs accessibility permission for the test host"))
struct ChoresFlowTests {
    static let phone = CGSize(width: 402, height: 874)

    /// The chores gallery opened on `pageId`.
    func open(_ pageId: String, viewer: String = "stephen") async -> AXWindow {
        await withLaunch(environment: ["FENTON_GALLERY_TODO_PAGE": pageId, "FENTON_GALLERY_VIEWER": viewer]) {
            let driver = AXWindow(NavigationStack { ComponentGallery(page: .chores) }, size: Self.phone)
            await driver.window.settle(0.8)
            return driver
        }
    }

    /// The gallery's last-call line once it satisfies `matches`.
    func lastCall(_ driver: AXWindow, _ matches: @escaping (String) -> Bool) async -> String {
        await driver.text("gallery.lastCall") { matches($0) } ?? "no last-call line"
    }

    @Test func aGroceryItemIsAddedFromItsSheet() async throws {
        let driver = await open("groceries")
        defer { driver.close() }
        _ = await driver.waitFor("todo.page.groceries")
        #expect(await driver.press("fab.add") { $0.contains { $0.identifier == "grocery.item" } })
        _ = try #require(await driver.waitFor("grocery.item"))
        let add = try #require(await driver.node("grocery.add"))
        #expect(!add.isEnabled, "Add waits for a name")
        #expect(await driver.type("Bananas", into: "grocery.item") { $0.contains { $0.identifier == "grocery.add" && $0.isEnabled } })
        #expect(await driver.press("grocery.add") { nodes in nodes.last { $0.identifier == "gallery.lastCall" }?.value.contains("add_item") == true })
        let call = await lastCall(driver) { $0.contains("add_item") }
        #expect(call.contains("todo.add_item") && call.contains("Bananas"), "\(call)")
        let closed = await driver.wait { !$0.contains { $0.identifier == "grocery.item" } }
        #expect(!closed.contains { $0.identifier == "grocery.item" }, "the sheet closes once the item is added")
    }

    @Test func aGroceryItemIsCheckedOffFromTheList() async throws {
        let driver = await open("groceries")
        defer { driver.close() }
        let item = try #require(await driver.waitFor("todo.item.g1"))
        #expect(item.spoken == "Oat milk" && item.value == "Not done")
        #expect(await driver.press(item))
        let call = await lastCall(driver) { $0.contains("update_item") }
        #expect(call.contains("todo.update_item"), "\(call)")
    }

    @Test func anAdminTaskIsAddedFromItsSheet() async throws {
        let driver = await open("to-do")
        defer { driver.close() }
        #expect(await driver.press("fab.add") { $0.contains { $0.identifier == "adminTodo.task" } })
        #expect(await driver.type("Fix the porch light", into: "adminTodo.task") { $0.contains { $0.identifier == "adminTodo.add" && $0.isEnabled } })
        #expect(await driver.press("adminTodo.add") { nodes in nodes.last { $0.identifier == "gallery.lastCall" }?.value.contains("add_item") == true })
        let added = await lastCall(driver) { $0.contains("add_item") }
        #expect(added.contains("Fix the porch light"), "\(added)")
    }

    @Test func aChoreTaskOpensInTheFormAndSavesItsNewName() async throws {
        let driver = await open("stephens-chores")
        defer { driver.close() }
        let edit = try #require(await driver.waitFor("todo.edit.12--fixture"))
        #expect(edit.spoken.hasPrefix("Edit "))
        #expect(await driver.press(edit.identifier) { $0.contains { $0.identifier == "task.name" } }, "the pencil opens the task form")
        let name = try #require(await driver.waitFor("task.name"))
        let loaded = await driver.wait { $0.contains { $0.identifier == "task.name" && !$0.value.isEmpty } }
        #expect(loaded.first { $0.identifier == "task.name" }?.value.isEmpty == false, "the form loads the task's name")
        #expect(await driver.node("task.delete") != nil, "an existing task can be deleted")
        #expect(await driver.type("Clean the gutters twice", into: name.identifier) { $0.contains { $0.identifier == "task.name" && $0.value == "Clean the gutters twice" } })
        #expect(await driver.press("task.save"))
        let call = await lastCall(driver) { $0.contains("donetick") }
        #expect(call.contains("donetick"), "\(call)")
    }

    @Test func aChoreTaskIsCreatedFromTheTaskForm() async throws {
        let driver = await open("stephens-chores")
        defer { driver.close() }
        _ = await driver.waitFor("todo.page.stephens-chores")
        #expect(await driver.press("fab.add") { $0.contains { $0.identifier == "task.name" } })
        let name = try #require(await driver.waitFor("task.name"))
        #expect(await driver.node("task.save")?.isEnabled == false, "a task needs a name")
        for id in ["task.description", "task.assignee", "task.priority", "task.recurrence", "task.hasDueDate", "task.hideOnVacation"] {
            #expect(await driver.node(id) != nil, "\(id)")
        }
        _ = name
        #expect(await driver.type("Wipe the counters", into: "task.name") { $0.contains { $0.identifier == "task.save" && $0.isEnabled } })
        #expect(await driver.press("task.save") { nodes in nodes.last { $0.identifier == "gallery.lastCall" }?.value.contains("donetick") == true })
        let call = await lastCall(driver) { $0.contains("create_task") || $0.contains("donetick") }
        #expect(call.contains("donetick"), "\(call)")
    }
}
#endif
