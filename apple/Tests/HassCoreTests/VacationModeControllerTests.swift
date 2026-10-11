import Foundation
@testable import HassCore
import Testing

struct VacationConfigTests {
    let calendar = TestClock.calendar
    let now = TestClock.now

    @Test func defaultRangeIsOneDay() {
        let range = Vacation.DateRange.makeDefault(now: now, calendar: calendar)
        #expect(range.start == WallClock(date: "2026-10-11", time: "16:30"))
        #expect(range.end == WallClock(date: "2026-10-12", time: "16:30"))
        #expect(!range.isInvalid(calendar: calendar))
        #expect(range.isFuture(now: now, calendar: calendar))
    }

    @Test func rangeFromHelperStates() {
        let range = Vacation.DateRange(startState: "2026-12-20 07:15:00", endState: "2026-12-27T19:45:00", now: now, calendar: calendar)
        #expect(range.start == WallClock(date: "2026-12-20", time: "07:15"))
        #expect(range.end == WallClock(date: "2026-12-27", time: "19:45"))
    }

    @Test func malformedPartsFallBackOneByOne() {
        let range = Vacation.DateRange(startState: "2026-12-20 nope", endState: "unknown", now: now, calendar: calendar)
        #expect(range.start == WallClock(date: "2026-12-20", time: "16:30"))
        #expect(range.end == WallClock(date: "2026-10-12", time: "16:30"))
        #expect(Vacation.DateRange(startState: nil, endState: "2026-12-20", now: now, calendar: calendar).end == WallClock(date: "2026-12-20", time: "16:30"))
    }

    @Test func invalidAndFutureRanges() {
        let reversed = Vacation.DateRange(start: WallClock(date: "2026-10-20", time: "09:00"), end: WallClock(date: "2026-10-19", time: "09:00"))
        #expect(reversed.isInvalid(calendar: calendar))
        let equal = Vacation.DateRange(start: WallClock(date: "2026-10-20", time: "09:00"), end: WallClock(date: "2026-10-20", time: "09:00"))
        #expect(equal.isInvalid(calendar: calendar))
        let unreadable = Vacation.DateRange(start: WallClock(date: "", time: ""), end: WallClock(date: "2026-10-20", time: "09:00"))
        #expect(!unreadable.isInvalid(calendar: calendar))
        let past = Vacation.DateRange(start: WallClock(date: "2026-10-01", time: "09:00"), end: WallClock(date: "2026-10-02", time: "09:00"))
        #expect(!past.isFuture(now: now, calendar: calendar))
        #expect(!Vacation.DateRange(start: past.start, end: WallClock(date: "", time: "")).isFuture(now: now, calendar: calendar))
    }

    @Test func serviceCalls() {
        let range = Vacation.DateRange(start: WallClock(date: "2026-10-20", time: "09:00"), end: WallClock(date: "2026-10-27", time: "18:30"))
        #expect(Vacation.confirmCalls(range) == [
            ServiceCall("input_datetime", "set_datetime", target: Vacation.startEntityId, data: ["date": .string("2026-10-20"), "time": .string("09:00:00")]),
            ServiceCall("input_datetime", "set_datetime", target: Vacation.endEntityId, data: ["date": .string("2026-10-27"), "time": .string("18:30:00")]),
            ServiceCall("input_boolean", "turn_off", target: Vacation.invalidDatesPendingEntityId),
            ServiceCall("input_boolean", "turn_on", target: Vacation.modeEntityId),
        ])
        let disable = Vacation.disableCalls()
        #expect(disable.count == 7)
        #expect(disable.allSatisfy { $0.service == "turn_off" })
        #expect(Set(disable.compactMap(\.target)) == Set([Vacation.modeEntityId, Vacation.invalidDatesPendingEntityId] + Vacation.checklist.map(\.entityId)))
        #expect(Vacation.recoveryCalls().map(\.service) == ["turn_on", "turn_off"])
        #expect(Vacation.pageEntityIds.count == 9)
    }

    @Test func routing() {
        let idle = HouseholdAway.Snapshot(entity: awayEntity())
        #expect(Vacation.route(snapshot: idle, vacationModeOn: false, invalidDatesPending: false) == .chooser)
        #expect(Vacation.route(snapshot: idle, vacationModeOn: true, invalidDatesPending: false) == .vacationMode)
        #expect(Vacation.route(snapshot: idle, vacationModeOn: false, invalidDatesPending: true) == .vacationMode)
        let backendVacation = HouseholdAway.Snapshot(entity: awayEntity("active", awayAttributes(mode: "vacation")))
        #expect(Vacation.route(snapshot: backendVacation, vacationModeOn: false, invalidDatesPending: false) == .vacationMode)
        let solo = HouseholdAway.Snapshot(entity: awayEntity("scheduled", awayAttributes(mode: "solo_trip", traveler: "steph")))
        #expect(Vacation.route(snapshot: solo, vacationModeOn: false, invalidDatesPending: false) == .soloTrip)
        let idleSolo = HouseholdAway.Snapshot(entity: awayEntity("idle", awayAttributes(mode: "solo_trip")))
        #expect(Vacation.route(snapshot: idleSolo, vacationModeOn: false, invalidDatesPending: false) == .chooser)
    }
}

