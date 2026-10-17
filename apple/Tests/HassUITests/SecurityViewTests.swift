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
        let contacts = RoomOverviewSheet(kind: .contacts).environment(store).frame(width: 402, height: 500)
        #expect(ImageRenderer(content: contacts).cgImage != nil)
    }

    @Test func everyRowAndModeRenders() {
        let caller = Caller()
        let store = SecurityFixtures.store()
        for tile in SecurityPage.doorTiles + SecurityConfig.vehicleTiles {
            let view = SecurityDoorTile(tile: tile, caller: caller, canSend: true).environment(store).frame(width: 170)
            #expect(ImageRenderer(content: view).cgImage != nil)
        }
        #expect(SecurityPage.doorTiles.map(\.kind) == [.lock, .garageDoor, .garageDoor])
        for scenario in [SecurityFixtures.Scenario.standard, .unavailable, .triggered] {
            let panel = AlarmPanel(caller: caller).environment(SecurityFixtures.store(scenario)).frame(width: 370)
            #expect(ImageRenderer(content: panel).cgImage != nil)
            let inSheet = panel.environment(\.tileSurface, .sheet)
            #expect(ImageRenderer(content: inSheet).cgImage != nil)
        }
        let large = AlarmPanel(caller: caller).environment(store).dynamicTypeSize(.accessibility5).frame(width: 370)
        #expect(ImageRenderer(content: large).cgImage != nil)
        let modes = SecurityConfig.modeButtons.map { AlarmModeButton(mode: $0, isSelected: $0.state == "disarmed", isUnavailable: false) {} }
        for mode in modes { #expect(ImageRenderer(content: mode.frame(width: 80)).cgImage != nil) }
        #expect(SecurityConfig.modeButtons.map { AlarmModeButton.symbol(for: $0) } == ["shield.slash", "house", "figure.walk", "moon"])
        for state in ["closed", "open", "unavailable"] {
            let tile = GarageDoorTile(tile: SecurityPage.doorTiles[1], liveState: state, caller: caller, canSend: true).frame(width: 170)
            #expect(ImageRenderer(content: tile).cgImage != nil)
        }
    }

    /// Lock tiles fill (the contact family) unless locked, and go red when jammed.
    @Test func lockTilesFillUnlessLocked() {
        #expect(!LockTile.isActive("locked"))
        for state in ["unlocked", "open", "locking", "unlocking", "jammed"] { #expect(LockTile.isActive(state), "\(state)") }
        #expect(!LockTile.isActive("unavailable") && !LockTile.isActive(nil))
        #expect(LockTile.symbol(for: .lock, state: "locked") == "lock")
        #expect(LockTile.symbol(for: .lock, state: "unlocked") == "lock.open")
        #expect(LockTile.symbol(for: .lock, state: "unavailable") == "lock")
        #expect(LockTile.symbol(for: .vehicle, state: "unlocked") == "car")
    }

    /// Lock tiles render in each state, in a grid cell's width.
    @Test func lockTilesRenderInEveryState() {
        let tile = SecurityConfig.controlTiles.first { $0.kind == .lock }!
        for state in ["locked", "unlocked", "locking", "jammed", "unavailable"] {
            let view = LockTile(tile: tile, state: EntityState(entityId: tile.entityId, state: state)) { _ in }.frame(width: 170)
            #expect(ImageRenderer(content: view).cgImage != nil, "\(state)")
        }
        #expect(ImageRenderer(content: LockTile(tile: tile, state: nil) { _ in }.frame(width: 170)).cgImage != nil)
    }

    /// The garage tile follows the command: Sending, the door's own movement, then Error on a failure.
    @Test func garageTileFollowsTheCommand() async {
        let caller = Caller()
        let garage = GarageDoorController(entityId: SecurityConfig.leftGarageDoorEntityId, liveState: "closed", caller: caller,
                                          scheduler: TaskRevertScheduler())
        #expect(GarageDoorTile.hint(for: garage) == "Opens the door")
        garage.send()
        #expect(GarageDoorTile.subtitle(for: garage) == "Sending Open…")
        await garage.waitForCall()
        garage.liveDidChange("opening")
        #expect(GarageDoorTile.symbol(for: garage) == "door.garage.open")
        garage.liveDidChange("open")
        #expect(GarageDoorTile.hint(for: garage) == "Closes the door")
        garage.send()
        garage.connectionDidChange(canSend: false)
        #expect(GarageDoorTile.subtitle(for: garage) == "Error")
        garage.liveDidChange("unavailable")
        #expect(GarageDoorTile.hint(for: garage) == "")
        #expect(GarageDoorTile.symbol(for: garage) == "door.garage.closed")
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

    /// Garage room cards draw the Security door tile under the card's title; other cards keep their tiles.
    @Test func garageRoomCardsUseTheDoorTile() {
        let garage = RoomsConfig.pages.first { $0.id == "garage" }!
        let cards = garage.sections.flatMap(\.cards).filter { $0.control == .garageDoor }
        #expect(cards.map(\.entityId) == [SecurityConfig.leftGarageDoorEntityId, SecurityConfig.rightGarageDoorEntityId])
        for card in cards {
            let tile = RoomCardView.garageTile(card)
            #expect(tile?.title == card.title)
            #expect(tile?.kind == .garageDoor)
        }
        let other = RoomsConfig.pages.flatMap(\.sections).flatMap(\.cards).first { $0.control != .garageDoor }!
        #expect(RoomCardView.garageTile(other) == nil)
        let store = SecurityFixtures.store()
        let controller = RoomController(page: garage, store: store, caller: Caller())
        let view = RoomCardView(controller: controller, card: cards[0]) {}.environment(store).frame(width: 170)
        #expect(ImageRenderer(content: view).cgImage != nil)
    }

    /// Quick Links' Security System detail shows the mode grid with a caller and the state alone without one.
    @Test func quickLinksSecurityDetailRenders() {
        let store = SecurityFixtures.store()
        for caller: (any HassServiceCalling)? in [Caller(), nil] {
            let view = NavigationStack { QuickLinksSecurityDetail(caller: caller) }.environment(store).frame(width: 402, height: 600)
            #expect(ImageRenderer(content: view).cgImage != nil)
        }
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
        // The door finishes opening a few seconds later; poll rather than guess how long the main actor is busy.
        for _ in 0..<3000 where store.value(SecurityConfig.leftGarageDoorEntityId)?.state != "open" {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.value(SecurityConfig.leftGarageDoorEntityId)?.state == "open")
        try await recorder.callService("cover", "close_cover", data: ["entity_id": SecurityConfig.leftGarageDoorEntityId])
        try await recorder.callService("light", "turn_on", data: [:])
        let failing = SecurityGalleryRecorder(store: store, fails: true)
        await #expect(throws: SecurityGalleryRecorder.Failure.self) {
            try await failing.callService("cover", "open_cover", data: ["entity_id": SecurityConfig.leftGarageDoorEntityId])
        }
    }
}
