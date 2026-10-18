#if os(macOS)
import AppKit
import Foundation
import FentonActivityModel
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// Launches each gallery the way the journeys do, with every `FENTON_GALLERY_*` switch that opens a sheet, a tab or a
/// state, and checks the page drew and (where a switch opens a sheet) that the sheet is up.
@MainActor
@Suite(.serialized)
struct GalleryLaunchMatrixTests {
    static let phone = CGSize(width: 402, height: 874)
    static let tablet = CGSize(width: 1210, height: 834)

    struct Launch: Sendable, CustomStringConvertible {
        var page: ComponentGallery.Page
        var environment: [String: String] = [:]
        var opensSheet = false
        var size = CGSize(width: 402, height: 874)
        var description: String { "\(page) \(environment.sorted { $0.key < $1.key }.map { "\($0.key.dropFirst("FENTON_GALLERY_".count))=\($0.value)" }.joined(separator: " "))" }
    }

    /// Hosts `launch` and checks what it drew.
    func run(_ launches: [Launch]) async {
        for launch in launches {
            let hosted = await withLaunch(environment: launch.environment) { () -> HostedWindow in
                let hosted = HostedWindow(ComponentGallery(page: launch.page), size: launch.size)
                await hosted.settle(launch.opensSheet ? 0.6 : 0.3)
                // A list builds only the rows in view: scroll to the end so the ones below the fold run too.
                await hosted.scrollThrough()
                return hosted
            }
            defer { hosted.close() }
            let image = hosted.snapshot()
            #expect((image?.distinctColors ?? 0) > 3, "\(launch) drew a blank window")
            if launch.opensSheet {
                #expect(hosted.window.attachedSheet != nil || !hosted.window.sheets.isEmpty, "\(launch) did not open its sheet")
            }
        }
    }

    func env(_ pairs: KeyValuePairs<String, String>) -> [String: String] {
        Dictionary(uniqueKeysWithValues: pairs.map { ($0.key, $0.value) })
    }

    @Test func bedroomOpensEachSheetTabAndScenario() async {
        var launches: [Launch] = []
        for scenario in BedroomFixtures.Scenario.allCases {
            launches.append(Launch(page: .bedroom, environment: ["FENTON_GALLERY_SCENARIO": scenario.rawValue]))
            launches.append(Launch(page: .bedroom, environment: ["FENTON_GALLERY_SCENARIO": scenario.rawValue,
                                                                "FENTON_GALLERY_SHEET": "wake-light"], opensSheet: true))
            for bed in ["stephens-bed", "stephs-bed"] {
                launches.append(Launch(page: .bedroom, environment: ["FENTON_GALLERY_SCENARIO": scenario.rawValue,
                                                                    "FENTON_GALLERY_SHEET": bed], opensSheet: true))
            }
        }
        for tab in WakeLightSheet.Tab.allCases {
            launches.append(Launch(page: .bedroom, environment: ["FENTON_GALLERY_SHEET": "wake-light", "FENTON_GALLERY_TAB": tab.rawValue],
                                   opensSheet: true))
        }
        for tab in BedSideSheet.Tab.allCases {
            for bed in ["stephens-bed", "stephs-bed"] {
                launches.append(Launch(page: .bedroom, environment: ["FENTON_GALLERY_SHEET": bed, "FENTON_GALLERY_TAB": tab.rawValue],
                                       opensSheet: true))
            }
        }
        launches.append(Launch(page: .bedroom, environment: ["FENTON_GALLERY_SHEET": "wake-light"], opensSheet: true, size: Self.tablet))
        launches.append(Launch(page: .bedroom, environment: ["FENTON_GALLERY_SHEET": "stephens-bed"], opensSheet: true, size: Self.tablet))
        await run(launches)
    }

    @Test func liveActivityGalleryDrawsEachFixtureGroupAndTheIslandWidths() async {
        var launches = HomeActivityFixtures.groups.keys.sorted().map {
            Launch(page: .liveActivity, environment: ["FENTON_GALLERY_SCENARIO": $0])
        }
        launches += ["fan", "vacuum-paused", "problem-navigation-stuck", "island-widths", "nothing-at-all"].map {
            Launch(page: .liveActivity, environment: ["FENTON_GALLERY_SCENARIO": $0])
        }
        launches.append(Launch(page: .liveActivity, environment: ["FENTON_GALLERY_SCENARIO": "stack"], size: Self.tablet))
        await run(launches)
    }