@MainActor
struct VacationModeControllerTests {
    struct Harness {
        let controller: VacationModeController
        let store: EntityStore
        let caller: RecordingCaller
        let scheduler: ManualScheduler
        let responder: ScriptedResponder
    }

    func make(mode: String = "off", checklist: [String]? = nil, invalidPending: String = "off",
              start: String = "2026-10-20 09:00:00", end: String = "2026-10-27 18:00:00",
              away: EntityState = awayEntity()) -> Harness {
        var states: [String: String] = [
            Vacation.modeEntityId: mode,
            Vacation.invalidDatesPendingEntityId: invalidPending,
            Vacation.startEntityId: start,
            Vacation.endEntityId: end,
        ]
        for (index, item) in Vacation.checklist.enumerated() { states[item.entityId] = checklist?[index] ?? "off" }
        let store = makeStore(states)
        store.apply([away])
        let caller = RecordingCaller()
        let scheduler = ManualScheduler()
        let responder = ScriptedResponder()
        let household = HouseholdAwayController(store: store, responder: responder)
        let controller = VacationModeController(store: store, household: household, caller: caller, scheduler: scheduler,
                                                now: { TestClock.now }, calendar: TestClock.calendar)
        return Harness(controller: controller, store: store, caller: caller, scheduler: scheduler, responder: responder)
    }

    let allDone = Array(repeating: "on", count: 5)

    @Test func offWithIncompleteChecklistShowsTheChecklistAndBlocks() {
        let h = make(checklist: ["on", "off", "on", "on", "on"])
        let vacation = h.controller
        #expect(!vacation.cardEnabled)
        #expect(!vacation.showsInlineDates)
        #expect(vacation.cardSubtitle == "Off")
        #expect(!vacation.cardOpensSheet)
        vacation.tapCard()
        #expect(vacation.showsPreChecklistError)
        #expect(!vacation.isConfirming)
        // Finishing the checklist clears the error.
        vacation.toggle(Vacation.checklist[1])
        #expect(vacation.isChecked(Vacation.checklist[1]))
        #expect(vacation.checklistComplete)
        #expect(!vacation.blockedEnableAttempted)
        #expect(!vacation.showsPreChecklistError)
    }

    @Test func checklistTogglesAreExplicitAndOptimistic() async {
        let h = make(checklist: allDone)
        h.controller.toggle(Vacation.checklist[0])
        #expect(!h.controller.isChecked(Vacation.checklist[0]))
        await h.controller.drain()
        #expect(h.caller.calls == [.init(domain: "input_boolean", service: "turn_off", data: ["entity_id": Vacation.checklist[0].entityId])])
        // No echo: the optimistic value reverts.
        h.scheduler.fireAll()
        #expect(h.controller.isChecked(Vacation.checklist[0]))
    }

    @Test func unavailableChecklistRowsDoNothing() async {
        let h = make(checklist: ["unavailable", "on", "on", "on", "on"])
        #expect(h.controller.isUnavailable(Vacation.checklist[0]))
        h.controller.toggle(Vacation.checklist[0])
        await h.controller.drain()
        #expect(h.caller.calls.isEmpty)
        #expect(!h.controller.checklistComplete)
    }

    @Test func enablingAsksForDatesThenConfirms() async {
        let h = make(checklist: allDone)
        let vacation = h.controller
        #expect(vacation.cardOpensSheet)
        vacation.tapCard()
        #expect(vacation.isConfirming)
        #expect(vacation.cardSubtitle == "Pending")
        #expect(vacation.dateRange == .makeDefault(now: TestClock.now, calendar: TestClock.calendar))
        let picked = Vacation.DateRange(start: WallClock(date: "2026-11-01", time: "06:00"), end: WallClock(date: "2026-11-08", time: "22:00"))
        vacation.updatePendingRange(picked)
        #expect(vacation.dateRange == picked)
        vacation.confirm()
        #expect(!vacation.isConfirming)
        #expect(vacation.modeOn)
        #expect(vacation.showsInlineDates)
        await vacation.drain()
        #expect(h.caller.calls.map(\.service) == ["set_datetime", "set_datetime", "turn_off", "turn_on"])
        #expect(h.caller.calls[0].data["date"] == "2026-11-01")
        #expect(h.caller.calls[1].data["time"] == "22:00:00")
    }

