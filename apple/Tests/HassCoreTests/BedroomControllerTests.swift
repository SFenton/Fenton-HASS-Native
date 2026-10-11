import Foundation
@testable import HassCore
import Testing

// MARK: - Test double

/// Records calls and answers response-checked commands from a queue (default `accepted`).
@MainActor
final class ResponseCaller: HassServiceResponding {
    struct Call {
        var domain: String
        var service: String
        var data: [String: any Sendable]
        var name: String { "\(domain).\(service)" }
    }

    var calls: [Call] = []
    var responses: [JSONValue] = []
    var fail = false
    /// Suspends response-checked calls until ``release()``.
    var hold = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    struct Failure: Error {}

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        calls.append(Call(domain: domain, service: service, data: data))
        if fail { throw Failure() }
    }

    func callServiceWithResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        calls.append(Call(domain: domain, service: service, data: data))
        if hold { await withCheckedContinuation { waiting.append($0) } }
        if fail { throw Failure() }
        return responses.isEmpty ? .object(["outcome": "accepted"]) : responses.removeFirst()
    }

    func release() {
        hold = false
        let continuations = waiting
        waiting.removeAll()
        continuations.forEach { $0.resume() }
    }

    var names: [String] { calls.map(\.name) }
}

@MainActor
func bedroomStore(_ entities: [EntityState]) -> EntityStore {
    let store = EntityStore()
    store.replaceAll(entities)
    return store
}

@MainActor
func update(_ store: EntityStore, _ id: String, _ change: (inout EntityState) -> Void) {
    var entity = store.value(id) ?? EntityState(entityId: id, state: "unknown")
    change(&entity)
    store.apply([entity])
}

/// Stephen's side on, in the asleep stage, at +3, with Monday and Tuesday 07:00 alarms.
@MainActor
func bedEntities(phase: String = "asleep", away: EntityState? = nil) -> [EntityState] {
    let bed = MasterBedroom.stephensBed
    let range: [String: JSONValue] = ["min": .number(-10), "max": .number(10), "step": .number(1)]
    func alarm(_ time: String) -> JSONValue { .object(["time": .string(time), "enabled": true]) }
    var entities = [
        EntityState(entityId: bed.climateEntityId, state: "auto", attributes: ["current_temperature": .number(90.5), "temperature": .number(90.75)]),
        EntityState(entityId: bed.targetLevelEntityId, state: "3", attributes: range),
        EntityState(entityId: bed.schedulePhaseEntityId, state: phase),
        EntityState(entityId: bed.stageLevelEntityIds[.bedtime]!, state: "4", attributes: range),
        EntityState(entityId: bed.stageLevelEntityIds[.asleep]!, state: "3", attributes: range),
        EntityState(entityId: bed.stageLevelEntityIds[.dawn]!, state: "1", attributes: range),
        EntityState(entityId: bed.alarmStateEntityId, state: "idle"),
        EntityState(entityId: bed.hotFlashActiveEntityId, state: "off"),
        EntityState(entityId: MasterBedroom.scheduleEntityId, state: "ok", attributes: [
            "left": .object(["monday": .object(["alarms": .array([alarm("07:00")])]), "tuesday": .object(["alarms": .array([alarm("07:00")])])]),
            "right": .object([:]),
        ]),
        wakeStatus(),
    ]
    if let away { entities.append(away) }
    return entities
}

@MainActor
func soloTrip(home: String = "stephen") -> EntityState {
    EntityState(entityId: MasterBedroom.householdAwayEntityId, state: "active", attributes: [
        "mode": "solo_trip", "traveler": home == "stephen" ? "steph" : "stephen", "home_resident": .string(home), "revision": .number(5),
        "effects": .object(["wake_light_source": true, "sleepypod_schedule": true, "sleepypod_live_follow": true]),
    ])
}

// MARK: - Wake light

@Suite("Wake light controller")
@MainActor
struct WakeLightControllerTests {
    let scheduler = ManualScheduler()
    let caller = ResponseCaller()

    func make(_ status: EntityState = wakeStatus()) -> (WakeLightController, EntityStore) {
        let store = bedroomStore([status])
        return (WakeLightController(config: MasterBedroom.wakeLight, store: store, caller: caller, scheduler: scheduler, requestId: { "req" }), store)
    }

