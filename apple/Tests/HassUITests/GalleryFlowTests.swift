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
        #expect(await driver.press("g.chip.Lights"))
        #expect(await lastAction(driver) { $0.contains("chip Lights") } == "Last action: chip Lights")
        #expect(await driver.press("g.tile.Office Lamp"))
        #expect(await lastAction(driver) { $0.contains("tile Office Lamp") } == "Last action: tile Office Lamp")
        #expect(await driver.press("g.tile.Garage Door"))
        #expect(await lastAction(driver) { $0.contains("tile Garage Door") } == "Last action: tile Garage Door")
    }

    @Test func theSectionSheetSwitchesBetweenItsTabs() async throws {
        let driver = await withLaunch(defaults: ["directionGOrder": "lower"]) { await page(.directionG) }
        defer { driver.close() }
        #expect(await driver.press("g.primary"))
        let tabs = await driver.wait { $0.contains { $0.spoken == "Families" } }
        #expect(tabs.contains { $0.spoken == "Families" }, "the sheet opens on its tab bar")
        #expect(tabs.contains { $0.spoken == "Floor Lamp" }, "on its Controls tab")
        #expect(await driver.press(try #require(await driver.node(label: "Families"))))
        let families = await driver.wait { $0.contains { $0.spoken.hasPrefix("Lights") } }
        #expect(families.contains { $0.spoken.hasPrefix("Lights") }, "Families lists every colour family")
        #expect(!families.contains { $0.spoken == "Floor Lamp" }, "and drops the controls")
    }

    // MARK: Floating actions

    @Test func theFloatingBarAddsASortsAndFiltersThroughItsSheets() async throws {
        let driver = await page(.floatingActions)
        defer { driver.close() }
        #expect(await driver.press("fab.add"))
        #expect(await lastAction(driver) { $0.contains("add") } == "Last action: add")
        #expect(await driver.press("fab.sort"))
        let sheet = await driver.wait { $0.contains { $0.identifier == "gallery.sort.expiring" } }
        #expect(sheet.contains { $0.identifier == "gallery.sort.expiring" }, "the sort sheet lists its options")
        #expect(sheet.first { $0.identifier == "filterSheet.apply" }?.isEnabled == false, "nothing changed yet")
        #expect(await driver.press("gallery.sort.expiring"))
        let ready = await driver.wait { $0.contains { $0.identifier == "filterSheet.apply" && $0.isEnabled } }
        #expect(ready.contains { $0.identifier == "filterSheet.apply" && $0.isEnabled }, "choosing another option enables Apply")
        #expect(ready.contains { $0.identifier == "filterSheet.reset" }, "and offers Reset to Defaults")
        #expect(await driver.press("filterSheet.apply"))
        #expect(await lastAction(driver) { $0.contains("sort Expiring Soon") } == "Last action: sort Expiring Soon")
    }
}
#endif
