import Foundation
@testable import HassCore
import Testing

/// The bathroom fan's command matrix and optimistic rules (web `bathroomFanState.test.ts`,
/// `BathroomFanModalContent.test.tsx`).
@MainActor
struct BathroomFanControllerTests {
    let fan = BathroomFanConfig.guest

    func controller(power: String = "on", locked: Bool = false, pending: Bool = false, autoUnlock: Bool = false,
                    deadline: [String: JSONValue] = [:], deadlineState: String = "2026-10-11 12:00:00")
        -> (BathroomFanController, EntityStore, RecordingCaller, ManualScheduler)
    {
        let store = makeStore([
            fan.powerEntityId: power,
            fan.lockEntityId: locked ? "on" : "off",
            fan.pendingEntityId: pending ? "on" : "off",
            fan.autoUnlockEntityId: autoUnlock ? "on" : "off",
            fan.deadlineEntityId: deadlineState,
        ], attributes: [fan.deadlineEntityId: deadline])
        let caller = RecordingCaller()
        let scheduler = ManualScheduler()
        return (BathroomFanController(config: fan, store: store, caller: caller, scheduler: scheduler), store, caller, scheduler)
    }

    func script(_ data: [String: String]) -> RecordingCaller.Call {
        .init(domain: "script", service: "guest_bathroom_fan_command", data: data)
    }

    // MARK: Contract

    @Test func keepsTheExactEntityContract() {
        #expect(BathroomFanConfig.master.powerEntityId == "switch.master_bathroom_fan_switch_top")
        #expect(BathroomFanConfig.master.scriptService == "master_bathroom_fan_command")
        #expect(BathroomFanConfig.guest.deadlineEntityId == "input_datetime.guest_bathroom_fan_timer_ends_at")
        #expect(BathroomFanConfig.forPowerEntity("switch.guest_bathroom_fan_switch_top") == .guest)
        #expect(BathroomFanConfig.forPowerEntity("switch.other") == nil)
    }

    @Test func timerMinutesSnapToTheOfferedLengths() {
        #expect(BathroomFanController.normalizedMinutes(5) == 5)
        #expect(BathroomFanController.normalizedMinutes(7) == 5)
        #expect(BathroomFanController.normalizedMinutes(44) == 30)
        #expect(BathroomFanController.normalizedMinutes(46) == 60)
        #expect(BathroomFanController.normalizedMinutes(500) == 60)
        #expect(BathroomFanController.durationTitle(60) == "1 hour")
        #expect(BathroomFanController.durationTitle(15) == "15 minutes")
    }

    // MARK: Commands

    @Test func powerOffAlsoShowsTimerLockAndAutoUnlockCleared() async {
        let (fanController, _, caller, _) = controller(power: "on", locked: true, pending: true, autoUnlock: true)
        fanController.setPower(false)
        #expect(!fanController.powerOn && !fanController.timerPending && !fanController.locked && !fanController.autoUnlock)
        await fanController.commands.waitForCalls()
        #expect(caller.calls == [script(["command": "power", "target_power": "off"])])
    }

    @Test func unchangedOrUnavailableCommandsAreSkipped() async {
        let (onFan, _, caller, _) = controller(power: "on")
        onFan.setPower(true)
        onFan.setLocked(false)
        onFan.cancelTimer()
        onFan.setAutoUnlock(true)
        await onFan.commands.waitForCalls()
        #expect(caller.calls.isEmpty)

        let (missing, _, missingCaller, _) = controller(power: "unavailable")
        #expect(!missing.powerAvailable)
        #expect(missing.powerStateText == "Unavailable")
        missing.setPower(true)
        missing.startTimer()
        await missing.commands.waitForCalls()
        #expect(missingCaller.calls.isEmpty)
    }

    @Test func lockingDuringATimerTurnsAutoUnlockOn() async {
        let (fanController, _, caller, _) = controller(pending: true)
        fanController.setLocked(true)
        #expect(fanController.locked && fanController.autoUnlock)
        #expect(fanController.lockStateText == "Locked")
        await fanController.commands.waitForCalls()
        #expect(caller.calls == [script(["command": "lock", "locked": "true"])])
    }

