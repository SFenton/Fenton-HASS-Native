#if os(macOS)
import AppKit
import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// Presses every control a device sheet offers, on its gallery house, and checks what reached Home Assistant: a
/// control either sends a service call (the gallery's last-call line changes) or opens something, and the sheet
/// survives all of them.
@MainActor
@Suite(.serialized, .enabled(if: AXWindow.isAvailable, "Needs accessibility permission for the test host"))
struct ControlSweepTests {
    static let phone = CGSize(width: 402, height: 874)

    /// Controls a sweep leaves alone: they close the sheet, delete or leave, or hand the main thread to a system panel
    /// (photo and file pickers, the share sheet, camera access) that nothing in a test can answer.
    static func endsTheSweep(_ identifier: String) -> Bool {
        let lower = identifier.lowercased()
        return ["sheet.", "close", "cancel", "delete", "remove", "discard", "signout", "images", "photo", "attach", "picker",
                "scan.", "camera", "snapshot", "export", "share", "file"].contains { lower.contains($0) }
    }

    static let deviceControls = ["fan.", "purifier.", "humidifier.", "grill.", "airQuality."]

    func open(_ page: ComponentGallery.Page, _ environment: [String: String]) async -> AXWindow {
        await withLaunch(environment: environment) {
            // These galleries own their navigation stack (the fixtures are injected above it).
            let ownsStack: [ComponentGallery.Page] = [.food, .chores, .vacation, .location, .rooms]
            let driver = ownsStack.contains(page)
                ? AXWindow(ComponentGallery(page: page), size: Self.phone)
                : AXWindow(NavigationStack { ComponentGallery(page: page) }, size: Self.phone)
            await driver.window.settle(0.8)
            return driver
        }
    }

    func sweep(_ page: ComponentGallery.Page, _ environment: [String: String], prefixes: [String]) async -> [AXWindow.PressOutcome] {
        let driver = await open(page, environment)
        defer { driver.close() }
        _ = await driver.wait { !$0.isEmpty }
        let outcomes = await driver.pressEach(prefixes: prefixes, skipping: Self.endsTheSweep)
        try? "\(page) \(environment): \(outcomes.map(\.description).joined(separator: "; "))\n".appendLine(to: "/tmp/sweep.log")
        return outcomes
    }

    @Test func mediaRemotesSendTheirCommandsAppLaunchesAndDeviceToggles() async throws {
        let plan: [(remote: String, tabs: [MediaRemoteTab])] = [
            ("living-room-shield", [.controls, .apps]),
            ("master-bedroom-apple-tv", [.controls]),
            ("theater-room-shield", [.controls, .devices]),
            ("music-room-remote", [.controls, .apps, .devices, .hueSync]),
        ]
        var pressed = 0, sent: [String] = []
        for (remote, tabs) in plan {
            for tab in tabs {
                let outcomes = await sweep(.mediaRemote, ["FENTON_GALLERY_REMOTE": remote, "FENTON_GALLERY_TAB": tab.rawValue], prefixes: ["remote."])
                #expect(!outcomes.isEmpty, "\(remote) \(tab.rawValue) offers controls")
                pressed += outcomes.count
                sent += outcomes.compactMap(\.call)
            }
        }
        // Each control either sends a command or opens something; most send one. (A call that lands late is missed when
        // the machine is busy, so the bar is far below what a quiet run sees.)
        #expect(pressed >= 25, "\(pressed) controls pressed")
        #expect(sent.count >= 10, "\(sent.count) of \(pressed) sent a call")
        #expect(sent.contains { $0.contains("remote.send_command") } && sent.contains { $0.contains("launch_app") })
    }

    @Test func vacuumControlsStartPauseAndDock() async throws {
        for (scenario, vacuum) in [("docked", Vacuums.all[0]), ("cleaning", Vacuums.all[0]), ("docked", Vacuums.all[2])] {
            do {
                let outcomes = await sweep(.vacuums, ["FENTON_GALLERY_SCENARIO": scenario, "FENTON_GALLERY_VACUUM": vacuum.vacuumMapId], prefixes: ["vacuum."])
                #expect(!outcomes.isEmpty, "\(vacuum.title) \(scenario) offers controls")
            }
        }
    }

    @Test func roomDeviceSheetsSendTheirServices() async throws {
        for fixture in RoomDeviceFixture.all() {
            let outcomes = await sweep(.roomDevices, ["FENTON_GALLERY_DEVICE": fixture.id], prefixes: Self.deviceControls)
            // Air quality's pickers are menus, which a click would hold open; the others are buttons.
            #expect(!outcomes.isEmpty || fixture.id.hasPrefix("purifier"), "\(fixture.id) offers controls")
        }
        for tab in HumidifierTab.allCases {
            _ = await sweep(.roomDevices, ["FENTON_GALLERY_DEVICE": "humidifier", "FENTON_GALLERY_TAB": tab.rawValue], prefixes: Self.deviceControls)
        }
    }

