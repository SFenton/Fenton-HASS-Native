import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// Hosted renders of the Climate page, its sheet tabs and every detail page, in both fixture scenarios and at
/// accessibility text sizes, plus the page's routing and fan-out rules.
@MainActor
struct ClimateViewTests {
    static let phone = CGSize(width: 402, height: 874)
    static let tablet = CGSize(width: 1210, height: 834)

    func controller(_ scenario: ClimateFixtures.Scenario = .home, states: [EntityState]? = nil) -> ClimateController {
        let store = EntityStore()
        store.replaceAll(states ?? ClimateFixtures.states(scenario))
        return ClimateController(store: store, caller: RecordingCaller())
    }

    func render(_ view: some View, controller: ClimateController, size: CGSize = phone, typeSize: DynamicTypeSize = .large) -> CGImage? {
        let content = view
            .environment(controller.store)
            .dynamicTypeSize(typeSize)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.cgImage
    }

    // MARK: Page

    @Test(arguments: [ClimateFixtures.Scenario.home, .away])
    func pageRendersInEveryScenarioAndSize(scenario: ClimateFixtures.Scenario) {
        let climate = controller(scenario)
        for size in [Self.phone, Self.tablet] {
            #expect(render(NavigationStack { ClimatePage(controller: climate) }, controller: climate, size: size) != nil)
        }
        #expect(render(ClimatePage(controller: climate), controller: climate, typeSize: .accessibility5) != nil)
    }

    @Test func pageRendersWithNothingLoaded() {
        let climate = controller(states: [])
        #expect(render(ClimatePage(controller: climate), controller: climate) != nil)
        #expect(render(ClimateHubList(controller: climate), controller: climate) != nil)
    }

    @Test func galleryRenders() {
        let renderer = ImageRenderer(content: ComponentGallery(page: .climate).frame(width: 402, height: 874))
        #expect(renderer.cgImage != nil)
    }

    // MARK: Sheet

    @Test(arguments: ClimateConfig.Tab.allCases)
    func everySheetTabRenders(tab: ClimateConfig.Tab) {
        for scenario in [ClimateFixtures.Scenario.home, .away] {
            let climate = controller(scenario)
            #expect(render(ClimateSheet(controller: climate, request: .init(tab: tab)), controller: climate) != nil)
            #expect(render(ClimateSheet(controller: climate, request: .init(tab: tab)), controller: climate, typeSize: .accessibility5) != nil)
        }
    }

    @Test func everyDetailRenders() {
        for scenario in [ClimateFixtures.Scenario.home, .away] {
            let climate = controller(scenario)
            var routes: [ClimateRoute] = ClimateConfig.rooms.map { .room($0.key) } + [.predictive, .room("attic")]
            routes += ClimateConfig.EcoOption.allCases.map(ClimateRoute.eco) + ClimateConfig.TrackingPage.allCases.map(ClimateRoute.tracking)
            for route in routes {
                #expect(render(ClimateSheet(controller: climate, request: .init(tab: route.tab, route: route)), controller: climate) != nil)
            }
            #expect(render(VStack { PredictiveComfortDetail(controller: climate) }, controller: climate, typeSize: .accessibility5) != nil)
            for page in ClimateConfig.TrackingPage.allCases {
                #expect(render(VStack { TrackingRoomsDetail(controller: climate, page: page) }, controller: climate) != nil)
            }
            for option in ClimateConfig.EcoOption.allCases {
                #expect(render(VStack { EcoOptionDetail(controller: climate, option: option) }, controller: climate) != nil)
            }
            #expect(render(VStack { ClimateRoomDetail(controller: climate, room: ClimateConfig.rooms[0]) }, controller: climate) != nil)
        }
    }

    @Test func emptySelectShowsTheUnavailableNotice() {
        let climate = controller(states: [EntityState(entityId: ClimateConfig.ecoCriticalEntityId, state: "unknown")])
        #expect(render(VStack { EcoOptionDetail(controller: climate, option: .critical) }, controller: climate) != nil)
        #expect(render(NavigationStack { ClimateAutomationTab(controller: climate) }, controller: climate) != nil)
    }

    @Test func hubPickersRenderEnabledAndEmpty() {
        let climate = controller()
        let hub = climate.entity(ClimateConfig.hubEntityId)
        let menu = HubPicker(label: "Thermostat Hub Mode", value: "Heat", options: ClimateLogic.hvacModeOptions(hub),
                             selected: "heat") { _ in }
        #expect(render(menu, controller: climate) != nil)
        #expect(render(menu, controller: climate, typeSize: .accessibility5) != nil)
        #expect(render(HubPicker(label: "Mode", value: "Heat", options: [], selected: nil) { _ in }, controller: climate) != nil)
    }

    // MARK: Rules

