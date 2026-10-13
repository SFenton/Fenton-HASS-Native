import Foundation
import Observation

/// Drives one bathroom fan (web `useBathroomFanCommand.ts`, `bathroomFanState.ts`, `BathroomFanModalContent.tsx`).
///
/// Every command goes through the fan's script with a `command` field; Home Assistant runs the timer, lock and
/// auto-unlock logic. Power, lock, timer-pending and auto-unlock show optimistically and clear on any live change
/// or after 2 s, like the web.
@MainActor
@Observable
public final class BathroomFanController {
    /// Timer lengths offered, in minutes (`BATHROOM_FAN_TIMER_MINUTES`).
    public static let timerMinutes = [5, 10, 15, 20, 30, 60]
    /// The timer picker's starting value.
    public static let defaultTimerMinutes = 30
    /// Web `DEFAULT_OPTIMISTIC_REVERT_MS`.
    public static let revert: Duration = .seconds(2)

    public let config: BathroomFanConfig
    public let commands: RoomDeviceCommands

    /// The timer length picked in the sheet (local until Set).
    public var selectedMinutes = BathroomFanController.defaultTimerMinutes
    /// The auto-unlock choice while no timer runs (web `inactiveAutoUnlock`); dropped whenever the lock/timer
    /// situation changes, so it resets to "on when locked".
    private var idleAutoUnlock: Bool?
    @ObservationIgnored private var observedSituation = ""

    /// Creates a controller.
    public init(config: BathroomFanConfig, store: EntityStore, caller: any HassServiceCalling,
                scheduler: any RevertScheduler = TaskRevertScheduler()) {
        self.config = config
        var rules: [String: OptimisticOverlay.ClearRule] = [:]
        for id in config.optimisticEntityIds { rules[id] = .liveChange }
        commands = RoomDeviceCommands(store: store, caller: caller, rules: rules, scheduler: scheduler) { [store] id in
            DeviceState.binaryFlag(store.entity(id).state?.state)
        }
        observedSituation = situationKey
        observeSituation()
    }