    @Test func savesWithOptimisticEditAndSendsTheCommand() async {
        let (controller, _) = make()
        var alarm = controller.snapshot.alarms[0]
        alarm.enabled = false
        caller.hold = true
        let task = Task { await controller.save(alarm) }
        await Task.yield()
        #expect(controller.snapshot.alarms[0].enabled == false)
        #expect(controller.isPending(alarmId: "a"))
        #expect(controller.configurationPending)
        caller.release()
        #expect(await task.value)
        #expect(!controller.isPending(alarmId: "a"))
        #expect(caller.names == ["wake_light.command"])
        #expect(caller.calls[0].data["operation"] as? String == "upsert_alarm")
        #expect(caller.calls[0].data["expected_revision"] as? Int == 7)
        // Still shown until the revert timer lets Home Assistant's state win.
        #expect(controller.snapshot.alarms[0].enabled == false)
        scheduler.fireAll()
        #expect(controller.snapshot.alarms[0].enabled == true)
    }

    @Test func rejectedCommandRollsBackAndShowsTheError() async {
        let (controller, _) = make()
        caller.responses = [.object(["outcome": "rejected", "error_code": "revision_conflict", "conflict": "alarm_revision", "revision": .number(9)])]
        #expect(await controller.delete(alarmId: "a") == false)
        #expect(controller.snapshot.alarms.map(\.id) == ["a", "b"])
        #expect(controller.errorCode == "revision_conflict")
        #expect(controller.requiresAlarmReload)
        #expect(controller.error?.contains("changed elsewhere") == true)
        controller.clearError()
        #expect(controller.error == nil && !controller.requiresAlarmReload)
        // The next command expects the newer revision the rejection reported.
        await controller.updateDefaults(.standard)
        #expect(caller.calls.last?.data["expected_revision"] as? Int == 9)
    }

    @Test func noChangeRollsBackSilently() async {
        let (controller, _) = make()
        caller.responses = [.object(["outcome": "no_change", "revision": .number(7)])]
        #expect(await controller.updateDefaults(WakeLight.Defaults(rampMinutes: 5, postWakeHoldMinutes: 5)))
        #expect(controller.snapshot.defaults.rampMinutes == 15)
        #expect(controller.error == nil)
    }

    @Test func transportFailureRollsBack() async {
        let (controller, _) = make()
        caller.fail = true
        #expect(await controller.setLinks(["sleepypod:left#monday#06:30"], enabled: false) == false)
        #expect(controller.snapshot.isLinked("sleepypod:left#monday#06:30"))
        #expect(controller.errorCode == "transport")
        caller.responses = [.object([:])]
        caller.fail = false
        #expect(await controller.setLinks(["k"], enabled: false) == false)
        #expect(controller.errorCode == "transport")
        #expect(await controller.setLinks([], enabled: true))
    }

    @Test func refusesWhileUnavailableOrWithoutAnEpisode() async {
        let (controller, store) = make()
        #expect(await controller.endEpisode() == false)
        #expect(controller.errorCode == "unavailable")
        update(store, MasterBedroom.wakeLight.statusEntityId) { $0.attributes["command_available"] = false }
        #expect(await controller.save(controller.snapshot.alarms[0]) == false)
        #expect(caller.calls.isEmpty)
    }

    @Test func endEpisodeClearsOccurrencesAndJumpsTheQueue() async {
        let (controller, _) = make(wakeStatus(state: "ramping", [
            "episode_ref": "ep",
            "active_occurrences": .array([.object(["occurrence_id": "o", "alarm_id": "a", "wake_at": "2026-10-12T06:45:00Z"])]),
        ]))
        #expect(controller.snapshot.activeOccurrences.count == 1)
        caller.hold = true
        let save = Task { await controller.save(controller.snapshot.alarms[0]) }
        await Task.yield()
        let stop = Task { await controller.endEpisode() }
        await Task.yield()
        await Task.yield()
        #expect(controller.stopping)
        #expect(controller.snapshot.activeOccurrences.isEmpty)
        #expect(caller.names.count == 2)
        caller.release()
        #expect(await stop.value)
        #expect(await save.value)
        // A duplicate command for the same keys is ignored while one is in flight.
        caller.hold = true
        let first = Task { await controller.save(controller.snapshot.alarms[0]) }
        await Task.yield()
        #expect(await controller.save(controller.snapshot.alarms[0]) == false)
        caller.release()
        _ = await first.value
    }
}

