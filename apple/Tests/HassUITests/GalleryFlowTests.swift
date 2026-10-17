#if os(macOS)
import AppKit
import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// Presses, drags and types through gallery pages the way the journeys do, reading the page's last-action line.
@MainActor
@Suite(.serialized, .enabled(if: AXWindow.isAvailable, "Needs accessibility permission for the test host"))
struct GalleryFlowTests {
    static let phone = CGSize(width: 402, height: 874)

    func page(_ page: ComponentGallery.Page, size: CGSize = GalleryFlowTests.phone) async -> AXWindow {
        let driver = AXWindow(NavigationStack { ComponentGallery(page: page) }, size: size)
        await driver.window.settle(0.6)
        return driver
    }

    /// The gallery's last-action line once it satisfies `matches`.
    func lastAction(_ driver: AXWindow, _ matches: @escaping (String) -> Bool) async -> String {
        await driver.text("gallery.lastCall") { matches($0) } ?? "no last-action line"
    }

    // MARK: Direction G

    @Test func chipsTilesAndButtonsReportTheirTaps() async throws {
        let driver = await page(.directionG)
        defer { driver.close() }
        #expect(await lastAction(driver) { $0 == "Last action: none" } == "Last action: none")
        func said(_ text: String) -> ([AXWindow.Node]) -> Bool { { nodes in nodes.last { $0.identifier == "gallery.lastCall" }?.value.contains(text) == true } }
        #expect(await driver.press("g.chip.Lights", until: said("chip Lights")))
        #expect(await driver.press("g.tile.Office Lamp", until: said("tile Office Lamp")))
        #expect(await driver.press("g.tile.Garage Door", until: said("tile Garage Door")))
    }

    @Test func tappingTheLightTileFlipsItOffAndOnAndDraggingSetsItsLevel() async throws {
        let driver = await page(.directionG)
        defer { driver.close() }
        let tile = try #require(await driver.waitFor("g.tile.light"))
        #expect(tile.spoken == "Kitchen Lights" && tile.value == "60%", "the tile starts at 60%")
        func said(_ text: String) -> ([AXWindow.Node]) -> Bool { { nodes in nodes.last { $0.identifier == "gallery.lastCall" }?.value.contains(text) == true } }
        #expect(await driver.press("g.tile.light", until: said("power false")), "a tap on a lit tile turns it off")
        let off = await driver.wait { $0.contains { $0.identifier == "g.tile.light" && $0.value == "Off" } }
        #expect(off.first { $0.identifier == "g.tile.light" }?.value == "Off", "the tile reads Off at once")
        #expect(await driver.press("g.tile.light", until: said("power true")), "and on again")
        let dragged = try #require(await driver.node("g.tile.light"))
        await driver.drag(dragged, from: 0.3, to: 0.85)
        let line = await lastAction(driver) { $0.contains("brightness") }
        let level = Int(line.components(separatedBy: "brightness ").last ?? "") ?? -1
        #expect((70...95).contains(level), "dragging to 85% across the tile commits about 85, got \(line)")
    }

    @Test func theSectionSheetSwitchesBetweenItsTabs() async throws {
        let driver = await withLaunch(defaults: ["directionGOrder": "lower"]) { await page(.directionG) }
        defer { driver.close() }
        #expect(await driver.press("g.primary") { $0.contains { $0.spoken == "Families" } })
        let tabs = await driver.wait { $0.contains { $0.spoken == "Families" } }
        #expect(tabs.contains { $0.spoken == "Families" }, "the sheet opens on its tab bar")
        #expect(tabs.contains { $0.spoken == "Floor Lamp" }, "on its Controls tab")
        let familiesTab = try #require(await driver.node(label: "Families"))
        #expect(await driver.press(familiesTab) { $0.contains { $0.spoken.hasPrefix("Lights") } })
        let families = await driver.wait { $0.contains { $0.spoken.hasPrefix("Lights") } && !$0.contains { $0.spoken == "Floor Lamp" } }
        #expect(families.contains { $0.spoken.hasPrefix("Lights") }, "Families lists every colour family")
        #expect(!families.contains { $0.spoken == "Floor Lamp" }, "and drops the controls")
    }

    // MARK: Floating actions

    @Test func theFloatingBarAddsASortsAndFiltersThroughItsSheets() async throws {
        let driver = await page(.floatingActions)
        defer { driver.close() }
        #expect(await driver.press("fab.add") { nodes in nodes.last { $0.identifier == "gallery.lastCall" }?.value.contains("add") == true })
        #expect(await driver.press("fab.sort") { $0.contains { $0.identifier == "gallery.sort.expiring" } })
        let sheet = await driver.wait { $0.contains { $0.identifier == "gallery.sort.expiring" } }
        #expect(sheet.contains { $0.identifier == "gallery.sort.expiring" }, "the sort sheet lists its options")
        #expect(sheet.first { $0.identifier == "filterSheet.apply" }?.isEnabled == false, "nothing changed yet")
        #expect(await driver.press("gallery.sort.expiring") { $0.contains { $0.identifier == "filterSheet.apply" && $0.isEnabled } })
        let ready = await driver.wait { $0.contains { $0.identifier == "filterSheet.apply" && $0.isEnabled } }
        #expect(ready.contains { $0.identifier == "filterSheet.apply" && $0.isEnabled }, "choosing another option enables Apply")
        #expect(ready.contains { $0.identifier == "filterSheet.reset" }, "and offers Reset to Defaults")
        #expect(await driver.press("filterSheet.apply") { nodes in nodes.last { $0.identifier == "gallery.lastCall" }?.value.contains("sort Expiring Soon") == true })
        #expect(await lastAction(driver) { $0.contains("sort Expiring Soon") } == "Last action: sort Expiring Soon")
    }
}
#endif
