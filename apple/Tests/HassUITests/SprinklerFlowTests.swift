#if os(macOS)
import AppKit
import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// Taps through the Sprinklers page on the gallery house the way a person does (accessibility identifiers and labels
/// are the handles), and reads what reaches Home Assistant from the gallery's last-call line.
@MainActor
@Suite(.serialized, .enabled(if: AXWindow.isAvailable, "Needs accessibility permission for the test host"))
struct SprinklerFlowTests {
    static let phone = CGSize(width: 402, height: 874)
    static let front = SprinklersConfig.frontYard
    static let back = SprinklersConfig.backyard

    /// The gallery page with one controller's sheet open.
    func open(_ controller: SprinklersConfig.Controller? = nil, detail: String? = nil) async -> AXWindow {
        var environment = ["FENTON_GALLERY_SPRINKLER": (controller ?? Self.front).id]
        if let detail { environment["FENTON_GALLERY_DETAIL"] = detail }
        return await withLaunch(environment: environment) {
            let driver = AXWindow(NavigationStack { ComponentGallery(page: .sprinklers) }, size: Self.phone)
            await driver.window.settle(0.8)
            return driver
        }
    }

    /// The gallery's last-call line once it names a call starting with `prefix`.
    func lastCall(_ driver: AXWindow, _ prefix: String) async -> String {
        await driver.text("gallery.lastCall") { $0.hasPrefix("Last call: \(prefix)") } ?? "no last-call line"
    }

    @Test func theOverviewListsStatusZonesControlsAndSchedule() async throws {
        let driver = await open()
        defer { driver.close() }
        let nodes = await driver.wait { $0.contains { $0.identifier == "sprinkler.overview" } }
        for heading in ["Status", "Zones", "Controls", "Settings", "Schedule"] {
            #expect(nodes.contains { $0.role == "AXHeading" && $0.spoken == heading }, "\(heading) section")
        }
        for pill in ["Controller", "Battery", "Next Watering", "Last Watering"] {
            #expect(nodes.contains { $0.spoken == pill }, "\(pill) pill")
        }
        for index in Self.front.zones.indices {
            #expect(nodes.contains { $0.identifier == "sprinkler.zone.\(index)" }, "zone \(index)")
        }
        // Idle controller: nothing to stop. Rain delay is off and smart watering on in the fixtures.
        let stop = try #require(nodes.first { $0.identifier == "sprinkler.stop" })
        #expect(!stop.isEnabled)
        #expect(nodes.first { $0.identifier == "sprinkler.rainDelay" }?.value == "0")
        #expect(nodes.first { $0.identifier == "sprinkler.smartWatering" }?.value == "1")
    }

    @Test func settingsSwitchesSendTheirServicesAndFlipOptimistically() async throws {
        let driver = await open()
        defer { driver.close() }
        func value(_ id: String, _ expected: String) -> ([AXWindow.Node]) -> Bool {
            { $0.contains { $0.identifier == id && $0.value == expected } }
        }
        // Rain delay starts off: the press shows the new value at once and sends its service.
        #expect(await driver.press("sprinkler.rainDelay", until: value("sprinkler.rainDelay", "1")), "the switch shows the new value at once")
        let afterRain = await lastCall(driver, "switch.turn_on")
        #expect(afterRain.contains(Self.front.rainDelayEntityId), "\(afterRain)")
    }

    @Test func aWateringControllerOffersToStopAndBlocksStartingAnotherZone() async throws {
        let driver = await open(Self.back)
        defer { driver.close() }
        let overview = await driver.wait { $0.contains { $0.identifier == "sprinkler.stop" } }
        #expect(overview.first { $0.identifier == "sprinkler.stop" }?.isEnabled == true)
        #expect(overview.contains { $0.identifier == "sprinkler.zone.1" && $0.spoken.contains("Watering") }, "the running zone reads Watering")
        // Another zone can't start while this one waters: Water now explains why and its Start button is off.
        #expect(await driver.press("sprinkler.zone.0"))
        let blocked = try #require(await driver.waitFor("sprinkler.waterBlocked"))
        #expect(blocked.value.contains("Another zone is watering"))
        #expect(await driver.node("sprinkler.startWatering")?.isEnabled == false)
    }

    @Test func waterNowStartsAZoneForTheChosenRunTime() async throws {
        let driver = await open()
        defer { driver.close() }
        #expect(await driver.press("sprinkler.zone.0"))
        let start = try #require(await driver.waitFor("sprinkler.startWatering"))
        #expect(start.isEnabled)
        #expect(await driver.node("sprinkler.runTime") != nil)
        #expect(await driver.press(start))
        let call = await lastCall(driver, "bhyve.start_watering")
        #expect(call.hasPrefix("Last call: bhyve.start_watering"), "\(call)")
        #expect(call.contains("\(SprinklersConfig.manualRunTime.default)"), "\(call)")
        #expect(call.contains(Self.front.zones[0].valveEntityId), "\(call)")
    }

    @Test func aProgramScheduleListsItsDaysAndTimesAndApplies() async throws {
        let driver = await open(detail: "schedule-0")
        defer { driver.close() }
        let apply = try #require(await driver.waitFor("sprinkler.schedule.apply"))
        let nodes = await driver.nodes()
        for day in 0..<7 {
            #expect(nodes.contains { $0.identifier == "sprinkler.schedule.day.\(day)" && $0.spoken == SprinklerFormat.dayNames[day] })
        }
        #expect(nodes.contains { $0.identifier == "sprinkler.schedule.time.0" })
        #expect(nodes.contains { $0.identifier == "sprinkler.schedule.budget" })
        #expect(nodes.contains { $0.identifier == "sprinkler.schedule.enabled" })
        #expect(apply.isEnabled, "the fixture program has days and a start time")
        #expect(await driver.press(apply))
        let call = await lastCall(driver, "bhyve.update_program")
        #expect(call.hasPrefix("Last call: bhyve.update_program"), "\(call)")
    }
}
#endif