// MARK: - Bed side

@Suite("Bed side controller")
@MainActor
struct BedSideControllerTests {
    let scheduler = ManualScheduler()
    let caller = ResponseCaller()

    func make(_ entities: [EntityState] = bedEntities()) -> (BedSideController, EntityStore) {
        let store = bedroomStore(entities)
        return (BedSideController(config: MasterBedroom.stephensBed, store: store, caller: caller, scheduler: scheduler, requestId: { "req" }), store)
    }

    @Test func readsTheSide() {
        let (bed, _) = make()
        #expect(bed.sideAvailable && bed.isOn)
        #expect(bed.displayedTarget == 3)
        #expect(bed.currentLevel == 3)
        #expect(bed.action == "heating")
        #expect(bed.subtitle == "Heating • +3")
        #expect(bed.tileSubtitle() == "Heating • +3")
        #expect(bed.title == "Stephen's Bed")
        #expect(bed.activePhase == .asleep)
        #expect(bed.canSetTarget && bed.canTogglePower)
        #expect(bed.hint == "Drag the dial to set the target.")
        #expect(bed.powerTitle == "Turn Off")
        #expect(bed.stageLevel(.bedtime) == 4)
        #expect(bed.alarms.count == 2)
        #expect(bed.alarmGroups.map(\.day) == [.monday, .tuesday])
        #expect(bed.alarmState == .idle)
    }

    @Test func targetDuringAStageSetsTonightThenAsks() async {
        let (bed, store) = make()
        bed.setTarget(5.2)
        #expect(bed.displayedTarget == 5)
        #expect(bed.scopeRequest == BedSideController.ScopeRequest(phase: .asleep, level: 5, targetText: "+5"))
        await bed.waitForCalls()
        #expect(caller.names == ["script.sleepypod_stephen_temperature_tonight"])
        #expect(caller.calls[0].data["level"] as? Double == 5)
        bed.chooseScope(.allNights)
        #expect(bed.scopeRequest == nil)
        #expect(bed.stageLevel(.asleep) == 5)
        await bed.waitForCalls()
        #expect(caller.calls.last?.name == "input_number.set_value")
        #expect(caller.calls.last?.data["entity_id"] as? String == "input_number.eight_sleep_stephen_asleep_level")
        // Home Assistant confirms the target.
        update(store, MasterBedroom.stephensBed.targetLevelEntityId) { $0.state = "5" }
        bed.liveDidChange()
        #expect(bed.displayedTarget == 5)
    }

    @Test func tonightOnlyChangesNothingElse() async {
        let (bed, _) = make()
        bed.setTarget(4)
        bed.chooseScope(.tonight)
        await bed.waitForCalls()
        #expect(caller.names == ["script.sleepypod_stephen_temperature_tonight"])
        bed.setTarget(3)
        #expect(bed.scopeRequest != nil)
        bed.dismissScope()
        #expect(bed.scopeRequest == nil)
    }

    @Test func targetOutsideTheScheduleUsesTheOutsideScript() async {
        let (bed, _) = make(bedEntities(phase: "outside"))
        bed.setTarget(-2)
        await bed.waitForCalls()
        #expect(caller.names == ["script.sleepypod_stephen_temperature_outside_schedule"])
        #expect(bed.scopeRequest == nil)
        bed.setTarget(3)
        #expect(caller.calls.count == 1)
    }

    @Test func phaseChangeDropsThePendingTargetAndQuestion() {
        let (bed, store) = make()
        bed.setTarget(6)
        update(store, MasterBedroom.stephensBed.schedulePhaseEntityId) { $0.state = "dawn" }
        bed.liveDidChange()
        #expect(bed.scopeRequest == nil)
        #expect(bed.displayedTarget == 3)
    }

    @Test func failedCallRevertsThePower() async {
        let (bed, _) = make()
        caller.fail = true
        bed.setPower(on: false)
        #expect(!bed.isOn)
        #expect(bed.subtitle == "Off")
        await bed.waitForCalls()
        #expect(bed.isOn)
        #expect(caller.calls[0].data["action"] as? String == "power_off")
        #expect(caller.calls[0].data["side"] as? String == "left")
    }