    @Test func mediaRemotesOpenOnEveryTab() async {
        var launches: [Launch] = []
        for remote in MediaRemotes.all {
            for tab in MediaRemoteTab.allCases {
                launches.append(Launch(page: .mediaRemote, environment: ["FENTON_GALLERY_REMOTE": remote.id, "FENTON_GALLERY_TAB": tab.rawValue],
                                       opensSheet: true))
            }
            launches.append(Launch(page: .mediaPage, environment: ["FENTON_GALLERY_REMOTE": remote.id], opensSheet: true))
        }
        launches.append(Launch(page: .mediaRemote, environment: ["FENTON_GALLERY_OFFLINE": "1"]))
        await run(launches)
    }

    @Test func roomDevicesOpenEachFixtureAndHumidifierTab() async {
        var launches: [Launch] = []
        for fixture in RoomDeviceFixture.all() {
            launches.append(Launch(page: .roomDevices, environment: ["FENTON_GALLERY_DEVICE": fixture.id], opensSheet: true))
            launches.append(Launch(page: .roomDevices, environment: ["FENTON_GALLERY_DEVICE": fixture.id], opensSheet: true, size: Self.tablet))
        }
        for tab in HumidifierTab.allCases {
            launches.append(Launch(page: .roomDevices, environment: ["FENTON_GALLERY_DEVICE": "humidifier", "FENTON_GALLERY_TAB": tab.rawValue],
                                   opensSheet: true))
            launches.append(Launch(page: .roomDevices, environment: ["FENTON_GALLERY_DEVICE": "humidifier-fault", "FENTON_GALLERY_TAB": tab.rawValue],
                                   opensSheet: true))
        }
        await run(launches)
    }

    @Test func vacuumsOpenEveryScenarioVacuumAndTab() async {
        var launches: [Launch] = []
        for scenario in ["docked", "cleaning", "error", "resumable", "unavailable"] {
            launches.append(Launch(page: .vacuums, environment: ["FENTON_GALLERY_SCENARIO": scenario]))
            for vacuum in Vacuums.all {
                launches.append(Launch(page: .vacuums, environment: ["FENTON_GALLERY_SCENARIO": scenario,
                                                                    "FENTON_GALLERY_VACUUM": vacuum.vacuumMapId], opensSheet: true))
            }
        }
        for tab in VacuumTab.allCases {
            launches.append(Launch(page: .vacuums, environment: ["FENTON_GALLERY_SCENARIO": "cleaning", "FENTON_GALLERY_TAB": tab.rawValue,
                                                                "FENTON_GALLERY_VACUUM": Vacuums.all[0].vacuumMapId], opensSheet: true))
        }
        await run(launches)
    }

    @Test func securityClimateAndWeatherLaunchEveryState() async {
        var launches: [Launch] = []
        for scenario in ["standard", "unavailable", "triggered", "openHome", "openAway", "openArmed"] {
            launches.append(Launch(page: .security, environment: ["FENTON_GALLERY_SCENARIO": scenario]))
        }
        launches.append(Launch(page: .security, environment: ["FENTON_GALLERY_FAIL": "1"]))
        for scenario in ["home", "away"] {
            launches.append(Launch(page: .climate, environment: ["FENTON_GALLERY_CLIMATE_SCENARIO": scenario]))
        }
        for tab in ClimateConfig.Tab.allCases {
            launches.append(Launch(page: .climate, environment: ["FENTON_GALLERY_CLIMATE_OPEN": tab.rawValue], opensSheet: true))
        }
        for state in ["loading", "error", "empty"] {
            launches.append(Launch(page: .weather, environment: ["FENTON_GALLERY_WEATHER_STATE": state]))
        }
        for condition in ["sunny", "clear-night", "snowy", "lightning-rainy", "fog"] {
            launches.append(Launch(page: .weather, environment: ["FENTON_GALLERY_WEATHER_CONDITION": condition, "FENTON_GALLERY_WEATHER_NIGHT": "1",
                                                                "FENTON_GALLERY_WEATHER_NOAQI": "1"]))
        }
        launches.append(Launch(page: .weather, environment: ["FENTON_GALLERY_WEATHER_OPEN": "1"], opensSheet: true))
        await run(launches)
    }

