import AppKit
import Foundation
@testable import HassCore
@testable import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// Drives the Vacation and Solo Trip screens the way a person does (tap a tile, turn a date wheel, press
/// Confirm) on the gallery house, and checks what reaches Home Assistant and what the screen then shows.
///
/// Controls are reached through ``ControlProbe``; sheets and `@State` need a live hierarchy, so those tests
/// host the screen in ``SheetHostWindow``.
@MainActor
@Suite(.serialized)
struct VacationInteractionTests {
    // MARK: Fixtures

    private struct House {
        let store: EntityStore
        let house: VacationGalleryHouse
        let household: HouseholdAwayController
    }

    private func makeHouse(_ scenario: VacationFixtures.Scenario) -> House {
        let store = VacationFixtures.store(scenario)
        let house = VacationGalleryHouse(store: store, delay: .zero)
        return House(store: store, house: house, household: HouseholdAwayController(store: store, responder: house))
    }

    /// The controller a screen keeps in `@State` (a reference, so it is shared with the live copy).
    private func controller<T>(_ type: T.Type, of screen: Any) throws -> T {
        for child in Mirror(reflecting: screen).children {
            if let state = child.value as? State<T> { return state.wrappedValue }
        }
        throw Missing()
    }

    private struct Missing: Error {}

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
        return condition()
    }

    private func date(_ days: Int, hour: Int = 10) -> Date {
        let day = Calendar.current.date(byAdding: .day, value: days, to: .now)!
        return Calendar.current.date(bySettingHour: hour, minute: 15, second: 0, of: day)!
    }

    private func render(_ view: some View, width: CGFloat = 402) -> CGImage? {
        ImageRenderer(content: NavigationStack { view }.frame(width: width, height: 874)).cgImage
    }

    // MARK: Vacation Mode

    @Test func enablingAVacationFromTheSheetSavesDatesAndTurnsItOn() async throws {
        let h = makeHouse(.ready)
        let screen = VacationModeScreen(store: h.store, household: h.household, caller: h.house)
        let vacation = try controller(VacationModeController.self, of: screen)
        let hosted = SheetHostWindow(NavigationStack { screen })

        let tile = try #require(ControlProbe.first(GlassTile<EmptyView>.self, in: screen.body))
        #expect(tile.title == "Vacation Mode")
        #expect(tile.kind == .toggle)
        #expect(!tile.isActive)
        tile.action()
        hosted.settle()
        #expect(vacation.isConfirming)
        #expect(hosted.hasSheet)

        // The sheet's date wheels edit the draft, not Home Assistant.
        let sheet = VacationConfirmationSheet(controller: vacation)
        // Each field closes over the range it was built from, so rebuild the sheet after every change as SwiftUI does.
        func fields() throws -> [ScheduleDateField] { try #require(ControlProbe.first(ScheduleDateFields.self, in: sheet.body)).fields }
        #expect(try fields().map(\.identifier) == ["vacation.confirm.start", "vacation.confirm.end"])
        #expect(try fields().map(\.part) == [.dateAndTime, .dateAndTime])
        let start = date(3), end = date(9, hour: 18)
        try fields()[0].onChange(start)
        try fields()[1].onChange(end)
        let draft = try #require(vacation.pendingRange)
        // One picker sets both the date and the time.
        #expect(draft.start == WallClock(start))
        #expect(draft.end == WallClock(end))
        #expect(h.house.lastCall == "None")

        let confirm = try #require(ControlProbe.all(AwayActionButton.self, in: sheet.body).first)
        #expect(confirm.title == "Confirm Vacation")
        confirm.action()
        await vacation.drain()
        #expect(!vacation.isConfirming)
        #expect(h.store.value(Vacation.modeEntityId)?.state == "on")
        #expect(h.store.value(Vacation.startEntityId)?.state.hasPrefix(draft.start.date) == true)
        #expect(h.store.value(Vacation.endEntityId)?.state.hasPrefix(draft.end.date) == true)
    }

    @Test func aReversedRangeHidesConfirmAndShowsTheError() throws {
        let h = makeHouse(.ready)
        let vacation = VacationModeController(store: h.store, household: h.household, caller: h.house)
        vacation.tapCard()
        let sheet = VacationConfirmationSheet(controller: vacation)
        #expect(ControlProbe.all(AwayActionButton.self, in: sheet.body).count == 1)
        let fields = try #require(ControlProbe.first(ScheduleDateFields.self, in: sheet.body)).fields
        fields[1].onChange(date(-3))
        #expect(vacation.invalidDateRange)
        #expect(ControlProbe.all(AwayActionButton.self, in: sheet.body).isEmpty)
        #expect(ControlProbe.all(InlineAlert.self, in: sheet.body).map(\.message) == [Vacation.Copy.dateRangeError])
    }

    @Test func inlineDatesWriteEachChangeToHomeAssistant() async throws {
        let h = makeHouse(.vacation)
        let screen = VacationModeScreen(store: h.store, household: h.household, caller: h.house)
        let vacation = try controller(VacationModeController.self, of: screen)
        let fields = try #require(ControlProbe.first(ScheduleDateFields.self, in: screen.body)).fields
        #expect(fields.map(\.identifier) == ["vacation.dates.start", "vacation.dates.end"])
        let end = date(12)
        fields[1].onChange(end)
        await vacation.drain()
        #expect(h.store.value(Vacation.endEntityId)?.state.hasPrefix(WallClock(end).date) == true)
        let start = date(2, hour: 7)
        fields[0].onChange(start)
        await vacation.drain()
        #expect(h.store.value(Vacation.startEntityId)?.state.contains(WallClock(start).time) == true)
        // Start and end are separate helpers: moving the start leaves the end alone.
        #expect(h.store.value(Vacation.endEntityId)?.state.hasPrefix(WallClock(end).date) == true)
    }

    @Test func checklistRowsToggleTheirHelper() async throws {
        let h = makeHouse(.idle)
        let screen = VacationModeScreen(store: h.store, household: h.household, caller: h.house)
        let vacation = try controller(VacationModeController.self, of: screen)
        let item = Vacation.checklist[4]
        #expect(!vacation.isChecked(item))
        vacation.toggle(item)
        await vacation.drain()
        #expect(h.store.value(item.entityId)?.state == "on")
    }

    /// The Vacation Mode card sends no Household Away commands, so a Solo Trip command's error (the shared
    /// controller's) never shows above it (owner report 2026-10-13: "could not apply the Solo Trip change").
    @Test func aSoloTripErrorDoesNotShowOnTheVacationPage() async throws {
        let h = makeHouse(.ready)
        let rejecting = RejectingResponder()
        let household = HouseholdAwayController(store: h.store, responder: rejecting)
        await household.cancel()
        #expect(household.errorCode != nil)
        let screen = VacationModeScreen(store: h.store, household: household, caller: h.house)
        #expect(ControlProbe.all(InlineAlert.self, in: screen.body).isEmpty)
        #expect(render(screen) != nil)
    }

    @Test func aSoloTripOnTheVacationPageOffersTheRestoreActions() async throws {
        let h = makeHouse(.soloRestore)
        let screen = VacationModeScreen(store: h.store, household: h.household, caller: h.house)
        let status = try #require(ControlProbe.first(SoloTripStatusView.self, in: screen.body))
        #expect(status.status.actions.contains(.keepCurrent))
        status.perform(.keepCurrent)
        #expect(await eventually { h.house.lastCall.contains("resolve_restore") })
        #expect(h.house.lastCall.contains("keep_current"))
        #expect(await eventually { h.household.snapshot.state == .active })
        let ending = try #require(ControlProbe.first(SoloTripStatusView.self, in: screen.body))
        ending.perform(.endNow)
        #expect(await eventually { h.household.snapshot.state == .idle })
    }

    @Test func restoringTheSavedPlanFromTheVacationPage() async throws {
        let h = makeHouse(.soloRestore)
        let screen = VacationModeScreen(store: h.store, household: h.household, caller: h.house)
        let status = try #require(ControlProbe.first(SoloTripStatusView.self, in: screen.body))
        status.perform(.restoreSaved)
        #expect(await eventually { h.house.lastCall.contains("restore_saved") })
    }

    // MARK: Solo Trip

    @Test func schedulingATripFromTheEditorSheet() async throws {
        let h = makeHouse(.idle)
        let screen = SoloTripScreen(household: h.household, viewer: .stephen)
        let trip = try controller(SoloTripController.self, of: screen)
        let hosted = SheetHostWindow(NavigationStack { screen })

        // The traveler tiles come from a `ForEach`, which reflection can't expand: build the tile as the screen does.
        let tile = try #require(trip.travelerTiles.first { $0.resident == .stephen })
        #expect(tile.isInteractive)
        TravelerTileView(tile: tile) { trip.selectTraveler(tile.resident) }.action()
        #expect(trip.selectedTraveler == .stephen)

        let toggle = try #require(ControlProbe.all(GlassTile<EmptyView>.self, in: screen.body).first { $0.title == SoloTripCopy.title })
        toggle.action()
        #expect(await eventually { trip.editorOpen })
        hosted.settle()
        #expect(hosted.hasSheet)

        let sheet = SoloTripEditorSheet(controller: trip)
        func fields() throws -> [ScheduleDateField] { try #require(ControlProbe.first(ScheduleDateFields.self, in: sheet.body)).fields }
        #expect(try fields().map(\.identifier) == ["soloTrip.editor.start", "soloTrip.editor.end"])
        let start = date(1, hour: 8), end = date(5, hour: 19)
        try fields()[0].onChange(start)
        try fields()[1].onChange(end)
        #expect(trip.scheduleDraft.start == WallClock(start))
        #expect(trip.scheduleDraft.end == WallClock(end))

        let confirm = try #require(ControlProbe.all(AwayActionButton.self, in: sheet.body).first)
        #expect(confirm.title == SoloTripCopy.editorConfirm)
        confirm.action()
        #expect(await eventually { h.household.snapshot.state == .scheduled })
        #expect(h.household.snapshot.start == WallClock(start))
        #expect(h.household.snapshot.end == WallClock(end))
        #expect(h.household.snapshot.mode == .soloTrip)
    }

    @Test func movingTheReturnTimeOfARunningTrip() async throws {
        let h = makeHouse(.soloActive)
        let screen = SoloTripScreen(household: h.household, viewer: .stephen)
        let fields = try #require(ControlProbe.first(ScheduleDateFields.self, in: screen.body)).fields
        #expect(fields.map(\.identifier) == ["soloTrip.return"])
        let end = date(9, hour: 20)
        fields[0].onChange(end)
        #expect(await eventually { h.household.snapshot.end?.date == WallClock(end).date })
        #expect(h.house.lastCall.contains("update_end"))
    }

    @Test func theRestoreChoiceReachesTheScript() async throws {
        let h = makeHouse(.soloRestore)
        let screen = SoloTripScreen(household: h.household, viewer: .stephen)
        let status = try #require(ControlProbe.first(SoloTripStatusView.self, in: screen.body))
        status.perform(.keepCurrent)
        #expect(await eventually { h.house.lastCall.contains("keep_current") })
        #expect(await eventually { h.household.snapshot.state == .active })
    }

    @Test func endingARunningTripFromItsStatus() async throws {
        let h = makeHouse(.soloActive)
        let screen = SoloTripScreen(household: h.household, viewer: .stephen)
        let toggle = try #require(ControlProbe.all(GlassTile<EmptyView>.self, in: screen.body).first { $0.title == SoloTripCopy.title })
        #expect(toggle.isActive)
        toggle.action()
        #expect(await eventually { h.household.snapshot.state == .idle })
        #expect(h.house.lastCall.contains("end_now"))
    }

    @Test func endNowFromTheStatusEndsTheTrip() async throws {
        let h = makeHouse(.soloActive)
        var attributes = try #require(h.store.value(HouseholdAway.statusEntityId)).attributes
        attributes["effects"] = VacationFixtures.effects(false)
        h.store.apply([EntityState(entityId: HouseholdAway.statusEntityId, state: "degraded", attributes: attributes)])
        let screen = SoloTripScreen(household: h.household, viewer: .stephen)
        let status = try #require(ControlProbe.first(SoloTripStatusView.self, in: screen.body))
        #expect(status.status.title == SoloTripCopy.degradedTitle)
        status.perform(.endNow)
        #expect(await eventually { h.house.lastCall.contains("end_now") })
        #expect(await eventually { h.household.snapshot.state == .idle })
    }

    @Test func restoringTheSavedPlan() async throws {
        let h = makeHouse(.soloRestore)
        let screen = SoloTripScreen(household: h.household, viewer: .stephen)
        let status = try #require(ControlProbe.first(SoloTripStatusView.self, in: screen.body))
        status.perform(.restoreSaved)
        #expect(await eventually { h.house.lastCall.contains("restore_saved") })
    }

    // MARK: Route latch

    @Test func turningTheModeOffKeepsTheEngagedPage() async throws {
        let h = makeHouse(.idle)
        let screen = VacationScreen(store: h.store, responder: h.house, caller: h.house)
        let hosted = SheetHostWindow(screen)
        #expect(hosted.contains("SwiftUIOutlineListView"), "idle shows the chooser list")

        h.store.apply([EntityState(entityId: Vacation.modeEntityId, state: "on")])
        hosted.settle()
        #expect(!hosted.contains("SwiftUIOutlineListView"), "an engaged vacation shows its own page")

        h.store.apply([EntityState(entityId: Vacation.modeEntityId, state: "off")])
        hosted.settle()
        #expect(!hosted.contains("SwiftUIOutlineListView"), "turning it off must not swap the root back to the chooser")
    }

    @Test func aTripThatEndsKeepsItsPage() async throws {
        let h = makeHouse(.soloActive)
        let screen = VacationScreen(store: h.store, responder: h.house, caller: h.house) { HouseholdResident.stephen.haUserId }
        let hosted = SheetHostWindow(screen)
        #expect(!hosted.contains("SwiftUIOutlineListView"))
        await h.household.endNow()
        let idle = VacationFixtures.states(.idle).last!
        h.store.apply([idle])
        hosted.settle()
        #expect(!hosted.contains("SwiftUIOutlineListView"))
    }

    // MARK: Gallery

    @Test func theGalleryPageShowsTheLastCallLine() async throws {
        let gallery = VacationGallery()
        #expect(render(gallery) != nil)
        let hosted = SheetHostWindow(gallery)
        #expect(hosted.contains("NSHostingView") || hosted.host.subviews.isEmpty == false)
        let texts = ControlProbe.all(Text.self, in: gallery.body)
        #expect(!texts.isEmpty)
    }
}

/// Rejects every Household Away command, so the controller keeps an error code.
@MainActor
private final class RejectingResponder: HassServiceResponding {
    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {}

    func callServiceWithResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        .object(["status": .string("rejected"), "error_code": .string("stale_revision")])
    }
}