    @Test func unavailableSideHoldsBrieflyThenLocks() {
        let (bed, store) = make()
        update(store, MasterBedroom.stephensBed.climateEntityId) { $0.state = "unavailable" }
        bed.liveDidChange()
        #expect(bed.sideAvailable)
        scheduler.fireAll()
        #expect(!bed.sideAvailable)
        #expect(bed.hint == "Bed controls are unavailable.")
        #expect(bed.powerTitle == "Unavailable")
        bed.setPower(on: true)
        bed.setTarget(1)
        #expect(caller.calls.isEmpty)
    }

    @Test func stageSteppersBatchThenPublishTheSchedule() async {
        let (bed, _) = make(bedEntities(phase: "outside"))
        bed.stepStage(.bedtime, up: true)
        bed.stepStage(.bedtime, up: true)
        #expect(bed.stageLevel(.bedtime) == 6)
        #expect(caller.calls.isEmpty)
        scheduler.pending.filter { $0.delay == BedSideController.stageDebounce }.forEach { item in
            item.cancelled = true
            item.work()
        }
        await bed.waitForCalls()
        #expect(caller.names == ["input_number.set_value", "mqtt.publish"])
        #expect(caller.calls[0].data["value"] as? Double == 6)
        let payload = caller.calls[1].data["payload"] as? String
        #expect(payload?.contains("\"onTemperature\":99") == true)
        #expect(caller.calls[1].data["topic"] as? String == "sleepypod/eight-pod/cmd/set-schedules")
    }

    @Test func steppingTheRunningStageGoesThroughTonight() async {
        let (bed, _) = make()
        bed.stepStage(.asleep, up: false)
        scheduler.pending.filter { $0.delay == BedSideController.stageDebounce }.forEach { $0.cancelled = true; $0.work() }
        await bed.waitForCalls()
        #expect(caller.names == ["script.sleepypod_stephen_temperature_tonight"])
        #expect(bed.scopeRequest?.level == 2)
    }

    @Test func hotFlashShowsTheBottomOfTheScale() async {
        let (bed, store) = make()
        bed.startHotFlash()
        #expect(bed.hotFlashActive)
        #expect(bed.displayedTarget == -10)
        #expect(bed.subtitle == "Hot Flash Mode")
        #expect(!bed.canSetTarget)
        #expect(bed.hint == "Hot Flash Mode controls the target.")
        await bed.waitForCalls()
        #expect(caller.calls[0].data["entity_id"] as? String == "input_button.eight_sleep_stephen_hot_flash")
        let finishes = Date.now.addingTimeInterval(125)
        update(store, MasterBedroom.stephensBed.hotFlashActiveEntityId) { $0.state = "on" }
        update(store, MasterBedroom.stephensBed.hotFlashTimerEntityId) {
            $0.state = "active"
            $0.attributes["finishes_at"] = .string(ISO8601DateFormatter().string(from: finishes))
        }
        bed.liveDidChange()
        #expect(bed.hotFlashCountdown(now: finishes.addingTimeInterval(-65)) == "1:05")
        #expect(bed.tileSubtitle(now: finishes.addingTimeInterval(-65)) == "1:05 Remaining")
        bed.cancelHotFlash()
        #expect(!bed.hotFlashActive)
        await bed.waitForCalls()
        #expect(caller.calls.last?.data["entity_id"] as? String == "input_button.eight_sleep_stephen_cancel_hot_flash")
    }

