import Foundation
@testable import HassCore
@testable import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// Hosted renders of the Media, Custom Lights and Sprinklers pages and their sheets on phone and tablet sizes,
/// at AX5 and with nothing loaded, plus the views' pure helpers and the gallery recorder's echoes.
@MainActor
struct HomePagesViewTests {
    static let phone = CGSize(width: 402, height: 874)
    static let tablet = CGSize(width: 1210, height: 834)

    func render(_ view: some View, size: CGSize = Self.phone, typeSize: DynamicTypeSize = .large) -> CGImage? {
        let renderer = ImageRenderer(content: NavigationStack { view }
            .dynamicTypeSize(typeSize)
            .frame(width: size.width, height: size.height))
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.cgImage
    }

    func store(_ states: [EntityState] = HomePageFixtures.states) -> EntityStore {
        let store = EntityStore()
        store.replaceAll(states)
        return store
    }

    // MARK: Pages

    @Test func pagesRenderOnEverySizeAndAtAX5() {
        for size in [Self.phone, Self.tablet] {
            for typeSize in [DynamicTypeSize.large, .accessibility5] {
                let store = store()
                #expect(render(MediaScreen(store: store, caller: NullCaller()), size: size, typeSize: typeSize) != nil)
                #expect(render(CustomLightsScreen(store: store, caller: NullCaller()), size: size, typeSize: typeSize) != nil)
                #expect(render(SprinklersScreen(store: store, caller: NullCaller()), size: size, typeSize: typeSize) != nil)
            }
        }
    }

    @Test func pagesRenderWithNothingLoaded() {
        let empty = store([])
        #expect(render(MediaScreen(store: empty, caller: NullCaller())) != nil)
        #expect(render(CustomLightsScreen(store: empty, caller: NullCaller())) != nil)
        #expect(render(SprinklersScreen(store: empty, caller: NullCaller())) != nil)
    }

    @Test func sheetsRender() {
        let store = store()
        let controllers = SprinklersConfig.controllers.map { SprinklerController(config: $0, store: store, caller: NullCaller()) }
        for controller in controllers {
            #expect(render(SprinklerControllerSheet(controller: controller)) != nil)
            for zone in controller.config.zones.indices {
                #expect(render(SprinklerWaterPage(controller: controller, zone: zone) {}) != nil)
                #expect(render(SprinklerSchedulePage(controller: controller, zone: zone) {}, typeSize: .accessibility5) != nil)
            }
        }
        for light in CustomLightsConfig.lights {
            #expect(render(CustomLightSheet(light: light, store: store, caller: NullCaller())) != nil)
        }
        #expect(render(CustomLightSheet(light: CustomLightsConfig.lights[0], store: self.store([]), caller: NullCaller())) != nil)
        let options = CustomLightsConfig.fallbackModes.map { OptionPickerSheet.Option(value: $0, swatch: [.red, .blue]) }
        #expect(render(OptionPickerSheet(title: "Lighting Mode", options: options, selected: "Custom") { _ in }) != nil)
        #expect(render(GradientSwatch(colors: [])) != nil)
        #expect(StatusPill.accessibilityValue(value: "Ready", detail: "20 min") == "Ready, 20 min")
        #expect(StatusPill.accessibilityValue(value: "Ready", detail: nil) == "Ready")
    }

    @Test func galleryPagesRender() {
        for page in [ComponentGallery.Page.mediaPage, .customLights, .sprinklers] {
            #expect(render(ComponentGallery(page: page)) != nil, "\(page)")
        }
        #expect(ComponentGallery.Page(rawValue: "media-page") == .mediaPage)
        #expect(HomePageGallery.detail("water-1") == .water(zone: 1))
        #expect(HomePageGallery.detail("schedule-0") == .schedule(zone: 0))
        #expect(HomePageGallery.detail("other-0") == nil && HomePageGallery.detail("water") == nil)
    }

    // MARK: Helpers

    @Test func mediaTileLook() {
        let living = MediaPageConfig.cards[0]
        let off = MediaRemoteController.DeviceDisplay(state: "off", subtitle: "Off", isActive: false, isUnavailable: false,
                                                      isDisabled: false, semantics: .state)
        #expect(MediaCardTile.look(living, display: off).symbol == SymbolMap.symbol(for: "mdi:television-off"))
        var on = off
        on.state = "playing"
        on.semantics = .toggle(isOn: true)
        #expect(MediaCardTile.look(living, display: on).symbol == SymbolMap.symbol(for: "mdi:television"))
        #expect(MediaCardTile.look(living, display: on).kind == .toggle)
        on.semantics = .selection(isSelected: true)
        #expect(MediaCardTile.look(living, display: on).kind == .toggle)
        on.semantics = .command
        #expect(MediaCardTile.look(living, display: on).kind == .command)
        #expect(MediaCardTile.slug("Living Room SHIELD") == "living-room-shield")
        #expect(MediaCardTile.slug("Windows PC") == "windows-pc")
    }

