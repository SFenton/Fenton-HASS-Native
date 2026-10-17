#if os(macOS)
import AppKit
import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// Presses through the Master Bedroom sheets (wake light and both bed sides) on the gallery house the way the
/// journeys do, and reads the service the recorder saw from the gallery's last-call line.
@MainActor
@Suite(.serialized, .enabled(if: AXWindow.isAvailable, "Needs accessibility permission for the test host"))
struct BedroomFlowTests {
    static let phone = CGSize(width: 402, height: 874)

    func open(sheet: String, tab: String? = nil, scenario: String = "default") async -> AXWindow {
        var environment = ["FENTON_GALLERY_SHEET": sheet, "FENTON_GALLERY_SCENARIO": scenario]
        if let tab { environment["FENTON_GALLERY_TAB"] = tab }
        return await withLaunch(environment: environment) {
            let driver = AXWindow(NavigationStack { ComponentGallery(page: .bedroom) }, size: Self.phone)
            await driver.window.settle(0.8)
            return driver
        }
    }

    /// The gallery's last-call line once it names something other than "None".
    func lastCall(_ driver: AXWindow) async -> String {
        await driver.text("gallery.lastCall") { $0 != "Last call: None" && $0.hasPrefix("Last call:") } ?? "no last-call line"
    }

    @Test func theWakeLightListsItsAlarmsAndAddsOneFromTheEditor() async throws {
        let driver = await open(sheet: "wake-light")
        defer { driver.close() }
        let nodes = await driver.wait { $0.contains { $0.identifier == "wake.add" } }
        #expect(nodes.contains { $0.identifier.hasPrefix("wake.alarm.") }, "the fixture house has wake alarms")
        #expect(await driver.press("wake.add") { $0.contains { $0.identifier == "wake.editor.save" } }, "Add opens the editor")
        let name = try #require(await driver.waitFor("wake.editor.name"))
        #expect(await driver.type("Weekend Sunrise", into: name))
        let save = await driver.wait { $0.contains { $0.identifier == "wake.editor.save" && $0.isEnabled } }
        #expect(save.contains { $0.identifier == "wake.editor.save" && $0.isEnabled }, "a named alarm can be saved")
        #expect(await driver.press("wake.editor.save"))
        let call = await lastCall(driver)
        #expect(call.hasPrefix("Last call:") && call != "Last call: None", "saving sent a service call: \(call)")
    }

    @Test func aWakingWakeLightOffersToStopTheEpisode() async throws {
        let driver = await open(sheet: "wake-light", scenario: "waking")
        defer { driver.close() }
        let stop = try #require(await driver.waitFor("wake.stop"))
        #expect(stop.isEnabled && stop.spoken == "Stop Wake-Light Episode")
        let idle = await open(sheet: "wake-light")
        defer { idle.close() }
        let nodes = await idle.wait { $0.contains { $0.identifier == "wake.add" } }
        #expect(!nodes.contains { $0.identifier == "wake.stop" }, "nothing to stop while the lights are not waking")
    }

    @Test(arguments: ["stephens-bed", "stephs-bed"])
    func aBedSideShowsItsDialAndPowerButton(bed: String) async throws {
        let driver = await open(sheet: bed)
        defer { driver.close() }
        let nodes = await driver.wait { $0.contains { $0.identifier == "bed.power" } }
        #expect(nodes.contains { $0.identifier == "bed.dial" }, "the temperature tab shows the dial")
        let power = try #require(nodes.first { $0.identifier == "bed.power" })
        #expect(power.isEnabled)
        #expect(power.spoken.hasPrefix("Turn "), "the button names what it does: \(power.spoken)")
    }

    @Test func aBedSideAddsAnAlarmThroughItsEditor() async throws {
        let driver = await open(sheet: "stephens-bed", tab: "alarms")
        defer { driver.close() }
        let nodes = await driver.wait { $0.contains { $0.identifier == "bed.alarms.add" } }
        #expect(nodes.contains { $0.identifier == "bed.alarms.add" })
        #expect(await driver.press("bed.alarms.add") { $0.contains { $0.identifier == "bed.editor.save" } }, "Add Alarm opens the editor")
        #expect(await driver.press("bed.editor.save"))
        let call = await lastCall(driver)
        #expect(call != "no last-call line" && call != "Last call: None", "saving sent a service call: \(call)")
    }
}
#endif
