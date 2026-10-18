#if os(macOS)
import AppKit
import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// Drives the Your Summary sheet through its gallery the way the journeys do: the four tabs and their badges, the Chores
/// page's rows with their edit button, the Food page's rows with their cart and chevron, and the empty and vacation
/// states. Every service call lands on the fixture services, shown on the gallery's last-call line; nothing reaches a house.
@MainActor
@Suite(.serialized, .enabled(if: AXWindow.isAvailable, "Needs accessibility permission for the test host"))
struct YourSummaryFlowTests {
    static let phone = CGSize(width: 402, height: 874)
    static let tablet = CGSize(width: 810, height: 1080)

    /// The profile gallery with `environment` set, settled.
    func open(_ environment: [String: String] = [:], size: CGSize = YourSummaryFlowTests.phone) async -> AXWindow {
        await withLaunch(environment: environment) {
            let driver = AXWindow(ComponentGallery(page: .profile), size: size)
            await driver.window.settle(1.0)
            return driver
        }
    }

    func lastCall(_ driver: AXWindow, _ matches: @escaping (String) -> Bool) async -> String {
        await driver.text("gallery.lastCall") { matches($0) } ?? "no last-call line"
    }

    /// Presses a tab and waits for `identifier` to appear, pressing again if the click was lost: the content loads on the main
    /// actor, which other suites share, so it can take a while.
    func openTab(_ driver: AXWindow, _ tab: String, expecting identifier: String) async -> Bool {
        for _ in 0..<3 {
            await driver.press("summary.tabs.\(tab)")
            let nodes = await driver.wait(timeout: 90) { $0.contains { $0.identifier == identifier } }
            if nodes.contains(where: { $0.identifier == identifier }) { return true }
        }
        return false
    }

    // MARK: Tabs

    @Test func opensOnOverdueChoresWithBadgesOnTheTwoActionableTabs() async throws {
        let driver = await open()
        defer { driver.close() }
        let overdue = try #require(await driver.waitFor("summary.tabs.overdue", timeout: 90))
        #expect(overdue.spoken == "Overdue Chores, 2 items", "two chores slipped past their date")
        #expect(await driver.node("summary.tabs.expired-food")?.spoken == "Expired Food, 3 items")
        #expect(await driver.node("summary.tabs.upcoming")?.spoken == "Upcoming Chores", "upcoming chores never badge")
        #expect(await driver.node("summary.tabs.profile")?.spoken == "Profile")
        #expect(await driver.waitFor("todo.item.11--fixture", timeout: 90) != nil, "it opens on the overdue chores")
        #expect(await driver.waitFor("todo.item.12--fixture", timeout: 90) != nil)
        #expect(await driver.shows("Take out the recycling"))
        #expect(await driver.shows("Clean the gutters"))
        #expect(await driver.shows("Your Summary"))
    }

    @Test func tappingATabShowsItsContent() async throws {
        let driver = await open()
        defer { driver.close() }
        _ = await driver.waitFor("summary.tabs.upcoming", timeout: 90)
        #expect(await openTab(driver, "upcoming", expecting: "todo.item.13--fixture"))
        #expect(await driver.shows("Upcoming Chores"))
        #expect(await driver.shows("No Due Date"), "chores without a due date follow, under their own header")
        #expect(await driver.shows("Replace Battery"))
        #expect(await openTab(driver, "expired-food", expecting: "inventory.row.Cereal"))
        #expect(await openTab(driver, "profile", expecting: "account.header"))
        #expect(await driver.shows("People at Home"))
        #expect(await openTab(driver, "overdue", expecting: "todo.item.11--fixture"))
    }

    @Test func profileKeepsTheAccountsExtras() async throws {
        let driver = await open(["FENTON_GALLERY_TAB": "profile"])
        defer { driver.close() }
        let header = try #require(await driver.waitFor("account.header", timeout: 90))
        #expect(header.value.contains("Stephen Fenton"), "\(header.value)")
        #expect(await driver.shows("Stephen Fenton, Home"), "a resident at home")
        #expect(await driver.shows("Steph Fenton, Away"), "a resident away")
        #expect(await driver.shows("Guest, Home"))
        #expect(await driver.shows("People at Home"))
        #expect(await driver.shows("2 of 3 Home"))
        let signOut = try #require(await driver.node("account.signOut"))
        #expect(signOut.spoken == "Sign Out")
    }

    @Test func aGuestSeesProfileAndExpiredFoodOnly() async throws {
        let driver = await open(["FENTON_GALLERY_VIEWER": "guest"])
        defer { driver.close() }
        _ = try #require(await driver.waitFor("summary.tabs.profile", timeout: 90))
        #expect(await driver.node("summary.tabs.overdue") == nil)
        #expect(await driver.node("summary.tabs.upcoming") == nil)
        #expect(await driver.node("summary.tabs.expired-food")?.spoken == "Expired Food, 3 items")
        #expect(await driver.shows("Summary"))
        #expect(await driver.shows("Cereal"), "a guest opens on Expired Food")
    }

    @Test func stephsEmptyOverdueTabSaysShesCaughtUp() async throws {
        let driver = await open(["FENTON_GALLERY_VIEWER": "steph"])
        defer { driver.close() }
        _ = try #require(await driver.waitFor("summary.empty.overdue", timeout: 90))
        #expect(await driver.shows("No Chores Due"))
        #expect(await driver.shows("You are all caught up on chores that slipped past their due date."))
        #expect(await driver.node("summary.tabs.overdue")?.spoken == "Overdue Chores", "no count when nothing is overdue")
    }

    // MARK: Chores