    @Test func tappingWhileConfirmingCancels() {
        let h = make(checklist: allDone)
        h.controller.tapCard()
        h.controller.tapCard()
        #expect(!h.controller.isConfirming)
        h.controller.tapCard()
        h.controller.cancelConfirmation()
        #expect(!h.controller.isConfirming)
        // Edits outside the sheet are ignored.
        h.controller.updatePendingRange(.makeDefault())
        #expect(!h.controller.isConfirming)
    }

    @Test func invalidPendingRangeCannotConfirm() async {
        let h = make(checklist: allDone)
        h.controller.tapCard()
        h.controller.updatePendingRange(Vacation.DateRange(start: WallClock(date: "2026-11-08", time: "06:00"), end: WallClock(date: "2026-11-01", time: "06:00")))
        #expect(h.controller.invalidDateRange)
        #expect(!h.controller.recoveringInvalidDates)
        h.controller.confirm()
        await h.controller.drain()
        #expect(h.caller.calls.isEmpty)
        #expect(h.controller.isConfirming)
    }

    @Test func disablingResetsEverything() async {
        let h = make(mode: "on", checklist: allDone)
        let vacation = h.controller
        #expect(vacation.cardEnabled)
        #expect(vacation.showsInlineDates)
        #expect(vacation.cardSubtitle == "On")
        vacation.tapCard()
        #expect(!vacation.modeOn)
        await vacation.drain()
        #expect(h.caller.calls.count == 7)
        #expect(h.caller.calls.allSatisfy { $0.service == "turn_off" })
    }

    @Test func liveChangeClearsTheOptimisticValue() async {
        let h = make(mode: "on", checklist: allDone)
        h.controller.tapCard()
        #expect(!h.controller.modeOn)
        h.store.apply([EntityState(entityId: Vacation.modeEntityId, state: "off")])
        await Task.yield()
        await Task.yield()
        #expect(h.scheduler.pending.isEmpty || !h.controller.modeOn)
        #expect(!h.controller.modeOn)
    }

    @Test func inlineDateChangesSaveOneHelper() async {
        let h = make(mode: "on")
        let range = h.controller.savedRange
        var changed = range
        changed.end = WallClock(date: "2026-10-30", time: "18:00")
        h.controller.updateSavedRange(changed, changedEnd: true)
        changed.start = WallClock(date: "2026-10-21", time: "09:00")
        h.controller.updateSavedRange(changed, changedEnd: false)
        await h.controller.drain()
        #expect(h.caller.calls.map { $0.data["entity_id"] } == [Vacation.endEntityId, Vacation.startEntityId])
    }

    @Test func fixingPausedDatesReenables() async {
        let h = make(mode: "off", invalidPending: "on", start: "2026-10-27 09:00:00", end: "2026-10-20 09:00:00")
        let vacation = h.controller
        #expect(vacation.invalidDateRange)
        #expect(vacation.recoveringInvalidDates)
        #expect(vacation.cardEnabled)
        #expect(vacation.cardDisabled)
        vacation.tapCard()
        var fixed = vacation.savedRange
        fixed.end = WallClock(date: "2026-11-02", time: "09:00")
        vacation.updateSavedRange(fixed, changedEnd: true)
        await vacation.drain()
        #expect(h.caller.calls.map(\.service) == ["set_datetime", "turn_on", "turn_off"])
    }

    @Test func pastDatesDoNotReenable() async {
        let h = make(mode: "off", invalidPending: "on", start: "2026-10-01 09:00:00", end: "2026-10-02 09:00:00")
        var range = h.controller.savedRange
        range.start = WallClock(date: "2026-10-01", time: "08:00")
        h.controller.updateSavedRange(range, changedEnd: false)
        await h.controller.drain()
        #expect(h.caller.calls.map(\.service) == ["set_datetime"])
    }

    @Test func unavailableModeDisablesTheCard() {
        let h = make(mode: "unavailable", checklist: allDone)
        #expect(h.controller.modeUnavailable)
        #expect(h.controller.cardDisabled)
        #expect(h.controller.cardSubtitle == "Unavailable")
        h.controller.tapCard()
        #expect(!h.controller.isConfirming)
    }

    @Test func backendVacationAndSoloTrip() {
        let backend = make(away: awayEntity("active", awayAttributes(mode: "vacation")))
        #expect(backend.controller.backendVacationEngaged)
        #expect(backend.controller.cardEnabled)
        let solo = make(away: awayEntity("active", awayAttributes(mode: "solo_trip", traveler: "steph")))
        #expect(solo.controller.soloTripEngaged)
    }
}