    /// Drops the idle auto-unlock choice when the lock or timer changes, live or optimistically.
    private func observeSituation() {
        withObservationTracking {
            _ = situationKey
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let key = self.situationKey
                if key != self.observedSituation {
                    self.observedSituation = key
                    self.idleAutoUnlock = nil
                }
                self.observeSituation()
            }
        }
    }

    // MARK: - State

    private func flag(_ id: String) -> String { commands.displayed(id) ?? "unavailable" }

    public var powerAvailable: Bool { commands.live(config.powerEntityId) != "unavailable" }
    public var lockAvailable: Bool { commands.live(config.lockEntityId) != "unavailable" }
    public var timerAvailable: Bool { commands.live(config.pendingEntityId) != "unavailable" }
    var liveAutoUnlockAvailable: Bool { commands.live(config.autoUnlockEntityId) != "unavailable" }

    public var powerOn: Bool { flag(config.powerEntityId) == "on" }
    public var locked: Bool { flag(config.lockEntityId) == "on" }
    public var timerPending: Bool { flag(config.pendingEntityId) == "on" }
    /// Home Assistant's auto-unlock flag (meaningful while a timer runs).
    public var autoUnlock: Bool { flag(config.autoUnlockEntityId) == "on" }

    private var situationKey: String { "\(locked ? "locked" : "unlocked"):\(timerPending ? "active" : "idle")" }

    /// The auto-unlock checkbox's value: Home Assistant's while a timer runs, else the local choice
    /// (defaults to on while locked).
    public var displayedAutoUnlock: Bool {
        if timerPending { return autoUnlock }
        if let idleAutoUnlock, observedSituation == situationKey { return idleAutoUnlock }
        return locked
    }

    /// Whether the checkbox can be changed.
    public var autoUnlockAvailable: Bool { timerPending ? liveAutoUnlockAvailable : true }

    /// The checkbox shows only while locked and the fan is on or timed.
    public var showsAutoUnlock: Bool { locked && (powerOn || timerPending) }

    /// Set is enabled only while the fan is on.
    public var canStartTimer: Bool { powerAvailable && powerOn && timerAvailable }

    /// The subtitle for the power tile and the room tile: On, Off or Unavailable.
    public var powerStateText: String { powerAvailable ? (powerOn ? "On" : "Off") : "Unavailable" }

    /// Locked, Unlocked or Unavailable.
    public var lockStateText: String { lockAvailable ? (locked ? "Locked" : "Unlocked") : "Unavailable" }

    // MARK: - Timer

    /// When the pending timer ends, from the deadline helper (`timestamp` attribute, else the local date-time state).
    public var deadline: Date? {
        guard let entity = commands.entity(config.deadlineEntityId), !EntityState.isUnavailable(entity.state) else { return nil }
        if let timestamp = entity.attributes["timestamp"]?.number { return Date(timeIntervalSince1970: timestamp) }
        return Self.parseLocalDateTime(entity.state)
    }

    /// Seconds left at `now`, or `nil` when no timer runs or the deadline is unknown.
    public func remainingSeconds(at now: Date) -> Int? {
        guard timerPending, let deadline else { return nil }
        return max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
    }

    /// `05:00` or `01:00:00` (web `formatTimerRemaining`).
    public static func formatRemaining(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60, rest = seconds % 60
        return hours > 0 ? String(format: "%02d:%02d:%02d", hours, minutes, rest) : String(format: "%02d:%02d", minutes, rest)
    }

    /// `5 minutes` … `1 hour`.
    public static func durationTitle(_ minutes: Int) -> String {
        minutes == 60 ? "1 hour" : "\(minutes) minutes"
    }

    /// Parses `2026-10-11 14:30:00` (or with a `T`) in the device's time zone, like the web's `Date.parse`.
    static func parseLocalDateTime(_ text: String) -> Date? { HassDates.localDateTime(text) }

    /// The closest offered length (web `normalizeBathroomFanTimerMinutes`; ties keep the earlier value).
    public static func normalizedMinutes(_ minutes: Int) -> Int {
        timerMinutes.reduce(defaultTimerMinutes) { closest, candidate in
            abs(candidate - minutes) < abs(closest - minutes) ? candidate : closest
        }
    }

    // MARK: - Actions

    private func script(_ data: [String: JSONValue]) -> ServiceCall {
        ServiceCall("script", config.scriptService, data: data)
    }

    private func intent(_ id: String, _ on: Bool) -> OptimisticIntent { OptimisticIntent(id, on ? "on" : "off", revertAfter: Self.revert) }

    /// Turns the fan on or off; this also clears the timer, lock and auto-unlock on the server.
    public func setPower(_ on: Bool) {
        guard powerAvailable, on != powerOn else { return }
        var intents = [intent(config.powerEntityId, on)]
        if timerPending { intents.append(intent(config.pendingEntityId, false)) }
        if locked { intents.append(intent(config.lockEntityId, false)) }
        if autoUnlock { intents.append(intent(config.autoUnlockEntityId, false)) }
        commands.perform(script(["command": .string("power"), "target_power": .string(on ? "on" : "off")]), intents: intents)
    }

    /// Locks or unlocks the fan against its automations. Locking during a timer turns auto-unlock on.
    public func setLocked(_ lock: Bool) {
        guard lockAvailable, lock != locked else { return }
        var intents = [intent(config.lockEntityId, lock)]
        if lock && timerPending { intents.append(intent(config.autoUnlockEntityId, true)) }
        commands.perform(script(["command": .string("lock"), "locked": .bool(lock)]), intents: intents)
    }

    /// Starts the off timer with ``selectedMinutes``; auto-unlock applies only while locked.
    public func startTimer() {
        guard powerOn, timerAvailable else { return }
        let enabled = locked && displayedAutoUnlock
        commands.perform(script([
            "auto_unlock": .bool(enabled),
            "command": .string("timer_start"),
            "minutes": .number(Double(Self.normalizedMinutes(selectedMinutes))),
        ]), intents: [intent(config.pendingEntityId, true), intent(config.autoUnlockEntityId, enabled)])
    }

    /// Cancels the pending timer.
    public func cancelTimer() {
        guard timerPending, timerAvailable else { return }
        commands.perform(script(["command": .string("timer_cancel")]),
                         intents: [intent(config.pendingEntityId, false), intent(config.autoUnlockEntityId, false)])
    }

    /// Changes the auto-unlock checkbox: on the server while a timer runs, locally otherwise.
    public func setAutoUnlock(_ enabled: Bool) {
        guard timerPending else {
            observedSituation = situationKey
            idleAutoUnlock = enabled
            return
        }
        guard locked, liveAutoUnlockAvailable, enabled != autoUnlock else { return }
        commands.perform(script(["command": .string("timer_auto_unlock"), "enabled": .bool(enabled)]),
                         intents: [intent(config.autoUnlockEntityId, enabled)])
    }
}