    @Test func overdueRowsAreTheChoresPagesWithAnEditButtonThatOpensTheTaskForm() async throws {
        let driver = await open()
        defer { driver.close() }
        let row = try #require(await driver.waitFor("todo.item.11--fixture", timeout: 90))
        #expect(row.spoken == "Take out the recycling" && row.value.hasPrefix("Not done"))
        let edit = try #require(await driver.node("todo.edit.11--fixture"))
        #expect(edit.spoken == "Edit Take out the recycling")
        #expect(await driver.press(edit) { $0.contains { $0.identifier == "task.save" } })
        #expect(await lastCall(driver) { $0.contains("get_task") }.contains("donetick.get_task"), "the form loads the task")
    }

    @Test func checkingAChoreOffGoesThroughTheSharedControllerToTheFixtureService() async throws {
        let driver = await open()
        defer { driver.close() }
        let row = try #require(await driver.waitFor("todo.item.12--fixture", timeout: 90))
        #expect(await driver.press(row))
        let call = await lastCall(driver) { $0.contains("update_item") }
        #expect(call.contains("todo.update_item") && call.contains("12--fixture"), "\(call)")
    }

    // MARK: Expired food

    @Test func expiredRowsAreTheFoodPagesRowsOldestFirst() async throws {
        let driver = await open(["FENTON_GALLERY_TAB": "expired-food"])
        defer { driver.close() }
        let cereal = try #require(await driver.waitFor("inventory.row.Cereal", timeout: 90))
        #expect(await driver.shows("Cereal, Quantity 2, Expired"), "the stock count above one, then the red expiry line")
        #expect(await driver.shows("Jasmine Rice, Expired"))
        let rice = try #require(await driver.node("inventory.row.Jasmine Rice"))
        let yogurt = try #require(await driver.node("inventory.row.Greek Yogurt"))
        #expect(cereal.frame.minY < rice.frame.minY && rice.frame.minY < yogurt.frame.minY, "soonest expiry (the oldest) first")
        #expect(await driver.shows("Expired Food"))
    }

    @Test func theCartAsksForAQuantityAndTheChevronOpensTheItemEditor() async throws {
        let driver = await open(["FENTON_GALLERY_TAB": "expired-food"])
        defer { driver.close() }
        _ = try #require(await driver.waitFor("inventory.row.Jasmine Rice", timeout: 90))
        let carts = await driver.nodes().filter { $0.identifier == "inventory.row.cart" }
        #expect(carts.count == 3, "one cart per expired item")
        // Cereal expired longest ago, so it leads; its cart asks how many to add.
        #expect(carts.first?.spoken == "Add Cereal to shopping list")
        #expect(await driver.press(try #require(carts.first)) { $0.contains { $0.value == "Add Cereal to Groceries" } })
        #expect(await driver.shows("Quantity of Cereal to add to the grocery cart."))
        let edits = await driver.nodes().filter { $0.identifier == "inventory.row.edit" }
        #expect(edits.count == 3)
    }

    // MARK: Vacation and empty

    @Test func vacationHidesExpiredFoodAndSaysEnjoyVacation() async throws {
        let driver = await open(["FENTON_GALLERY_TAB": "expired-food", "FENTON_GALLERY_VACATION": "1"])
        defer { driver.close() }
        _ = try #require(await driver.waitFor("summary.empty.expired-food", timeout: 90))
        #expect(await driver.shows("Expired Food Hidden"))
        #expect(await driver.shows("Enjoy vacation!"))
        #expect(await driver.node("summary.tabs.expired-food")?.spoken == "Expired Food", "vacation puts the badge on hold")
    }

    @Test func vacationWithNothingExpiredSaysNoExpiredFood() async throws {
        let driver = await open(["FENTON_GALLERY_TAB": "expired-food", "FENTON_GALLERY_VACATION": "1", "FENTON_GALLERY_EMPTY": "1"])
        defer { driver.close() }
        _ = try #require(await driver.waitFor("summary.empty.expired-food", timeout: 90))
        #expect(await driver.shows("No Expired Food"))
        #expect(await driver.shows("Enjoy vacation!"))
    }

    @Test func emptyChoreTabsSayEnjoyVacationInVacationMode() async throws {
        for (tab, title) in [("overdue", "No Chores Due"), ("upcoming", "No Chores Upcoming")] {
            let driver = await open(["FENTON_GALLERY_TAB": tab, "FENTON_GALLERY_VACATION": "1", "FENTON_GALLERY_EMPTY": "1"])
            defer { driver.close() }
            _ = try #require(await driver.waitFor("summary.empty.\(tab)", timeout: 90))
            #expect(await driver.shows(title), "\(tab)")
            #expect(await driver.shows("Enjoy vacation!"), "\(tab)")
        }
    }

    @Test func nothingExpiredShowsTheNoExpiredFoodState() async throws {
        let driver = await open(["FENTON_GALLERY_TAB": "expired-food", "FENTON_GALLERY_EMPTY": "1"])
        defer { driver.close() }
        _ = try #require(await driver.waitFor("summary.empty.expired-food", timeout: 90))
        #expect(await driver.shows("Everything in the kitchen is still within date."))
    }

    // MARK: Regular width

    @Test func regularWidthShowsTheTabTitlesBesideTheirIcons() async throws {
        let driver = await open(size: Self.tablet)
        defer { driver.close() }
        _ = try #require(await driver.waitFor("summary.tabs.overdue", timeout: 90))
        #expect(await driver.shows("Upcoming Chores"))
        #expect(await driver.waitFor("todo.item.11--fixture", timeout: 90) != nil)
    }
}
#endif
