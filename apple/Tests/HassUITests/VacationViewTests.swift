import Foundation
@testable import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// Hosted renders of the Vacation pages in every fixture scenario, and the gallery house's echoes.
@MainActor
struct VacationViewTests {
    private func render(_ view: some View, width: CGFloat = 402) -> CGImage? {
        ImageRenderer(content: NavigationStack { view }.frame(width: width, height: 874)).cgImage
    }

    @Test(arguments: VacationFixtures.Scenario.allCases)
    func everyPageRendersInEveryScenario(scenario: VacationFixtures.Scenario) {
        let store = VacationFixtures.store(scenario)
        let house = VacationGalleryHouse(store: store, delay: .zero)
        let household = HouseholdAwayController(store: store, responder: house)
        #expect(render(VacationScreen(store: store, responder: house, caller: house)) != nil)
        #expect(render(VacationChooser(household: household, store: store, caller: house)) != nil)
        #expect(render(VacationModeScreen(store: store, household: household, caller: house), width: 1180) != nil)
        #expect(render(SoloTripScreen(household: household, viewer: .steph), width: 1180) != nil)
    }

    @Test func sheetsRender() {
        let store = VacationFixtures.store(.ready)
        let house = VacationGalleryHouse(store: store, delay: .zero)
        let household = HouseholdAwayController(store: store, responder: house)
        let vacation = VacationModeController(store: store, household: household, caller: house)
        vacation.tapCard()
        #expect(vacation.isConfirming)
        #expect(render(VacationConfirmationSheet(controller: vacation)) != nil)
        let trip = SoloTripController(household: household)
        trip.selectTraveler(.stephen)
        trip.openEditor()
        #expect(render(SoloTripEditorSheet(controller: trip)) != nil)
    }

    @Test func sharedPiecesRender() {
        #expect(render(InfoBox(title: "Stephen Away", message: "Message", tone: .success)) != nil)
        #expect(render(InfoBox(title: "Steph Away")) != nil)
        #expect(render(InlineAlert("Error", severity: .error)) != nil)
        #expect(render(VacationChecklistRow(title: "Make the bed", isChecked: true, isUnavailable: false) {}) != nil)
        #expect(render(VacationChecklistRow(title: "Make the bed", isChecked: false, isUnavailable: true) {}) != nil)
        let field = ScheduleDateField("Start Date", .date, WallClock(date: "2026-10-20", time: "09:00"), id: "start") { _ in }
        #expect(render(ScheduleDateFields(fields: [field], commitDelay: .milliseconds(10))) != nil)
        #expect(render(AwayActionButton(title: "Go", role: .destructive, identifier: "go") {}) != nil)
    }

    @Test func wallClockFieldKeepsTheOtherPart() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let value = WallClock(date: "2026-10-20", time: "09:15")
        var reported: [WallClock] = []
        let dateField = ScheduleDateField("Date", .date, value, id: "d", calendar: calendar) { reported.append($0) }
        let timeField = ScheduleDateField("Time", .time, value, id: "t", calendar: calendar) { reported.append($0) }
        #expect(dateField.value == value.date(in: calendar))
        let picked = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 22, minute: 40))!
        dateField.onChange(picked)
        timeField.onChange(picked)
        #expect(reported == [WallClock(date: "2026-11-02", time: "09:15"), WallClock(date: "2026-10-20", time: "22:40")])
    }

    // MARK: Gallery house

    @Test func galleryHouseEchoesHelpers() async throws {
        let store = VacationFixtures.store(.idle)
        let house = VacationGalleryHouse(store: store, delay: .zero)
        try await house.callService("input_boolean", "turn_on", data: ["entity_id": Vacation.modeEntityId])
        #expect(store.value(Vacation.modeEntityId)?.state == "on")
        try await house.callService("input_boolean", "turn_off", data: ["entity_id": Vacation.modeEntityId])
        #expect(store.value(Vacation.modeEntityId)?.state == "off")
        try await house.callService("input_datetime", "set_datetime", data: ["entity_id": Vacation.endEntityId, "date": "2026-12-01", "time": "10:00:00"])
        #expect(store.value(Vacation.endEntityId)?.state == "2026-12-01 10:00:00")
        try await house.callService("light", "turn_on", data: ["entity_id": "light.x"])
        #expect(house.lastCall == "light.turn_on entity_id=light.x")
    }

    @Test func galleryHouseRunsSoloTrips() async throws {
        let store = VacationFixtures.store(.idle)
        let house = VacationGalleryHouse(store: store, delay: .zero)
        let household = HouseholdAwayController(store: store, responder: house)
        let tomorrow = WallClock(Calendar.current.date(byAdding: .day, value: 1, to: .now)!)
        let later = WallClock(Calendar.current.date(byAdding: .day, value: 4, to: .now)!)
        #expect(await household.scheduleSoloTrip(traveler: .steph, draft: SoloTripDraft(start: tomorrow, end: later)) == .accepted(revision: 4))
        #expect(household.snapshot.state == .scheduled)
        #expect(household.snapshot.homeResident == .stephen)
        #expect(household.snapshot.end == later)
        let moved = WallClock(date: later.date, time: "23:00")
        await household.updateEnd(moved)
        #expect(household.snapshot.end == moved)
        await household.cancel()
        #expect(household.snapshot.state == .idle)
        #expect(household.snapshot.mode == .none)
        let now = WallClock(.now.addingTimeInterval(-60))
        await household.scheduleSoloTrip(traveler: .stephen, draft: SoloTripDraft(start: now, end: later))
        #expect(household.snapshot.isFullyActive)
    }

    @Test func galleryHouseResolvesAndRejects() async throws {
        let store = VacationFixtures.store(.soloRestore)
        let house = VacationGalleryHouse(store: store, delay: .zero)
        let household = HouseholdAwayController(store: store, responder: house)
        await household.resolveRestore(.restoreSaved)
        #expect(household.snapshot.state == .active)
        let response = try await house.callServiceWithResponse("script", "household_away_command", data: ["operation": "launch"])
        #expect(response["status"] == .string("rejected"))
    }

    @Test func fixtures() {
        #expect(VacationFixtures.Scenario.allCases.count == 8)
        let unavailable = HouseholdAway.Snapshot(entity: VacationFixtures.states(.unavailable).last)
        #expect(!unavailable.canCommand)
        let invalid = VacationFixtures.states(.invalidDates)
        let range = Vacation.DateRange(startState: invalid[2].state, endState: invalid[3].state)
        #expect(range.isInvalid())
        #expect(ComponentGallery.Page(rawValue: "vacation") == .vacation)
    }
}
