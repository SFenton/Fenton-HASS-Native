#if os(macOS)
import AppKit
import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// Edits an item's batches and adds an item by scanning it, on the EverShelf fixture server.
@MainActor
@Suite(.serialized, .enabled(if: AXWindow.isAvailable, "Needs accessibility permission for the test host"))
struct InventoryFlowTests {
    static let phone = CGSize(width: 402, height: 874)

    func open(_ environment: [String: String]) async -> AXWindow {
        await withLaunch(environment: environment) {
            let driver = AXWindow(NavigationStack { ComponentGallery(page: .inventory) }, size: Self.phone)
            await driver.window.settle(0.8)
            return driver
        }
    }

    @Test func aBatchQuantityIsEditedAndSaved() async throws {
        let driver = await open(["FENTON_GALLERY_OPEN": "editor:Honey", "FENTON_GALLERY_SPACE": "pantry"])
        defer { driver.close() }
        _ = await driver.wait(timeout: 40) { $0.contains { $0.identifier == "inventory.editor.save" } }
        #expect(await driver.node("inventory.editor.save")?.isEnabled == false, "nothing changed yet")
        // The batch's switches (an expiry date, prepared food) change its draft, which Save then sends.
        var changed = false
        for toggle in await driver.nodes().filter({ $0.role == "AXCheckBox" && $0.identifier == "inventory.editor" }) where !changed {
            _ = await driver.press(toggle)
            changed = await driver.wait(timeout: 4) { $0.contains { $0.identifier == "inventory.editor.save" && $0.isEnabled } }
                .contains { $0.identifier == "inventory.editor.save" && $0.isEnabled }
        }
        #expect(changed, "a changed quantity can be saved")
        _ = await driver.press("inventory.editor.save")
        let call = await driver.text("gallery.lastCall") { $0.contains("evershelf") && !$0.contains("list_inventory") } ?? "no call"
        #expect(call.contains("evershelf"), "\(call)")
    }

    @Test func anItemIsAddedByScanningItsBarcode() async throws {
        let driver = await open(["FENTON_GALLERY_OPEN": "scan", "FENTON_SCAN_CAMERA": "simulated", "FENTON_GALLERY_SPACE": "pantry"])
        defer { driver.close() }
        _ = await driver.wait(timeout: 40) { $0.contains { $0.identifier == "scan.simulate" } }
        #expect(await driver.press("scan.simulate", attempts: 4) { $0.contains { $0.role == "AXTextField" && $0.value == "Greek Yogurt" } }, "a simulated scan reads the barcode")
        for _ in 0..<4 where await driver.node("scan.add") == nil {
            _ = await driver.press("scan.forward")
            _ = await driver.wait(timeout: 6) { $0.contains { $0.identifier == "scan.add" } }
        }
        let toggles = await driver.nodes().filter { $0.role == "AXCheckBox" && $0.identifier == "scan.review" }
        #expect(!toggles.isEmpty, "the review offers its switches")
        for toggle in toggles { _ = await driver.press(toggle) }
        #expect(await driver.node(label: "Add to Fridge", role: "AXButton") != nil, "the review offers to add the item to the place it chose")
    }
}
#endif
