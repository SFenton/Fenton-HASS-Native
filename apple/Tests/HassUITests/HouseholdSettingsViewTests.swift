import Foundation
@testable import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing
#if canImport(AppKit)
import AppKit
#endif

/// Hosted renders of the household Settings pages, sheets and shared pieces, plus symbol and copy checks.
@MainActor
struct HouseholdSettingsViewTests {
    private func controller(unavailable: Bool = false) -> HouseholdSettingsController {
        HouseholdSettingsController(store: HouseholdSettingsFixtures.store(unavailable: unavailable), caller: NullCaller())
    }

    private func render(_ view: some View, width: CGFloat = 402) -> CGImage? {
        ImageRenderer(content: view.frame(width: width, height: 874)).cgImage
    }

    @Test func rowsMatchTheWebCopy() {
        #expect(HouseholdSettingsPage.allCases.map(\.rowTitle) == ["Admin Controls", "Special Device Modes", "Guest Controls", "Mach-E"])
        #expect(HouseholdSettingsPage.admin.subtitle == "Presence-Based Toggles, Automation Overrides, and More")
        #expect(HouseholdSettingsPage.allCases.map(\.pageTitle) == ["Admin", "Special Device Modes", "Guest Controls", "Mach-E"])
        for page in HouseholdSettingsPage.allCases { #expect(page.id == page.rawValue) }
    }

    #if canImport(AppKit)
    /// Every SF Symbol the pages use exists (a missing name draws nothing).
    @Test func everySymbolExists() {
        var names = HouseholdSettingsConfig.icons.map(SymbolMap.symbol(for:))
        names += HouseholdSettingsPage.allCases.map(\.symbol)
        for name in names {
            #expect(name != "circle", "unmapped icon")
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(name)")
        }
    }
    #endif

    @Test func pagesRenderLiveAndUnavailable() {
        for unavailable in [false, true] {
            for page in HouseholdSettingsPage.allCases {
                let view = NavigationStack { HouseholdSettingsPageView(page: page, controller: controller(unavailable: unavailable)) }
                #expect(render(view) != nil)
                #expect(render(view, width: 1180) != nil)
            }
        }
    }

    @Test func pagesBuildFromAStoreAndCaller() {
        let view = HouseholdSettingsPageView(page: .guests, store: HouseholdSettingsFixtures.store(), caller: NullCaller())
        #expect(render(NavigationStack { view }) != nil)
    }

    @Test func destinationAndSettingsListRenderWithTheConnection() {
        let store = HouseholdSettingsFixtures.store()
        let connection = HassConnection(server: .fentonHome, tokens: TokenManager(store: InMemoryTokenStore()), store: store)
        let session = AppSession(tokenStore: InMemoryTokenStore(), snapshotCache: EntitySnapshotCache(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "household-\(UUID()).json")))
        for view in [AnyView(NavigationStack { HouseholdSettingsDestination(page: .admin) }), AnyView(NavigationStack { SettingsScreen() })] {
            #expect(render(view.environment(session).environment(connection).environment(store)) != nil)
        }
    }

    @Test func sheetsAndDetailRender() {
        let settings = controller()
        let room = HouseholdSettingsConfig.Admin.presenceRooms[0]
        #expect(render(PresenceOverridesSheet(controller: settings)) != nil)
        #expect(render(PresenceOverridesSheet(controller: settings, initialRoom: room)) != nil)
        #expect(render(NavigationStack { PresenceOverrideDetail(room: room, controller: settings) }) != nil)
        #expect(render(NavigationStack { PresenceOverrideDetail(room: room, controller: settings, done: {}) }) != nil)
        #expect(render(NavigationStack { PresenceOverrideDetail(room: room, controller: controller(unavailable: true)) }) != nil)
        #expect(render(AutoResetSheet(controller: settings)) != nil)
    }

    @Test func galleryRenders() {
        #expect(render(ComponentGallery(page: .householdSettings)) != nil)
        #expect(render(NavigationStack { HouseholdSettingsGallery() }) != nil)
        // The gallery's List footer isn't drawn by ImageRenderer, so render the last-call line directly.
        #expect(render(HouseholdGalleryLastCall(recorder: HouseholdGalleryRecorder(store: HouseholdSettingsFixtures.store()))) != nil)
    }

    @Test func sharedPiecesRender() {
        let section = SettingsSection(title: "Title", paragraphs: ["One.", "Two."]) { InlineAlert("Careful.") }
        #expect(render(section) != nil)
        for selected in [true, false] {
            #expect(render(SelectableOptionRow(title: "Paused", detail: "Stays put.", symbol: "pause.circle", tint: .orange,
                                               isSelected: selected, isDisabled: !selected) {}) != nil)
        }
        #expect(render(GlassStateTile(title: "Doors", subtitle: "Locked", symbol: "lock", tint: .blue, isActive: false)) != nil)
        #expect(render(GlassStateTile(title: "Doors", symbol: "lock", tint: .blue, isActive: true, isUnavailable: true)) != nil)
    }

    @Test func galleryRecorderEchoesCalls() async throws {
        let store = HouseholdSettingsFixtures.store()
        let recorder = HouseholdGalleryRecorder(store: store)
        let aqi = HouseholdSettingsConfig.SpecialDeviceModes.highAqiTile.entityId
        try await recorder.callService("input_boolean", "turn_on", data: ["entity_id": aqi])
        #expect(store.value(aqi)?.state == "on")
        #expect(recorder.lastCall == "input_boolean.turn_on entity_id=input_boolean.high_aqi_mode")
        try await recorder.callService("input_boolean", "turn_off", data: ["entity_id": aqi])
        #expect(store.value(aqi)?.state == "off")
        let room = HouseholdSettingsConfig.Admin.presenceRooms[1].presenceEntityId
        try await recorder.callService("presence_based_lighting", "set_automation_state", data: ["entity_id": room, "state": "quieted"])
        #expect(PresenceOverrideState(entity: store.value(room)) == .quieted)
        try await recorder.callService("presence_based_lighting", "set_automation_state", data: ["entity_id": room, "state": "off"])
        #expect(PresenceOverrideState(entity: store.value(room)) == .off)
        // No state means active; an unrecognized service on a known entity leaves it alone.
        try await recorder.callService("presence_based_lighting", "set_automation_state", data: ["entity_id": room])
        #expect(PresenceOverrideState(entity: store.value(room)) == .enabled)
        try await recorder.callService("input_boolean", "toggle", data: ["entity_id": aqi])
        #expect(store.value(aqi)?.state == "off")
        // Unknown services and entities change nothing.
        try await recorder.callService("automation", "trigger", data: ["entity_id": HouseholdSettingsConfig.Admin.powerRecoveryAutomation])
        try await recorder.callService("light", "turn_on", data: [:])
        #expect(store.value(HouseholdSettingsConfig.Admin.powerRecoveryAutomation) == nil)
    }

    @Test func fixturesCoverEveryMode() {
        let store = HouseholdSettingsFixtures.store()
        let modes = Set(HouseholdSettingsConfig.Admin.presenceRooms.map { PresenceOverrideState(entity: store.value($0.presenceEntityId)) })
        #expect(modes == Set(PresenceOverrideState.allCases))
    }
}