    @Test func quickLinksHideSprinklersUntilFaucetsShow() {
        let store = store([])
        #expect(HomeRoute.allCases.filter { $0.link.isVisible(store) } == [.media, .customLights])
        store.apply([EntityState(entityId: SprinklersConfig.visibilityEntityId, state: "on")])
        #expect(HomeRoute.allCases.filter { $0.link.isVisible(store) } == [.media, .customLights, .sprinklers])
        #expect(HomeRoute.allCases.map(\.link.title) == ["Media", "Custom Lights", "Sprinklers"])
    }

    @Test func brightnessTileHints() {
        #expect(BrightnessTile.hint(percent: 0, isUnavailable: false, opensDetails: false) == "Double-tap to turn on. Swipe up or down to adjust brightness.")
        #expect(BrightnessTile.hint(percent: 40, isUnavailable: false, opensDetails: true) == "Double-tap for details. Swipe up or down to adjust brightness.")
        #expect(BrightnessTile.hint(percent: 40, isUnavailable: true, opensDetails: true).isEmpty)
    }

    @Test func pickedColorsConvertToRGB() {
        #expect(CustomLightsConfig.RGB(color: Color(red: 1, green: 0, blue: 0)) == CustomLightsConfig.RGB(255, 0, 0))
        #expect(CustomLightsConfig.RGB(color: Color(rgb: .init(12, 200, 99))) == CustomLightsConfig.RGB(12, 200, 99))
    }

    @Test func controllerTone() {
        let store = store()
        let front = SprinklerSnapshot(config: SprinklersConfig.frontYard, store: store)
        #expect(SprinklerControllerSheet.tone(front) == .ok)
        let back = SprinklerSnapshot(config: SprinklersConfig.backyard, store: store)
        #expect(SprinklerControllerSheet.tone(back) == .active)
        #expect(SprinklerControllerSheet.tone(SprinklerSnapshot(config: SprinklersConfig.frontYard, store: self.store([]))) == .unavailable)
        #expect(StatusPill.color(.danger) == .red)
    }

    // MARK: Gallery recorder

    @Test func recorderEchoesPageCalls() async throws {
        let store = store()
        let recorder = PageGalleryRecorder(store: store)
        let light = CustomLightsConfig.lights[0].entityId
        try await recorder.call(CustomLightsConfig.setManualControl(on: false))
        #expect(store.value(CustomLightsConfig.manualControlEntityId)?.state == "off")
        #expect(recorder.lastCall == "input_boolean.turn_off entity_id=\(CustomLightsConfig.manualControlEntityId)")
        try await recorder.call(CustomLightsConfig.selectMode("Seahawks"))
        #expect(store.value(CustomLightsConfig.modeEntityId)?.state == "Seahawks")
        try await recorder.call(CustomLightsConfig.setColor(.init(1, 2, 3), on: light))
        #expect(CustomLightsConfig.RGB(entity: store.value(light)) == .init(1, 2, 3))
        try await recorder.callService("light", "turn_off", data: ["entity_id": light])
        #expect(store.value(light)?.state == "off")
        try await recorder.callService("light", "turn_on", data: ["entity_id": light, "brightness_pct": 50])
        #expect(LightControl.percent(of: store.value(light)) == 50)
        try await recorder.call(CustomLightsConfig.reset())
        #expect(CustomLightsConfig.lights.allSatisfy { store.value($0.entityId)?.state == "on" })

        let valve = SprinklersConfig.frontYard.zones[0].valveEntityId
        try await recorder.call(SprinklersConfig.startWatering(valve: valve, minutes: 5))
        #expect(store.value(valve)?.state == "open")
        try await recorder.call(SprinklersConfig.stopWatering(valve: valve))
        #expect(store.value(valve)?.state == "closed")
        let program = SprinklersConfig.frontYard.zones[0].programEntityId
        try await recorder.call(SprinklersConfig.updateProgram(program, days: [2], startTimes: ["08:00"], budget: 90))
        let updated = SprinklerSnapshot(config: SprinklersConfig.frontYard, store: store).zones[0].program
        #expect(updated.days == [2] && updated.startTimes == ["08:00"] && updated.budget == 90)
    }
}