    @Test func householdInventoryFoodAndLocationLaunchEveryState() async {
        var launches: [Launch] = []
        for page in HouseholdSettingsPage.allCases {
            launches.append(Launch(page: .householdSettings, environment: ["FENTON_GALLERY_HOUSEHOLD": page.rawValue]))
            launches.append(Launch(page: .householdSettings, environment: ["FENTON_GALLERY_HOUSEHOLD": page.rawValue, "FENTON_GALLERY_UNAVAILABLE": "1"]))
        }
        for state in ["empty", "error", "loading"] {
            launches.append(Launch(page: .inventory, environment: ["FENTON_GALLERY_STATE": state]))
        }
        for space in InventorySpace.allCases {
            launches.append(Launch(page: .inventory, environment: ["FENTON_GALLERY_SPACE": space.rawValue]))
        }
        launches.append(Launch(page: .inventory, environment: ["FENTON_GALLERY_HOLD_ADDED": "1"]))
        for mode in ["normal", "error", "empty", "slow"] {
            launches.append(Launch(page: .food, environment: ["FENTON_GALLERY_FOOD_MODE": mode, "FENTON_GALLERY_ROUTE": "recipes"]))
        }
        launches.append(Launch(page: .food, environment: ["FENTON_GALLERY_ROUTE": "none"]))
        launches.append(Launch(page: .food, environment: ["FENTON_GALLERY_FOOD_TABS": "1"]))
        for stage in LocationPermission.Stage.allCases {
            launches.append(Launch(page: .location, environment: ["FENTON_GALLERY_LOCATION": stage.rawValue], opensSheet: true))
        }
        launches.append(Launch(page: .location, environment: ["FENTON_GALLERY_LOCATION": LocationGallery.askedStage], opensSheet: true))
        await run(launches)
    }

    @Test func roomsChoresAndHomePagesLaunchEveryRoomListAndController() async {
        var launches: [Launch] = []
        for page in RoomsConfig.pages {
            launches.append(Launch(page: .rooms, environment: ["FENTON_GALLERY_ROOM": page.id]))
            launches.append(Launch(page: .rooms, environment: ["FENTON_GALLERY_ROOM": page.id], size: Self.tablet))
        }
        launches.append(Launch(page: .rooms, environment: ["FENTON_GALLERY_QUICK_LINKS": "1"], opensSheet: true))
        for page in ChoresConfig.pages {
            launches.append(Launch(page: .chores, environment: ["FENTON_GALLERY_TODO_PAGE": page.id]))
            launches.append(Launch(page: .chores, environment: ["FENTON_GALLERY_TODO_PAGE": page.id, "FENTON_GALLERY_EMPTY": "1"]))
        }
        for viewer in ChoresConfig.Resident.allCases {
            launches.append(Launch(page: .chores, environment: ["FENTON_GALLERY_VIEWER": viewer.rawValue, "FENTON_GALLERY_TODO_PAGE": "stephens-chores"]))
        }
        for light in CustomLightsConfig.lights {
            launches.append(Launch(page: .customLights, environment: ["FENTON_GALLERY_LIGHT": light.entityId], opensSheet: true))
        }
        launches.append(Launch(page: .customLights, environment: ["FENTON_GALLERY_PICKER": "1"], opensSheet: true))
        for controller in SprinklersConfig.controllers {
            launches.append(Launch(page: .sprinklers, environment: ["FENTON_GALLERY_SPRINKLER": controller.id], opensSheet: true))
            for zone in controller.zones.indices {
                for detail in ["water", "schedule"] {
                    launches.append(Launch(page: .sprinklers, environment: ["FENTON_GALLERY_SPRINKLER": controller.id,
                                                                           "FENTON_GALLERY_DETAIL": "\(detail)-\(zone)"], opensSheet: true))
                }
            }
        }
        await run(launches)
    }

    /// Your Summary opens on every tab for each viewer, in Vacation Mode and empty, on a phone and a tablet.
    @Test func yourSummaryOpensOnEveryTabViewerAndState() async {
        var launches: [Launch] = []
        for tab in SummaryTab.allCases {
            for viewer in ["stephen", "steph", "guest"] {
                launches.append(Launch(page: .profile, environment: ["FENTON_GALLERY_TAB": tab.rawValue, "FENTON_GALLERY_VIEWER": viewer], opensSheet: true))
            }
            for extra in [["FENTON_GALLERY_VACATION": "1"], ["FENTON_GALLERY_EMPTY": "1"], ["FENTON_GALLERY_VACATION": "1", "FENTON_GALLERY_EMPTY": "1"]] {
                launches.append(Launch(page: .profile, environment: extra.merging(["FENTON_GALLERY_TAB": tab.rawValue]) { a, _ in a }, opensSheet: true))
            }
            launches.append(Launch(page: .profile, environment: ["FENTON_GALLERY_TAB": tab.rawValue, "FENTON_GALLERY_CHORES": "12"],
                                   opensSheet: true, size: Self.tablet))
        }
        launches.append(Launch(page: .profile, environment: ["FENTON_GALLERY_CLEAN": "1"], opensSheet: true))
        await run(launches)
    }
}
#endif