    @Test func startTimerSendsSnappedMinutesAndAutoUnlockOnlyWhileLocked() async {
        let (unlocked, _, caller, _) = controller()
        unlocked.selectedMinutes = 20
        #expect(unlocked.canStartTimer)
        #expect(!unlocked.displayedAutoUnlock, "Defaults to the lock state")
        unlocked.startTimer()
        #expect(unlocked.timerPending)
        await unlocked.commands.waitForCalls()
        #expect(caller.calls == [script(["auto_unlock": "false", "command": "timer_start", "minutes": "20"])])

        let (locked, _, lockedCaller, _) = controller(locked: true)
        #expect(locked.displayedAutoUnlock && locked.showsAutoUnlock)
        locked.startTimer()
        #expect(locked.autoUnlock)
        await locked.commands.waitForCalls()
        #expect(lockedCaller.calls == [script(["auto_unlock": "true", "command": "timer_start", "minutes": "30"])])
    }

    @Test func idleAutoUnlockChoiceIsLocalAndResetsWhenTheSituationChanges() async {
        let (fanController, store, caller, _) = controller(locked: true)
        fanController.setAutoUnlock(false)
        #expect(!fanController.displayedAutoUnlock)
        await fanController.commands.waitForCalls()
        #expect(caller.calls.isEmpty, "The idle choice stays local")

        // Unlocking changes the situation, so the next lock defaults back to on.
        set(store, fan.lockEntityId, "off")
        #expect(!fanController.displayedAutoUnlock)
        for _ in 0..<20 { await Task.yield() }
        set(store, fan.lockEntityId, "on")
        for _ in 0..<20 { await Task.yield() }
        #expect(fanController.displayedAutoUnlock)
    }

    @Test func timerAutoUnlockAndCancelGoToTheServerWhilePending() async {
        let (fanController, _, caller, _) = controller(locked: true, pending: true, autoUnlock: true)
        #expect(fanController.autoUnlockAvailable)
        fanController.setAutoUnlock(false)
        #expect(!fanController.displayedAutoUnlock)
        fanController.cancelTimer()
        #expect(!fanController.timerPending)
        await fanController.commands.waitForCalls()
        #expect(caller.calls == [
            script(["command": "timer_auto_unlock", "enabled": "false"]),
            script(["command": "timer_cancel"]),
        ])
    }

    // MARK: Optimistic values

    @Test func optimisticValuesClearOnLiveChangeOrAfterTwoSeconds() async {
        let (fanController, store, _, scheduler) = controller(power: "off")
        fanController.setPower(true)
        #expect(fanController.powerOn)
        scheduler.fireAll()
        #expect(!fanController.powerOn, "Reverts when Home Assistant never confirms")

        fanController.setPower(true)
        set(store, fan.powerEntityId, "on")
        for _ in 0..<20 where !fanController.commands.overlay.pending.isEmpty { await Task.yield() }
        #expect(fanController.powerOn)
        #expect(fanController.commands.overlay.pending.isEmpty)
    }

    @Test func aFailedCallDropsItsOptimisticValues() async {
        let (fanController, _, caller, _) = controller(power: "off")
        caller.failNext = true
        fanController.setPower(true)
        await fanController.commands.waitForCalls()
        #expect(!fanController.powerOn)
    }

    // MARK: Timer

    @Test func remainingTimeComesFromTheTimestampAttribute() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let (fanController, _, _, _) = controller(pending: true, deadline: ["timestamp": .number(1_000_000 + 754.2)])
        #expect(fanController.remainingSeconds(at: now) == 755)
        #expect(fanController.remainingSeconds(at: now.addingTimeInterval(10_000)) == 0)
        #expect(BathroomFanController.formatRemaining(755) == "12:35")
        #expect(BathroomFanController.formatRemaining(3_725) == "01:02:05")
        #expect(BathroomFanController.formatRemaining(-3) == "00:00")
    }

    @Test func remainingTimeFallsBackToTheLocalDateTimeState() throws {
        let (fanController, _, _, _) = controller(pending: true, deadlineState: "2026-10-11 12:30:00")
        let deadline = try #require(fanController.deadline)
        let parts = Calendar.current.dateComponents([.hour, .minute], from: deadline)
        #expect(parts.hour == 12 && parts.minute == 30)
        #expect(BathroomFanController.parseLocalDateTime("2026-10-11T12:30:00") == deadline)
        #expect(BathroomFanController.parseLocalDateTime("soon") == nil)
    }

    @Test func noRemainingTimeWithoutATimerOrDeadline() {
        let (idle, _, _, _) = controller(pending: false, deadline: ["timestamp": .number(2_000_000_000)])
        #expect(idle.remainingSeconds(at: Date()) == nil)
        let (unknown, _, _, _) = controller(pending: true, deadlineState: "unknown")
        #expect(unknown.remainingSeconds(at: Date()) == nil)
    }
}
