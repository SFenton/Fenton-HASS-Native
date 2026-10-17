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
        // Rain delay starts off and smart watering on: each press shows the new value at once and sends its service.
        #expect(await driver.press("sprinkler.rainDelay", until: value("sprinkler.rainDelay", "1")), "the switch shows the new value at once")
        let afterRain = await lastCall(driver, "switch.turn_on")
        #expect(afterRain.contains(Self.front.rainDelayEntityId), "\(afterRain)")
        #expect(await driver.press("sprinkler.smartWatering", until: value("sprinkler.smartWatering", "0")))
        let afterSmart = await lastCall(driver, "switch.turn_off")
        #expect(afterSmart.contains(Self.front.smartWateringEntityId), "\(afterSmart)")
    }

    @Test func aWateringControllerCanBeStopped() async throws {
        let driver = await open(Self.back)
        defer { driver.close() }
        let overview = await driver.wait { $0.contains { $0.identifier == "sprinkler.stop" } }
        #expect(overview.first { $0.identifier == "sprinkler.stop" }?.isEnabled == true)
        #expect(await driver.press("sprinkler.stop") { nodes in nodes.last { $0.identifier == "gallery.lastCall" }?.value.contains("bhyve.stop_watering") == true })
    }

    @Test func aWateringControllerOffersToStopAndBlocksStartingAnotherZone() async throws {
        let driver = await open(Self.back)
        defer { driver.close() }
        let overview = await driver.wait { $0.contains { $0.identifier == "sprinkler.stop" } }
        #expect(overview.first { $0.identifier == "sprinkler.stop" }?.isEnabled == true)
        #expect(overview.contains { $0.identifier == "sprinkler.zone.1" && $0.spoken.contains("Watering") }, "the running zone reads Watering")
        // Another zone can't start while this one waters: Water now explains why and its Start button is off.
        #expect(await driver.press("sprinkler.zone.0") { $0.contains { $0.identifier == "sprinkler.waterBlocked" } })
        let blocked = try #require(await driver.waitFor("sprinkler.waterBlocked"))
        #expect(blocked.value.contains("Another zone is watering"))
        #expect(await driver.node("sprinkler.startWatering")?.isEnabled == false)
    }

    @Test func waterNowStartsAZoneForTheChosenRunTime() async throws {
        let driver = await open()
        defer { driver.close() }
        #expect(await driver.press("sprinkler.zone.0") { $0.contains { $0.identifier == "sprinkler.startWatering" } })
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

    @Test func daysAndStartTimesAreEditedBeforeApplying() async throws {
        let driver = await open(detail: "schedule-0")
        defer { driver.close() }
        let nodes = await driver.wait { $0.contains { $0.identifier == "sprinkler.schedule.apply" } }
        let before = nodes.filter { $0.identifier.hasPrefix("sprinkler.schedule.day.") }.map(\.isSelected)
        #expect(before.count == 7)
        // A day button toggles its own selection.
        let day = "sprinkler.schedule.day.0"
        let wasSelected = nodes.first { $0.identifier == day }?.isSelected ?? false
        #expect(await driver.press(day) { $0.contains { $0.identifier == day && $0.isSelected != wasSelected } }, "pressing a day flips it")
        // A start time is added and removed again.
        #expect(await driver.press("sprinkler.schedule.addTime") { $0.contains { $0.identifier == "sprinkler.schedule.time.1" } }, "Add Another Start Time adds a row")
        let remove = try #require(await driver.node(label: "Remove Start Time 2"))
        #expect(await driver.press(remove))
        let removed = await driver.wait { !$0.contains { $0.identifier == "sprinkler.schedule.time.1" } }
        #expect(!removed.contains { $0.identifier == "sprinkler.schedule.time.1" }, "Remove drops it")
    }
}

/// A service caller whose every call fails, so the pages show what a failed command looks like.
@MainActor
final class FailingCaller: HassServiceCalling {
    struct Refused: LocalizedError { var errorDescription: String? { "Home Assistant refused the command." } }
    private(set) var attempts = 0
    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        attempts += 1
        throw Refused()
    }
}

/// The sprinkler sheet's pages when Home Assistant refuses every command: each shows its message and goes on working.
@MainActor
@Suite(.serialized, .enabled(if: AXWindow.isAvailable, "Needs accessibility permission for the test host"))
struct SprinklerFailureFlowTests {
    static let phone = CGSize(width: 402, height: 874)

    func open(detail: SprinklerDetail?, caller: FailingCaller) -> AXWindow {
        let store = EntityStore()
        store.replaceAll(HomePageFixtures.states, freshness: .live)
        let controller = SprinklerController(config: SprinklersConfig.frontYard, store: store, caller: caller)
        return AXWindow(SprinklerControllerSheet(controller: controller, initialDetail: detail), size: Self.phone)
    }

    static func refusal(_ nodes: [AXWindow.Node]) -> Bool {
        nodes.contains { $0.spoken.contains("refused") || $0.value.contains("refused") }
    }

    @Test func theOverviewShowsTheMessageWhenASwitchIsRefused() async throws {
        let caller = FailingCaller()
        let driver = open(detail: nil, caller: caller)
        defer { driver.close() }
        _ = await driver.waitFor("sprinkler.smartWatering")
        #expect(await driver.press("sprinkler.smartWatering") { _ in caller.attempts > 0 })
        #expect(Self.refusal(await driver.wait(Self.refusal)), "the refusal is shown")
    }

    @Test func waterNowShowsTheMessageWhenStartingIsRefused() async throws {
        let caller = FailingCaller()
        let driver = open(detail: .water(zone: 0), caller: caller)
        defer { driver.close() }
        _ = await driver.waitFor("sprinkler.startWatering")
        #expect(await driver.press("sprinkler.startWatering") { _ in caller.attempts > 0 })
        #expect(Self.refusal(await driver.wait(Self.refusal)), "the refusal is shown")
    }

    @Test func theScheduleShowsTheMessageWhenApplyingIsRefused() async throws {
        let caller = FailingCaller()
        let driver = open(detail: .schedule(zone: 0), caller: caller)
        defer { driver.close() }
        _ = await driver.waitFor("sprinkler.schedule.apply")
        let outcomes = await driver.pressEach(prefixes: ["sprinkler.schedule."], skipping: { $0.contains("apply") || $0.contains("addTime") })
        #expect(!outcomes.isEmpty, "days and switches can be pressed: \(outcomes)")
        #expect(await driver.press("sprinkler.schedule.apply") { _ in caller.attempts > 0 })
        #expect(Self.refusal(await driver.wait(Self.refusal)), "the refusal is shown")
    }
}
#endif
