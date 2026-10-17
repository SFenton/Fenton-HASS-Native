#if os(macOS)
import AppKit
import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// Opens each of the modal sizing gallery's sheets from its page, as a person does, and presses what each offers.
@MainActor
@Suite(.serialized, .enabled(if: AXWindow.isAvailable, "Needs accessibility permission for the test host"))
struct ModalSizingFlowTests {
    static let phone = CGSize(width: 402, height: 874)

    func open(defaults: [String: String] = [:], size: CGSize = ModalSizingFlowTests.phone) async -> AXWindow {
        await withLaunch(defaults: defaults) {
            let driver = AXWindow(NavigationStack { ComponentGallery(page: .modalSizing) }, size: size)
            await driver.window.settle(0.8)
            return driver
        }
    }

    @Test(arguments: ["short", "tall", "tabs", "edit", "sort", "filter"])
    func eachSheetOpensFromItsButtonAndSurvivesEveryPress(kind: String) async throws {
        let driver = await open()
        defer { driver.close() }
        #expect(await driver.press("sizing.open.\(kind)", attempts: 4) { _ in driver.window.window.attachedSheet != nil },
                "the \(kind) button opens its sheet")
        _ = await driver.wait { nodes in nodes.contains { $0.identifier.hasPrefix("sizing.") && $0.identifier != "sizing.open.\(kind)" } }
        let outcomes = await driver.pressEach(prefixes: [""], inSheet: true, skipping: ControlSweepTests.endsTheSweep)
        _ = outcomes
        await driver.closeSheet()
    }

    @Test(arguments: ["short", "tall", "tabs", "edit", "sort", "filter"])
    func eachSheetOpensFromALaunchSwitchOnATablet(kind: String) async throws {
        let driver = await open(defaults: ["modalSizingOpen": kind], size: CGSize(width: 1210, height: 834))
        defer { driver.close() }
        _ = await driver.wait { _ in driver.window.window.attachedSheet != nil }
        #expect(driver.window.window.attachedSheet != nil, "the \(kind) sheet opens at launch")
        _ = await driver.pressEach(prefixes: [""], inSheet: true, skipping: ControlSweepTests.endsTheSweep)
    }
}
#endif
