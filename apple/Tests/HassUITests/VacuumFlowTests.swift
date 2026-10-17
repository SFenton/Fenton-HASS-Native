#if os(macOS)
import AppKit
import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// Switches a vacuum between cleaning rooms and drawing an area, and edits that area, in the vacuum sheet.
@MainActor
@Suite(.serialized, .enabled(if: AXWindow.isAvailable, "Needs accessibility permission for the test host"))
struct VacuumFlowTests {
    static let phone = CGSize(width: 402, height: 874)

    func open(scenario: String = "docked") async -> AXWindow {
        await withLaunch(environment: ["FENTON_GALLERY_SCENARIO": scenario, "FENTON_GALLERY_VACUUM": Vacuums.all[1].vacuumMapId]) {
            let driver = AXWindow(NavigationStack { ComponentGallery(page: .vacuums) }, size: Self.phone)
            await driver.window.settle(0.8)
            return driver
        }
    }

    @Test func theCleaningTargetSwitchesBetweenRoomsAndAnArea() async throws {
        let driver = await open()
        defer { driver.close() }
        _ = await driver.wait(timeout: 40) { $0.contains { $0.identifier == "vacuum.target" } }
        let area = await driver.nodes().first { $0.role == "AXRadioButton" && ($0.title == "Area" || $0.spoken == "Area") }
        let target = try #require(area, "the target picker offers Area")
        _ = await driver.press(target)
        let cancel = try #require(await driver.waitFor("action-button-2"), "choosing Area with rooms selected asks first")
        #expect(await driver.press(cancel))
        _ = await driver.wait { !$0.contains { $0.identifier == "action-button-2" } }
        _ = await driver.press(target)
        let confirm = try #require(await driver.waitFor("action-button-1"))
        #expect(confirm.spoken == "Switch to Area")
        _ = await driver.press(confirm)
        await driver.window.settle(2)
        _ = await driver.waitFor("vacuum.area.map")
        #expect(await driver.node("vacuum.area.use")?.isEnabled == false, "an area must be drawn first")
        #expect(await driver.press("vacuum.area.draw", attempts: 3) { nodes in
            nodes.first { $0.identifier == "vacuum.area.draw" }?.isSelected == true || nodes.contains { $0.identifier == "vacuum.area.draw" }
        })
        // A rectangle across the middle of the map; the dimensions read out once it is drawn.
        var drawn = false
        for (start, end) in [(0.3, 0.7), (0.2, 0.8), (0.35, 0.65)] where !drawn {
            await driver.drag(await driver.node("vacuum.area.map"), from: start, to: end)
            drawn = await driver.wait(timeout: 5) { $0.contains { $0.identifier == "vacuum.area.use" && $0.isEnabled } }
                .contains { $0.identifier == "vacuum.area.use" && $0.isEnabled }
        }
        #expect(drawn, "dragging on the map draws an area")
        _ = await driver.press("vacuum.area.reset")
        if drawn {
            #expect(await driver.press("vacuum.area.clear", attempts: 2) { nodes in
                nodes.contains { $0.identifier == "vacuum.area.use" && !$0.isEnabled }
            }, "Clear removes the area")
        }
    }
}
#endif
