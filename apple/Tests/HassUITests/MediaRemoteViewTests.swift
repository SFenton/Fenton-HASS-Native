import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing
#if canImport(AppKit)
import AppKit
#endif

/// Records calls for hosted renders; nothing reaches a server.
@MainActor
final class NullCaller: HassServiceCalling {
    var calls: [String] = []
    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        calls.append("\(domain).\(service)")
    }
}

/// Hosted renders of the media remote on every remote, tab, layout and text size, plus its pure UI policies.
@MainActor
struct MediaRemoteViewTests {
    static let phone = CGSize(width: 402, height: 874)
    static let tabletLandscape = CGSize(width: 1210, height: 834)

    func render(_ config: MediaRemoteConfig, tab: MediaRemoteTab, size: CGSize, window: WindowMetrics? = nil,
                typeSize: DynamicTypeSize = .large, states: [EntityState] = MediaRemoteFixtures.states) -> CGImage? {
        let store = EntityStore()
        store.replaceAll(states)
        let controller = MediaRemoteController(config: config, store: store, caller: NullCaller())
        let view = MediaRemoteSheet(controller: controller, imageServer: nil, initialTab: tab, window: window)
            .dynamicTypeSize(typeSize)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.cgImage
    }

    @Test(arguments: MediaRemotes.all)
    func everyTabRendersInBothLayouts(config: MediaRemoteConfig) {
        for tab in config.tabs {
            #expect(render(config, tab: tab, size: Self.phone) != nil, "\(config.id) \(tab) phone")
            #expect(render(config, tab: tab, size: Self.tabletLandscape,
                           window: WindowMetrics(size: Self.tabletLandscape, isRegularWidth: true)) != nil, "\(config.id) \(tab) two columns")
        }
    }

    @Test func rendersAtAccessibilitySizesAndWithEverythingOff() {
        let off = MediaRemoteFixtures.states.map { EntityState(entityId: $0.entityId, state: "unavailable", attributes: $0.attributes) }
        for config in MediaRemotes.all {
            for tab in config.tabs {
                #expect(render(config, tab: tab, size: Self.phone, typeSize: .accessibility5) != nil)
                #expect(render(config, tab: tab, size: Self.phone, states: off) != nil)
            }
        }
        #expect(render(MediaRemotes.musicRoom, tab: .hueSync, size: Self.phone, states: []) != nil)
    }

    @Test func missingTabFallsBackToControls() {
        #expect(render(MediaRemotes.livingRoomShield, tab: .hueSync, size: Self.phone) != nil)
    }

    // MARK: Layout policy

    @Test func twoColumnsOnlyWhereSplitsAreAllowedAndTheSheetIsWide() {
        let wide = CGSize(width: 800, height: 700)
        // iPad landscape and unfolded Duo landscape: regular width, wider than tall.
        #expect(MediaRemoteLayout.usesTwoColumns(window: Self.tabletLandscape, isRegularWidth: true, container: wide))
        #expect(!MediaRemoteLayout.usesTwoColumns(window: Self.tabletLandscape, isRegularWidth: true, container: CGSize(width: 600, height: 700)),
                "A narrow sheet stays single")
        // iPad portrait, unfolded Duo portrait, folded Duo, iPhone.
        #expect(!MediaRemoteLayout.usesTwoColumns(window: CGSize(width: 834, height: 1210), isRegularWidth: true, container: wide))
        #expect(!MediaRemoteLayout.usesTwoColumns(window: CGSize(width: 874, height: 402), isRegularWidth: false, container: wide))
        #expect(!MediaRemoteLayout.usesTwoColumns(window: Self.phone, isRegularWidth: false, container: Self.phone))
    }

    /// The d-pad scales 64–104 pt with Dynamic Type but fits its column, never below 44 pt.
    @Test func dpadFitsItsColumn() {
        #expect(DirectionalPad.diameter(scaled: 76, maxWidth: nil) == 76)
        #expect(DirectionalPad.diameter(scaled: 200, maxWidth: nil) == 104)
        #expect(DirectionalPad.diameter(scaled: 30, maxWidth: nil) == 64)
        #expect(DirectionalPad.diameter(scaled: 104, maxWidth: 296) == 93.33333333333333)
        #expect(DirectionalPad.diameter(scaled: 104, maxWidth: 100) == 44)
    }

    // MARK: Symbols

    /// Every MDI icon the remotes use maps to an SF Symbol that exists.
    @Test func everyRemoteIconMapsToARealSymbol() {
        var icons: Set<String> = []
        for config in MediaRemotes.all {
            let buttons = config.directionalButtons + [config.power, config.back, config.home, config.pause, config.play,
                                                       config.volumeDown, config.volumeMute, config.volumeUp] + [config.keyboard].compactMap { $0 }
            icons.formUnion(buttons.filter(\.hasIcon).map(\.icon))
            icons.formUnion(config.devices.map(\.icon))
            icons.formUnion(config.apps.compactMap(\.icon))
        }
        icons.formUnion(["mdi:play-box", "mdi:music", "mdi:movie-open", "mdi:gamepad-variant", "mdi:lightbulb-multiple", "mdi:gauge",
                         "mdi:television", "mdi:television-off"])
        for icon in icons {
            let symbol = SymbolMap.symbol(for: icon)
            #expect(symbol != "circle", "\(icon) has no mapping")
            #if canImport(AppKit)
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(icon) → \(symbol) is not an SF Symbol")
            #endif
        }
        for symbol in ["power", "lightbulb.2", "gauge.with.dots.needle.50percent", "tv", "tv.slash"] {
            #if canImport(AppKit)
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol)")
            #endif
        }
    }

    // MARK: Gallery

    @Test func galleryRecorderDescribesAndEchoesCalls() async throws {
        let store = MediaRemoteFixtures.store()
        let recorder = GalleryServiceRecorder(store: store)
        try await recorder.callService("remote", "send_command", data: ["entity_id": "remote.living_room_shield", "command": "POWER"])
        #expect(recorder.lastCall == "remote.send_command command=POWER entity_id=remote.living_room_shield")
        #expect(store.value("media_player.living_room_shield_2")?.state == "off")
        try await recorder.callService("script", "toggle_sonos_mute", data: ["sonosdevice": ["media_player.sonos"] as [any Sendable]])
        #expect(recorder.lastCall == "script.toggle_sonos_mute sonosdevice=[media_player.sonos]")
        try await recorder.callService("media_player", "volume_set", data: ["entity_id": "media_player.sonos", "volume_level": 0.5])
        #expect(store.value("media_player.sonos")?.attributes["volume_level"]?.number == 0.5)
        try await recorder.callService("media_player", "toggle", data: ["entity_id": "media_player.sony_projector"])
        #expect(store.value("media_player.sony_projector")?.state == "off")
        try await recorder.callService("switch", "turn_off", data: ["entity_id": "switch.x"])
        try await recorder.callService("switch", "turn_on", data: ["entity_id": "switch.x"])
        #expect(store.value("switch.x")?.state == "on")
        try await recorder.callService("select", "select_option", data: ["entity_id": "select.x", "option": "b"])
        #expect(store.value("select.x")?.state == "b")
        try await recorder.callService("number", "set_value", data: ["entity_id": "number.x", "value": 7])
        #expect(store.value("number.x")?.state == "7")
        try await recorder.callService("input_button", "press", data: ["entity_id": "input_button.theater_pc_on"])
        #expect(store.value("input_boolean.theater_pc_power")?.state == "on")
        try await recorder.callService("script", "apple_tv_power_on_off", data: [:])
        #expect(store.value("media_player.master_bedroom_apple_tv")?.state == "standby")
        try await recorder.callService("script", "toggle_on_off_theater_room", data: [:])
        #expect(store.value("media_player.theater_room_shield")?.state == "off")
        try await recorder.callService("script", "music_room_tv_off", data: [:])
        #expect(store.value(MediaRemotes.MusicRoom.controlEntityId)?.state == "off")
        try await recorder.callService("script", "music_room_tv", data: [:])
        #expect(store.value(MediaRemotes.MusicRoom.activeMediaSourceEntityId)?.state == "TV")
        try await recorder.callService("light", "turn_on", data: [:])
        #expect(recorder.lastCall == "light.turn_on")
    }

    @Test func galleryRenders() {
        #expect(ComponentGallery.Page(rawValue: "media-remote") == .mediaRemote)
        #expect(ComponentGallery.requested == nil)
        let renderer = ImageRenderer(content: ComponentGallery(page: .mediaRemote).frame(width: 402, height: 874))
        #expect(renderer.cgImage != nil)
        #expect(MediaRemoteFixtures.imageServer != nil)
    }

    // MARK: Keyboard and sliders

    @Test func keyboardPromptOpensSendsAndCloses() async {
        let caller = NullCaller()
        let store = MediaRemoteFixtures.store()
        let controller = MediaRemoteController(config: MediaRemotes.livingRoomShield, store: store, caller: caller)
        var prompt = KeyboardPrompt()
        prompt.toggle("media_player.living_room_shield_2")
        #expect(prompt.isOpen)
        prompt.text = "  "
        prompt.submit(with: controller)
        #expect(prompt.isOpen, "Blank text keeps the prompt open")
        prompt.text = "plex"
        prompt.submit(with: controller)
        #expect(prompt == KeyboardPrompt())
        await controller.waitForCalls()
        #expect(caller.calls == ["androidtv.adb_command"])
        prompt.toggle("a")
        prompt.toggle("b")
        #expect(prompt.target == "b", "Another target re-targets")
        prompt.toggle("b")
        #expect(!prompt.isOpen)
        prompt.submit(with: controller)
        await controller.waitForCalls()
        #expect(caller.calls.count == 1, "Closed prompt sends nothing")
    }

    @Test func sliderCommitsOnReleaseOrImmediateSteps() {
        var slider = SliderDraft()
        var commits: [Double] = []
        #expect(slider.shown(live: 30) == 30)
        slider.set(31) { commits.append($0) }
        #expect(commits == [31], "A step without a drag commits at once")
        slider.editingChanged(true, live: 30) { commits.append($0) }
        slider.set(55) { commits.append($0) }
        slider.set(60) { commits.append($0) }
        #expect(slider.shown(live: 30) == 60)
        #expect(commits == [31])
        slider.editingChanged(false, live: 30) { commits.append($0) }
        #expect(commits == [31, 60])
        slider.editingChanged(false, live: 30) { commits.append($0) }
        #expect(commits == [31, 60], "A second release commits nothing")
    }

    @Test func openKeyboardAndPresentationRender() throws {
        let store = MediaRemoteFixtures.store()
        let controller = MediaRemoteController(config: MediaRemotes.theaterRoomShield, store: store, caller: NullCaller())
        let open = KeyboardPrompt(target: "media_player.theater_room_shield", text: "it's")
        #expect(ImageRenderer(content: RemoteControlsTab(controller: controller, keyboard: open).frame(width: 402)).cgImage != nil)
        #expect(ImageRenderer(content: Color.clear.mediaRemotePresentation().frame(width: 10, height: 10)).cgImage != nil)
        let apps = RemoteAppsTab(controller: controller, imageServer: .fentonHome).frame(width: 402)
        #expect(ImageRenderer(content: apps).cgImage != nil)
        // Public initializers: a caller of your own, or the app's connection.
        let sheet = MediaRemoteSheet(config: MediaRemotes.musicRoom, store: store, caller: NullCaller()).frame(width: 402, height: 874)
        #expect(ImageRenderer(content: sheet).cgImage != nil)
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "remote-\(UUID()).json"))
        let connection = HassConnection(server: .fentonHome, tokens: TokenManager(store: InMemoryTokenStore()), store: store, snapshotCache: cache)
        let connected = MediaRemoteSheet(config: MediaRemotes.livingRoomShield, connection: connection, initialTab: .apps).frame(width: 402, height: 874)
        #expect(ImageRenderer(content: connected).cgImage != nil)
    }
}