    @Test func snoozeAndStopTheRingingAlarm() async {
        let (bed, store) = make()
        update(store, MasterBedroom.stephensBed.alarmStateEntityId) { $0.state = "ringing" }
        bed.liveDidChange()
        #expect(bed.alarmState == .ringing)
        let now = Date(timeIntervalSince1970: 10_000)
        bed.snoozeAlarm(now: now)
        #expect(bed.alarmState == .snoozed)
        #expect(bed.snoozeRemaining(now: now.addingTimeInterval(1)) == "4:59 Remaining")
        bed.stopAlarm()
        #expect(bed.alarmState == .idle)
        await bed.waitForCalls()
        #expect(caller.calls.map { $0.data["entity_id"] as? String } == [
            "button.master_bedroom_sleepypod_eight_pod_left_alarm_snooze", "button.master_bedroom_sleepypod_eight_pod_left_alarm_stop",
        ])
    }

    @Test func soloTripRoutesThroughHouseholdAway() async {
        let (bed, _) = make(bedEntities(phase: "outside", away: soloTrip()))
        #expect(bed.title == "Stephen's Bed · Whole Bed")
        #expect(bed.tileSubtitle() == "Whole Bed • Heating • +3")
        bed.setTarget(1)
        bed.setPower(on: false)
        await bed.waitForCalls()
        #expect(caller.names == ["script.household_away_command", "script.household_away_command"])
        #expect(caller.calls[0].data["action"] as? String == "set_outside_level")
        #expect(caller.calls[0].data["expected_revision"] as? Int == 5)
        #expect(caller.calls[1].data["enabled"] as? Bool == false)
    }

    @Test func refusedSoloTripCommandRollsBack() async {
        let (bed, _) = make(bedEntities(phase: "outside", away: soloTrip()))
        caller.responses = [.object(["outcome": "rejected", "error_code": "revision_conflict"])]
        bed.setTarget(-4)
        await bed.waitForCalls()
        #expect(bed.displayedTarget == 3)
        #expect(bed.commandError == "Home Assistant could not apply the Solo Trip change. Try again.")
    }

    @Test func travelerSideIsReadOnly() async {
        let (bed, _) = make(bedEntities(away: soloTrip(home: "steph")))
        #expect(bed.tileSubtitle() == "Away · Read Only")
        #expect(!bed.canSetTarget && !bed.canTogglePower && !bed.alarmsEditable && bed.alarmControlsReadOnly)
        #expect(bed.hint == "Away · Read Only")
        bed.snoozeAlarm()
        bed.startHotFlash()
        #expect(caller.calls.isEmpty)
        #expect(bed.problems(bed.newAlarmDraft()).contains("Away · Read Only"))
    }

    @Test func alarmEditsAreBatchedAndConfirmed() async {
        let (bed, store) = make()
        let monday = bed.alarms[0]
        #expect(bed.setEnabled(monday, false))
        #expect(bed.alarms[0].enabled == false)
        #expect(caller.calls.isEmpty)
        scheduler.pending.filter { $0.delay == BedSideController.alarmDebounce }.forEach { $0.cancelled = true; $0.work() }
        await bed.waitForCalls()
        #expect(caller.names == ["mqtt.publish"])
        let text = caller.calls[0].data["payload"] as? String ?? ""
        let payload = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        #expect(payload?["left"]?["monday"]?["alarms"]?.array?.first?["enabled"] == false)
        // Home Assistant echoes the new list: the optimistic copy gives way.
        update(store, MasterBedroom.scheduleEntityId) { entity in
            if let payload, case var .object(left)? = entity.attributes["left"], case let .object(days)? = payload["left"] {
                for (day, value) in days { left[day] = value }
                entity.attributes["left"] = .object(left)
            }
        }
        bed.liveDidChange()
        #expect(bed.alarms.first { $0.day == .monday }?.enabled == false)
        #expect(bed.setEnabled(bed.alarms[0], false))
    }

    @Test func someoneElsesChangeDropsTheOptimisticList() {
        let (bed, store) = make()
        bed.setEnabled(bed.alarms[0], false)
        update(store, MasterBedroom.scheduleEntityId) { entity in
            entity.attributes["left"] = .object(["friday": .object(["alarms": .array([.object(["time": "09:00", "enabled": true])])])])
        }
        bed.liveDidChange()
        #expect(bed.alarms.map(\.day) == [.friday])
    }

    @Test func savingAnAlarmLinksTheWakeLightFirst() async {
        let entities = bedEntities()
        let store = bedroomStore(entities)
        let bed = BedSideController(config: MasterBedroom.stephensBed, store: store, caller: caller, scheduler: scheduler, requestId: { "req" })
        let wake = WakeLightController(config: MasterBedroom.wakeLight, store: store, caller: caller, scheduler: scheduler, requestId: { "req" })
        var draft = bed.newAlarmDraft()
        #expect(draft.days == Weekday.workdays)
        #expect(draft.title == "Add Stephen's Bed Alarm")
        draft.days = [.wednesday]
        draft.time = "06:15"
        #expect(await bed.save(draft, wakeLight: wake))
        #expect(caller.names == ["wake_light.command"])
        #expect(caller.calls[0].data["link_keys"] as? [String] == ["sleepypod:left#wednesday#06:15"])
        #expect(bed.alarms.count == 3)
        // A refused link saves nothing.
        caller.responses = [.object(["outcome": "rejected", "error_code": "x"])]
        draft.days = [.thursday]
        #expect(await bed.save(draft, wakeLight: wake) == false)
        #expect(bed.alarms.count == 3)
    }

    @Test func editAndDeleteDrafts() async {
        let store = bedroomStore(bedEntities())
        let bed = BedSideController(config: MasterBedroom.stephensBed, store: store, caller: caller, scheduler: scheduler, requestId: { "req" })
        let wake = WakeLightController(config: MasterBedroom.wakeLight, store: store, caller: caller, scheduler: scheduler, requestId: { "req" })
        let alarm = bed.alarms[0]
        var draft = bed.editDraft(alarm, wakeLight: wake.snapshot)
        #expect(draft.title == "Stephen's Bed Monday Alarm")
        #expect(draft.wakeLightEnabled)
        #expect(draft.lockedDay == .monday)
        draft.time = "bad"
        #expect(bed.problems(draft) == ["Choose a valid alarm time."])
        draft.time = "08:00"
        #expect(await bed.save(draft, wakeLight: nil))
        #expect(bed.alarms.contains { $0.day == .monday && $0.time == "08:00" })
        let edited = bed.alarms.first { $0.day == .monday }!
        draft = bed.editDraft(edited, wakeLight: nil)
        #expect(await bed.delete(draft, wakeLight: wake))
        #expect(!bed.alarms.contains { $0.day == .monday })
        #expect(caller.calls.last?.data["enabled"] as? Bool == false)
        #expect(bed.isStale(draft))
        var empty = bed.newAlarmDraft(lockedDay: .sunday)
        #expect(empty.title == "Add Stephen's Bed Sunday Alarm")
        empty.days = []
        #expect(bed.problems(empty) == ["Select at least one day."])
    }

    @Test func createsAlarmsForTheWakeLight() async {
        let (bed, _) = make()
        bed.createAlarms(days: [.friday], time: "6:30")
        bed.createAlarms(days: [], time: "06:30")
        await bed.waitForCalls()
        #expect(caller.names == ["mqtt.publish"])
        #expect((caller.calls[0].data["payload"] as? String)?.contains("06:30") == true)
    }
}

