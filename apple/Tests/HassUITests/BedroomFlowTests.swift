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

    @Test func aWakingWakeLightCanBeStopped() async throws {
        let driver = await open(sheet: "wake-light", scenario: "waking")
        defer { driver.close() }
        let stop = try #require(await driver.waitFor("wake.stop"))
        #expect(stop.isEnabled && stop.spoken == "Stop Wake-Light Episode")
        #expect(await driver.press("wake.stop") { nodes in nodes.last { $0.identifier == "gallery.lastCall" }?.value.hasPrefix("Last call: wake_light.command") == true },
                "stopping the episode sends the wake-light command")
        let idle = await open(sheet: "wake-light")
        defer { idle.close() }
        let nodes = await idle.wait { $0.contains { $0.identifier == "wake.add" } }
        #expect(!nodes.contains { $0.identifier == "wake.stop" }, "nothing to stop while the lights are not waking")
    }

    @Test(arguments: ["stephens-bed", "stephs-bed"])
    func aBedSideTurnsOffAfterAskingAndBackOnWithoutAsking(bed: String) async throws {
        let driver = await open(sheet: bed)
        defer { driver.close() }
        let nodes = await driver.wait { $0.contains { $0.identifier == "bed.power" } }
        #expect(nodes.contains { $0.identifier == "bed.dial" }, "the temperature tab shows the dial")
        let power = try #require(nodes.first { $0.identifier == "bed.power" })
        #expect(power.isEnabled && power.spoken.hasPrefix("Turn "), "\(power.spoken)")
        let turningOff = power.spoken == "Turn Off"
        if turningOff {
            // An on bed asks first; nothing is sent until the dialog is answered.
            #expect(await driver.press("bed.power") { $0.contains { $0.spoken == "Turn Off" && $0.identifier != "bed.power" } }, "turning a running bed off asks first")
            #expect(await driver.text("gallery.lastCall") == "Last call: None")
            let confirm = try #require(await driver.nodes().first { $0.spoken == "Turn Off" && $0.identifier != "bed.power" })
            #expect(await driver.press(confirm) { nodes in nodes.last { $0.identifier == "gallery.lastCall" }?.value != "Last call: None" })
        } else {
            #expect(await driver.press("bed.power") { nodes in nodes.last { $0.identifier == "gallery.lastCall" }?.value != "Last call: None" },
                    "turning an idle bed on sends at once")
        }
    }

    @Test func aWakeAlarmOpensInTheEditorFromItsRow() async throws {
        let driver = await open(sheet: "wake-light")
        defer { driver.close() }
        _ = await driver.waitFor("wake.add")
        let alarm = try #require(await driver.nodes().first { $0.identifier.hasPrefix("wake.alarm.") && !$0.identifier.hasSuffix(".enabled") && !$0.identifier.hasSuffix(".link") && !$0.identifier.hasSuffix(".open") })
        #expect(await driver.press(alarm.identifier) { $0.contains { $0.identifier == "wake.editor.name" } }, "tapping an alarm row opens its editor")
        let name = try #require(await driver.waitFor("wake.editor.name"))
        #expect(!name.value.isEmpty, "the editor loads the alarm's name")
        let nodes = await driver.nodes()
        #expect(nodes.contains { $0.identifier == "wake.editor.delete" }, "an existing alarm can be deleted")
        #expect(nodes.first { $0.identifier == "wake.editor.save" }?.isEnabled == false, "an unchanged alarm has nothing to save")
        #expect(await driver.press("wake.editor.delete") { $0.contains { $0.spoken == "Delete Alarm" } }, "Delete asks before it removes")
    }

    @Test func theWakeAlarmEditorSwitchesBetweenWeeklyAndOneTime() async throws {
        let driver = await open(sheet: "wake-light")
        defer { driver.close() }
        #expect(await driver.press("wake.add") { $0.contains { $0.identifier == "wake.editor.save" } }, "Add opens the editor")
        let segments = await driver.nodes().filter { $0.role == "AXRadioButton" }
        #expect(segments.count >= 2, "the editor offers the alarm types as segments: \(segments.map(\.spoken))")
        let once = try #require(segments.first { $0.spoken.lowercased().contains("one") || $0.title.lowercased().contains("one") })
        #expect(await driver.press(once) { $0.contains { $0.identifier == "wake.editor.date" } }, "a one-time alarm asks for a date")
        #expect(!(await driver.nodes()).contains { $0.identifier.hasPrefix("wake.editor.day.") }, "and not for weekdays")
        let weekly = try #require(await driver.nodes().first { $0.role == "AXRadioButton" && !($0.spoken.lowercased().contains("one") || $0.title.lowercased().contains("one")) })
        #expect(await driver.press(weekly) { $0.contains { $0.identifier.hasPrefix("wake.editor.day.") } }, "a weekly one asks for its days")
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

    @Test func theWakeAlarmEditorOffersDaysRampsAnEnabledSwitchAndBeds() async throws {
        let driver = await open(sheet: "wake-light")
        defer { driver.close() }
        #expect(await driver.press("wake.add") { $0.contains { $0.identifier == "wake.editor.save" } }, "Add opens the editor")
        let nodes = await driver.nodes()
        #expect(nodes.contains { $0.identifier.hasPrefix("wake.editor.day.") }, "a weekly alarm asks for its days")
        #expect(!nodes.contains { $0.identifier == "wake.editor.date" }, "and not for a date")
        let outcomes = await driver.pressEach(prefixes: ["wake.editor.day.", "wake.editor.ramp.", "wake.editor.enabled", "wake.editor.bed."],
                                              inSheet: true)
        #expect(outcomes.count >= 8, "days, ramps, the enabled switch and the bed toggles can all be pressed: \(outcomes.count)")
    }
}
#endif