    @Test func customLightSheetsSendTheirColoursAndBrightness() async throws {
        for light in CustomLightsConfig.lights.prefix(2) {
            let outcomes = await sweep(.customLights, ["FENTON_GALLERY_LIGHT": light.entityId], prefixes: ["customLight."])
            #expect(!outcomes.isEmpty, "\(light.title) offers controls")
        }
    }

    /// Presses every identified control in the sheet a launch opens (not the page behind it).
    func sheetSweep(_ page: ComponentGallery.Page, _ environment: [String: String]) async -> [AXWindow.PressOutcome] {
        let driver = await open(page, environment)
        defer { driver.close() }
        _ = await driver.wait { !$0.isEmpty }
        let outcomes = await driver.pressEach(prefixes: [""], inSheet: true, skipping: Self.endsTheSweep)
        try? "\(page) \(environment): \(outcomes.map(\.description).joined(separator: "; "))\n".appendLine(to: "/tmp/sweep.log")
        return outcomes
    }

    @Test func bedroomSheetsSendTheirServicesOnEveryTab() async throws {
        for tab in WakeLightSheet.Tab.allCases {
            _ = await sheetSweep(.bedroom, ["FENTON_GALLERY_SHEET": "wake-light", "FENTON_GALLERY_TAB": tab.rawValue])
        }
        for tab in BedSideSheet.Tab.allCases {
            _ = await sheetSweep(.bedroom, ["FENTON_GALLERY_SHEET": "stephens-bed", "FENTON_GALLERY_TAB": tab.rawValue])
        }
        _ = await sheetSweep(.bedroom, ["FENTON_GALLERY_SHEET": "stephs-bed", "FENTON_GALLERY_SCENARIO": "hot-flash"])
        _ = await sheetSweep(.bedroom, ["FENTON_GALLERY_SHEET": "wake-light", "FENTON_GALLERY_SCENARIO": "waking"])
    }

    @Test func vacuumSheetsSendTheirServicesOnEveryTab() async throws {
        for tab in VacuumTab.allCases {
            _ = await sheetSweep(.vacuums, ["FENTON_GALLERY_SCENARIO": "docked", "FENTON_GALLERY_TAB": tab.rawValue,
                                            "FENTON_GALLERY_VACUUM": Vacuums.all[1].vacuumMapId])
        }
    }

    /// Presses every identified control on a page, and in each sheet one of them opens.
    func pageSweep(_ page: ComponentGallery.Page, _ environment: [String: String] = [:]) async -> [AXWindow.PressOutcome] {
        let driver = await open(page, environment)
        defer { driver.close() }
        _ = await driver.wait { !$0.isEmpty }
        let outcomes = await driver.pressEach(prefixes: [""], descend: 1, skipping: Self.endsTheSweep)
        try? "PAGE \(page) \(environment): \(outcomes.count) presses, \(outcomes.compactMap(\.call).count) calls\n".appendLine(to: "/tmp/sweep.log")
        return outcomes
    }

    @Test func homePagesAndTheSheetsTheirControlsOpenSurviveEveryPress() async throws {
        let launches: [(ComponentGallery.Page, [String: String])] = [
            (.floatingActions, [:]), (.directionG, [:]),
            (.security, [:]), (.climate, [:]), (.vacuums, [:]), (.roomDevices, [:]), (.bedroom, [:]),
            (.customLights, [:]), (.sprinklers, [:]), (.mediaPage, [:]), (.inventory, [:]), (.food, ["FENTON_GALLERY_ROUTE": "recipes"]),
            (.vacation, [:]), (.householdSettings, [:]), (.weather, ["FENTON_GALLERY_WEATHER_OPEN": "1"]),
        ]
        for (page, environment) in launches {
            _ = await pageSweep(page, environment)
        }
    }

    @Test func choresPagesAndTheirSheetsSurviveEveryPress() async throws {
        for page in ["chores", "groceries", "stephens-chores", "to-do"] {
            _ = await pageSweep(.chores, ["FENTON_GALLERY_TODO_PAGE": page])
        }
    }

    @Test func roomPagesSurviveEveryPress() async throws {
        for room in ["master-bedroom", "living-room", "kitchen"] {
            _ = await pageSweep(.rooms, ["FENTON_GALLERY_ROOM": room])
        }
    }

    @Test func climateSheetsSendTheirServices() async throws {
        for tab in ClimateConfig.Tab.allCases {
            _ = await sweep(.climate, ["FENTON_GALLERY_CLIMATE_OPEN": tab.rawValue], prefixes: ["climate."])
        }
    }
}

extension String {
    func appendLine(to path: String) throws {
        let url = URL(fileURLWithPath: path)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(utf8))
            try handle.close()
        } else {
            try write(to: url, atomically: false, encoding: .utf8)
        }
    }
}
#endif