// MARK: - Room

@Suite("Bedroom devices")
@MainActor
struct BedroomDevicesTests {
    @Test func newWeeklyWakeAlarmAddsBedAlarmsAndLinks() async {
        let caller = ResponseCaller()
        let store = bedroomStore(bedEntities())
        let devices = BedroomDevices(store: store, caller: caller, scheduler: ManualScheduler(), requestId: { "req" })
        #expect(devices.bedTargets.map(\.available) == [true, true])
        #expect(devices.bed(source: "sleepypod:right")?.config.side == .right)
        let alarm = WakeLight.Alarm(id: "n", label: " New ", kind: .weekly, localTime: "07:00", weekdays: [.monday, .friday])
        #expect(await devices.saveWakeAlarm(alarm, isNew: true, addToBeds: [.left]))
        await devices.bed(.left).waitForCalls()
        #expect(caller.names.contains("mqtt.publish"))
        let upsert = caller.calls.first { $0.data["operation"] as? String == "upsert_alarm" }
        #expect((upsert?.data["alarm"] as? [String: any Sendable])?["label"] as? String == "New")
        // Friday is missing on Stephen's side; Steph's side is off and has no alarms at 07:00, so nothing happens there.
        let publish = caller.calls.first { $0.name == "mqtt.publish" }
        #expect((publish?.data["payload"] as? String)?.contains("\"friday\":{\"alarms\":[{") == true)
    }

    @Test func oneTimeAlarmCarriesBedSides() async {
        let caller = ResponseCaller()
        let devices = BedroomDevices(store: bedroomStore(bedEntities()), caller: caller, scheduler: ManualScheduler(), requestId: { "req" })
        let alarm = WakeLight.Alarm(id: "o", label: "Trip", kind: .once, localTime: "05:00", date: "2030-01-01")
        #expect(await devices.saveWakeAlarm(alarm, isNew: true, addToBeds: [.right]))
        #expect(caller.calls.count == 1)
        #expect((caller.calls[0].data["alarm"] as? [String: any Sendable])?["bed_sides"] as? [String] == ["right"])
        caller.responses = [.object(["outcome": "rejected"])]
        #expect(await devices.saveWakeAlarm(alarm, isNew: false, addToBeds: []) == false)
    }
}
