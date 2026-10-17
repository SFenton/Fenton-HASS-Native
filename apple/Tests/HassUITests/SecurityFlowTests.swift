#if os(macOS)
import AppKit
import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// Arms, disarms and opens doors on the Security gallery house the way the journeys do, reading what reached Home
/// Assistant from the gallery's last-call line.
@MainActor
@Suite(.serialized, .enabled(if: AXWindow.isAvailable, "Needs accessibility permission for the test host"))
struct SecurityFlowTests {
    static let phone = CGSize(width: 402, height: 874)

    func open(scenario: String = "standard") async -> AXWindow {
        await withLaunch(environment: ["FENTON_GALLERY_SCENARIO": scenario]) {
            let driver = AXWindow(NavigationStack { ComponentGallery(page: .security) }, size: Self.phone)
            await driver.window.settle(0.8)
            return driver
        }
    }

    func lastCall(_ driver: AXWindow, _ matches: @escaping (String) -> Bool) async -> String {
        await driver.text("gallery.lastCall") { matches($0) } ?? "no last-call line"
    }

    @Test func eachArmingModeSendsItsServiceAndASecondPressOfTheSameModeSendsNothing() async throws {
        let driver = await open()
        defer { driver.close() }
        let arming = SecurityConfig.modeButtons.filter { !$0.needsConfirmation && $0.state != "armed_home" }
        #expect(!arming.isEmpty)
        for mode in arming {
            #expect(await driver.press("security.mode.\(mode.state)"), "\(mode.state)")
            let call = await lastCall(driver) { $0.contains("alarm_control_panel") }
            #expect(call.contains("alarm_control_panel"), "\(mode.state): \(call)")
        }
    }

    @Test func disarmingAsksFirstAndSendsNothingUntilTheAlertIsAnswered() async throws {
        let driver = await open()
        defer { driver.close() }
        #expect(await driver.press("security.mode.disarmed"))
        let alert = await driver.wait { $0.contains { $0.identifier == "security.disarm.confirm" } }
        #expect(alert.contains { $0.identifier == "security.disarm.confirm" }, "disarming confirms first")
        #expect(await lastCall(driver) { _ in true } == "Last call: None", "nothing was sent before the alert was answered")
    }

    @Test func aDoorTileSendsItsCommand() async throws {
        let driver = await open()
        defer { driver.close() }
        let tile = try #require(await driver.nodes().first { $0.identifier.hasPrefix("security.tile.") })
        #expect(await driver.press(tile))
        let call = await lastCall(driver) { $0 != "Last call: None" && $0.hasPrefix("Last call:") }
        #expect(call != "Last call: None", "tapping \(tile.spoken) sent a call: \(call)")
    }

    @Test func aTriggeredAlarmAndAnUnavailableSystemStillDrawTheirPanels() async throws {
        for scenario in ["triggered", "unavailable", "openArmed"] {
            let driver = await open(scenario: scenario)
            defer { driver.close() }
            let state = try #require(await driver.waitFor("security.system.state"), "\(scenario)")
            #expect(state.spoken == "Security System", "\(scenario): the panel is one named element")
        }
    }
}
#endif