    @Test func wholeHomeFansRangesOutFromTheGlobalThermostatOnly() {
        let global = ClimateConfig.globalThermostatEntityId
        #expect(ClimatePage.wholeHomeCommitIds(dialEntityId: global, targets: .range(low: 70, high: 75)) == ClimateConfig.roomClimateEntityIds)
        #expect(ClimatePage.wholeHomeCommitIds(dialEntityId: global, targets: .single(72)) == [global])
        let away = ClimateConfig.ecoAwayThermostatEntityId
        #expect(ClimatePage.wholeHomeCommitIds(dialEntityId: away, targets: .range(low: 62, high: 78)) == [away])
    }

    /// A bound dial with a caller commits there (the gallery and the Climate controller's recorder).
    @Test func boundDialCommitsThroughItsCaller() async {
        let caller = RecordingCaller()
        let dial = ClimateThermostatDial(entityId: "climate.office", title: "Office", action: "heating", caller: caller)
        await dial.commit(.single(71))?.value
        #expect(caller.names == ["climate.set_temperature"])
        let climate = controller()
        #expect(render(dial, controller: climate) != nil)
    }

    /// A rejected commit is not swallowed: the dial's task runs the rollback path.
    @Test func boundDialSurvivesARejectedCommit() async {
        final class Rejecting: HassServiceCalling {
            var attempts = 0
            func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
                attempts += 1
                throw URLError(.badServerResponse)
            }
        }
        let caller = Rejecting()
        let dial = ClimateThermostatDial(entityId: "climate.office", title: "Office", caller: caller)
        await dial.commit(.single(71))?.value
        #expect(caller.attempts == 1)
    }

    @Test func routeTokensAndTitles() {
        #expect(ClimateRoute(token: "room:living_room") == .room("living_room"))
        #expect(ClimateRoute(token: "room:attic") == nil)
        #expect(ClimateRoute(token: "predictive") == .predictive)
        #expect(ClimateRoute(token: "eco-away") == .eco(.away))
        #expect(ClimateRoute(token: "occupied-only") == .tracking(.occupiedOnly))
        #expect(ClimateRoute(token: "nope") == nil)
        #expect(ClimateRoute.room("office").title == "Office")
        #expect(ClimateRoute.room("attic").title == "Room")
        #expect(ClimateRoute.predictive.title == "Predictive Comfort")
        #expect(ClimateRoute.eco(.critical).title == "Eco Mode Critical Tracking")
        #expect(ClimateRoute.tracking(.selectedRooms).title == "Selected Rooms")
        #expect([ClimateRoute.room("x"), .predictive, .eco(.away), .tracking(.occupiedOnly)].map(\.tab) == [.rooms, .automation, .automation, .tracking])
        #expect(ClimateGallery.request(token: "tracking") == ClimateSheetRequest(tab: .tracking))
        #expect(ClimateGallery.request(token: "predictive") == ClimateSheetRequest(tab: .automation, route: .predictive))
        #expect(ClimateGallery.request(token: "bogus") == nil)
        #expect(ClimateSheetRequest(tab: .rooms).id != ClimateSheetRequest(tab: .rooms, route: .room("office")).id)
    }

    @Test func styleTintsFollowTheAction() {
        #expect(ClimateStyle.tint(action: "heating") == ClimateStyle.heat)
        #expect(ClimateStyle.tint(action: "cool") == ClimateStyle.cool)
        #expect(ClimateStyle.tint(action: "idle") == nil)
        #expect(ClimateStyle.symbol("mdi:leaf") == "leaf")
    }

    /// The gallery recorder echoes the climate services the page sends, so journeys see state change.
    @Test func galleryRecorderEchoesClimateServices() async throws {
        let store = ClimateFixtures.store()
        let recorder = GalleryServiceRecorder(store: store)
        let eco = ClimateConfig.ecoModeEntityId
        try await recorder.callService("homeassistant", "toggle", data: ["entity_id": eco])
        #expect(store.value(eco)?.state == "off")
        let hub = ClimateConfig.hubEntityId
        try await recorder.callService("climate", "set_hvac_mode", data: ["entity_id": hub, "hvac_mode": "cool"])
        try await recorder.callService("climate", "set_fan_mode", data: ["entity_id": hub, "fan_mode": "on"])
        #expect(store.value(hub)?.state == "cool")
        #expect(store.value(hub)?.attributes["fan_mode"] == .string("on"))
        let rooms = Array(ClimateConfig.roomClimateEntityIds.prefix(2))
        try await recorder.callService("climate", "set_temperature", data: ["entity_id": rooms, "target_temp_low": 69.0, "target_temp_high": 76.0])
        #expect(store.value(rooms[1])?.attributes["target_temp_high"] == .number(76))
        try await recorder.callService("climate", "set_temperature", data: ["entity_id": "climate.missing", "temperature": 70.0])
        #expect(recorder.lastCall.hasPrefix("climate.set_temperature"))
    }
}
