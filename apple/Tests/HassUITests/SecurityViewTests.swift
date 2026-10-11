import Foundation
@testable import HassCore
@testable import HassUI
import SwiftUI
import Testing

/// Hosted checks for the Security page: rendering from fixtures, tile text and tone, sheets and the gallery echo.
@MainActor
struct SecurityViewTests {
    final class Caller: HassServiceCalling {
        var calls: [String] = []
        func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
            calls.append("\(domain).\(service) \(data["entity_id"] as? String ?? "")")
        }
    }

    /// The page and both sheets draw from fixture state without a connection.
    @Test func pageAndSheetsRender() {
        let store = SecurityFixtures.store()
        let caller = Caller()
        let page = NavigationStack {
            SecurityPage(caller: caller, canSend: true, showsCameras: false, showsVehicle: true)
        }
        .environment(store)
        .frame(width: 402, height: 874)
        #expect(ImageRenderer(content: page).cgImage != nil)
        let sheet = SecuritySystemSheet(caller: caller).environment(store).frame(width: 402, height: 500)
        #expect(ImageRenderer(content: sheet).cgImage != nil)
        // Unavailable panel: modes draw disabled.
        let empty = SecuritySystemSheet(caller: caller).environment(EntityStore()).frame(width: 402, height: 500)
        #expect(ImageRenderer(content: empty).cgImage != nil)
    }

    /// Guest stays and the Contact Sensors sheet render with no `HassConnection` in the environment (the
    /// gallery path), and a guest toggle goes through the passed caller.
    @Test func guestSectionAndContactsSheetNeedNoConnection() {
        let store = SecurityFixtures.store()
        store.apply([EntityState(entityId: HomeConfig.guestToggles[0].entityId, state: "on")])
        let caller = Caller()
        let guests = GuestPresenceSection(caller: caller).environment(store).frame(width: 402)
        #expect(ImageRenderer(content: guests).cgImage != nil)
        let contacts = ChipSheet(kind: .contacts).environment(store).frame(width: 402, height: 500)
        #expect(ImageRenderer(content: contacts).cgImage != nil)
    }

    @Test func everyTileKindRenders() {
        let caller = Caller()
        let store = SecurityFixtures.store()
        for tile in SecurityConfig.controlTiles + SecurityConfig.vehicleTiles {
            let view = SecurityTile(tile: tile, caller: caller, canSend: true) {}.environment(store).frame(width: 170)
            #expect(ImageRenderer(content: view).cgImage != nil)
        }
        for state: EntityState? in [nil, EntityState(entityId: SecurityConfig.alarmEntityId, state: "unavailable")] {
            let alarm = AlarmTile(tile: SecurityConfig.controlTiles[0], state: state) {}.frame(width: 170)
            #expect(ImageRenderer(content: alarm).cgImage != nil)
        }
        let modes = SecurityConfig.alarmModes.map { AlarmModeButton(mode: $0, isSelected: $0.state == "disarmed", isUnavailable: false) {} }
        for mode in modes { #expect(ImageRenderer(content: mode.frame(width: 150)).cgImage != nil) }
    }

    @Test func garageSubtitlesAndTones() async {
        let caller = Caller()
        let scheduler = TaskRevertScheduler()
        let garage = GarageDoorController(entityId: SecurityConfig.rightGarageDoorEntityId, liveState: "open", caller: caller, scheduler: scheduler)
        #expect(GarageDoorTile.subtitle(for: garage) == "Open")
        #expect(GarageDoorTile.tone(for: garage) == .danger)
        garage.send()
        #expect(GarageDoorTile.subtitle(for: garage) == "Sending Close…")
        #expect(GarageDoorTile.tone(for: garage) == .active, "Shows closing")
        await garage.waitForCall()
        #expect(caller.calls == ["cover.close_cover cover.garage_right_door"])
        garage.liveDidChange("closed")
        #expect(GarageDoorTile.subtitle(for: garage) == "Closed")
        #expect(GarageDoorTile.tone(for: garage) == .secure)
        garage.send()
        #expect(GarageDoorTile.subtitle(for: garage) == "Sending Open…")
        garage.connectionDidChange(canSend: false)
        #expect(GarageDoorTile.subtitle(for: garage) == "Error")
        #expect(GarageDoorTile.tone(for: garage) == .danger)
        garage.liveDidChange("unavailable")
        #expect(GarageDoorTile.subtitle(for: garage) == "Unavailable")
    }

    @Test func connectionStatusGatesCommands() {
        #expect(SecurityScreen.canSend(.connected(version: "2026.10")))
        #expect(SecurityScreen.canSend(.connecting))
        #expect(!SecurityScreen.canSend(.disconnected))
        #expect(!SecurityScreen.canSend(.waitingToReconnect))
        #expect(!SecurityScreen.canSend(.rejected))
    }

    @Test func chipsOpenTheirSheets() {
        #expect(SecurityPage.chips.map(\.sheet) == [.security, .contacts])
        #expect(SecuritySheet.chip(.security) == .system)
        #expect(SecuritySheet.chip(.contacts) == .contacts)
        let ids = [SecuritySheet.system, .contacts] + HomeConfig.cameras.map(SecuritySheet.camera)
        #expect(Set(ids.map(\.id)).count == ids.count)
    }

    @Test func toneColorsAreDistinct() {
        let tones: [SecurityConfig.Tone] = [.secure, .active, .danger, .neutral]
        #expect(Set(tones.map { "\($0.color)" }).count == tones.count)
        #expect("\(SecurityConfig.alarmTint(for: "armed_night"))" != "\(SecurityConfig.alarmTint(for: "armed_home"))")
    }

    /// The gallery recorder echoes locks, alarm modes and doors into the fixture store.
    @Test func galleryRecorderEchoes() async throws {
        let store = SecurityFixtures.store()
        let recorder = SecurityGalleryRecorder(store: store, fails: false)
        try await recorder.callService("lock", "unlock", data: ["entity_id": SecurityConfig.frontDoorLockEntityId])
        #expect(store.value(SecurityConfig.frontDoorLockEntityId)?.state == "unlocked")
        #expect(recorder.lastCall == "lock.unlock entity_id=lock.aqara_smart_lock_u400")
        try await recorder.callService("lock", "lock", data: ["entity_id": SecurityConfig.frontDoorLockEntityId])
        #expect(store.value(SecurityConfig.frontDoorLockEntityId)?.state == "locked")
        try await recorder.callService("alarm_control_panel", "alarm_arm_night", data: ["entity_id": SecurityConfig.alarmEntityId])
        #expect(store.value(SecurityConfig.alarmEntityId)?.state == "armed_night")
        try await recorder.callService("cover", "open_cover", data: ["entity_id": SecurityConfig.leftGarageDoorEntityId])
        try await Task.sleep(for: .seconds(5))
        #expect(store.value(SecurityConfig.leftGarageDoorEntityId)?.state == "open")
        try await recorder.callService("cover", "close_cover", data: ["entity_id": SecurityConfig.leftGarageDoorEntityId])
        try await recorder.callService("light", "turn_on", data: [:])
        let failing = SecurityGalleryRecorder(store: store, fails: true)
        await #expect(throws: SecurityGalleryRecorder.Failure.self) {
            try await failing.callService("cover", "open_cover", data: ["entity_id": SecurityConfig.leftGarageDoorEntityId])
        }
    }
}
