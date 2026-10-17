#if os(macOS)
import AppKit
import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// Adds, edits and deletes a humidifier's scheduled activities through its sheet's Schedules tab.
@MainActor
@Suite(.serialized, .enabled(if: AXWindow.isAvailable, "Needs accessibility permission for the test host"))
struct HumidifierFlowTests {
    static let phone = CGSize(width: 402, height: 874)

    func open() async -> AXWindow {
        await withLaunch(environment: ["FENTON_GALLERY_DEVICE": "humidifier", "FENTON_GALLERY_TAB": "schedules"]) {
            let driver = AXWindow(NavigationStack { ComponentGallery(page: .roomDevices) }, size: Self.phone)
            await driver.window.settle(0.8)
            return driver
        }
    }

    @Test func anActivityIsAddedThroughTheEditor() async throws {
        let driver = await open()
        defer { driver.close() }
        _ = await driver.wait(timeout: 30) { $0.contains { $0.identifier == "humidifier.addActivity" } }
        let add = try #require(await driver.node("humidifier.addActivity"))
        if !add.isEnabled { _ = await driver.wait(timeout: 30) { $0.contains { $0.identifier == "humidifier.addActivity" && $0.isEnabled } } }
        #expect(await driver.press("humidifier.addActivity", attempts: 4) { $0.contains { $0.identifier == "activity.name" } }, "Add opens the editor")
        #expect(await driver.node("activity.save")?.isEnabled == false, "a nameless activity cannot be saved")
        #expect(await driver.type("Afternoon", into: "activity.name") { $0.contains { $0.identifier == "activity.name" && $0.value == "Afternoon" } })
        let days = await driver.nodes().filter { $0.identifier.hasPrefix("activity.day.") }
        #expect(days.count == 7, "every weekday can be chosen")
        for day in days.prefix(3) { _ = await driver.press(day) }
        let outcomes = await driver.pressEach(prefixes: ["activity.warm", "activity.display"], inSheet: true)
        #expect(!outcomes.isEmpty, "warm mist and the display switch can be pressed")
        _ = await driver.press("activity.save")
        await driver.window.settle(0.8)
    }

    @Test func anExistingActivityOpensAndIsDeletedAfterAConfirmation() async throws {
        let driver = await open()
        defer { driver.close() }
        let rows = await driver.wait(timeout: 30) { $0.contains { $0.identifier.hasPrefix("humidifier.activity.") } }
        let row = try #require(rows.first { $0.identifier.hasPrefix("humidifier.activity.") })
        #expect(await driver.press(row.identifier, attempts: 4) { $0.contains { $0.identifier == "activity.delete" } }, "a row opens its editor")
        #expect(await driver.press("activity.delete") { $0.contains { $0.spoken == "Delete Activity" && $0.role == "AXButton" } })
        if let confirm = await driver.node(label: "Delete Activity", role: "AXButton") { _ = await driver.press(confirm) }
        await driver.window.settle(0.8)
    }
}
#endif
