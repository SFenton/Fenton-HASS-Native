import Foundation
import Observation

/// The Vacation Mode page's state (web `DashboardViewPage.tsx` `VacationModePage`, `VacationModeCard`,
/// `VacationChecklistSection`, `VacationDateControls`).
///
/// Enabling needs every checklist task done, then asks for dates in a confirmation sheet. While enabled the
/// page shows the dates inline (each change saves at once); disabling resets the checklist. If Home
/// Assistant paused the vacation for invalid dates, fixing them re-enables it.
@MainActor
@Observable
public final class VacationModeController {
    // MARK: - Dependencies

    public let store: EntityStore
    /// Household Away, for a backend vacation plan and the Solo Trip conflict.
    public let household: HouseholdAwayController

    @ObservationIgnored private let caller: any HassServiceCalling
    @ObservationIgnored private let overlay: OptimisticOverlay
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let calendar: Calendar

    /// How long a tapped toggle or checkbox shows its new value without an echo (web `DEFAULT_OPTIMISTIC_REVERT_MS`).
    public static let optimisticRevert: Duration = .seconds(2)

    // MARK: - Page state

    /// The enable was refused because the checklist isn't done.
    public private(set) var blockedEnableAttempted = false
    /// Dates being confirmed; non-nil while the confirmation sheet is open.
    public private(set) var pendingRange: Vacation.DateRange?

    // MARK: - Init

    /// Creates the page state.
    public init(
        store: EntityStore,
        household: HouseholdAwayController,
        caller: any HassServiceCalling,
        scheduler: any RevertScheduler = TaskRevertScheduler(),
        now: @escaping @MainActor () -> Date = { .now },
        calendar: Calendar = .current
    ) {
        self.store = store
        self.household = household
        self.caller = caller
        self.now = now
        self.calendar = calendar
        var rules: [String: OptimisticOverlay.ClearRule] = [Vacation.modeEntityId: .liveChange]
        for item in Vacation.checklist { rules[item.entityId] = .liveChange }
        overlay = OptimisticOverlay(rules: rules, scheduler: scheduler)
        liveDidChange()
        observeLive()
    }

    // MARK: - Reading

    private func live(_ entityId: String) -> String? { store.entity(entityId).state?.state }
    private func displayed(_ entityId: String) -> String? { overlay.displayed(entityId, live: live(entityId)) }

    /// The mode entity is missing, unavailable or unknown.
    public var modeUnavailable: Bool {
        guard let state = live(Vacation.modeEntityId) else { return true }
        return state == "unavailable" || state == "unknown"
    }

    /// The mode shows on (optimistically).
    public var modeOn: Bool { displayed(Vacation.modeEntityId) == "on" }

    /// The confirmation sheet is open.
    public var isConfirming: Bool { pendingRange != nil }

    /// The helpers' saved range.
    public var savedRange: Vacation.DateRange {
        Vacation.DateRange(startState: live(Vacation.startEntityId), endState: live(Vacation.endEntityId), now: now(), calendar: calendar)
    }

    /// The range shown: the sheet's draft while confirming, else the saved one.
    public var dateRange: Vacation.DateRange { pendingRange ?? savedRange }

    /// Start is not before end.
    public var invalidDateRange: Bool { dateRange.isInvalid(calendar: calendar) }

    /// Home Assistant paused the vacation for invalid dates (or they are invalid now).
    public var recoveringInvalidDates: Bool {
        !isConfirming && (invalidDateRange || live(Vacation.invalidDatesPendingEntityId) == "on")
    }

    /// A backend Household Away vacation is engaged.
    public var backendVacationEngaged: Bool { household.snapshot.isEngaged(.vacation) }

    /// The card shows enabled.
    public var cardEnabled: Bool { modeOn || recoveringInvalidDates || backendVacationEngaged }

    /// Show the dates instead of the checklist.
    public var showsInlineDates: Bool { cardEnabled }

    /// A Solo Trip owns the plan; the page shows its status instead.
    public var soloTripEngaged: Bool { household.snapshot.mode == .soloTrip }

    /// A checklist task is done (optimistically).
    public func isChecked(_ item: Vacation.ChecklistItem) -> Bool { displayed(item.entityId) == "on" }

    /// A checklist task can't be changed.
    public func isUnavailable(_ item: Vacation.ChecklistItem) -> Bool {
        let state = displayed(item.entityId) ?? "unavailable"
        return state == "unavailable" || state == "unknown"
    }

    /// Every checklist task is done.
    public var checklistComplete: Bool { Vacation.checklist.allSatisfy(isChecked) }

    /// Show the "finish the checklist" error.
    public var showsPreChecklistError: Bool {
        blockedEnableAttempted && !checklistComplete && !showsInlineDates && !isConfirming
    }

    /// The card can't be tapped.
    public var cardDisabled: Bool {
        modeUnavailable || household.pending || (recoveringInvalidDates && invalidDateRange)
    }

    /// The card subtitle (web `formatCompactEntityState`).
    public var cardSubtitle: String {
        if isConfirming { return Vacation.Copy.pending }
        if modeUnavailable { return Vacation.Copy.unavailable }
        return cardEnabled ? Vacation.Copy.on : Vacation.Copy.off
    }

    /// The card leads to the confirmation sheet.
    public var cardOpensSheet: Bool { !cardDisabled && !cardEnabled && !isConfirming && checklistComplete }

    // MARK: - Actions

    /// Taps the Vacation Mode card (web `toggleVacationMode`).
    public func tapCard() {
        guard !cardDisabled else { return }
        if cardEnabled {
            pendingRange = nil
            overlay.commit(Vacation.modeEntityId, value: "off", live: live(Vacation.modeEntityId), revertAfter: Self.optimisticRevert)
            send(Vacation.disableCalls())
            return
        }
        if isConfirming {
            pendingRange = nil
            return
        }
        guard checklistComplete else {
            blockedEnableAttempted = true
            return
        }
        pendingRange = .makeDefault(now: now(), calendar: calendar)
        blockedEnableAttempted = false
    }

    /// Checks or unchecks a task.
    public func toggle(_ item: Vacation.ChecklistItem) {
        guard !isUnavailable(item) else { return }
        let checked = isChecked(item)
        overlay.commit(item.entityId, value: checked ? "off" : "on", live: live(item.entityId), revertAfter: Self.optimisticRevert)
        if checklistComplete { blockedEnableAttempted = false }
        send([Vacation.setBoolean(item.entityId, on: !checked)])
    }

    /// Changes the sheet's draft.
    public func updatePendingRange(_ range: Vacation.DateRange) {
        guard isConfirming else { return }
        pendingRange = range
    }

    /// Closes the confirmation sheet without enabling.
    public func cancelConfirmation() { pendingRange = nil }

    /// Saves the sheet's dates and enables the mode.
    public func confirm() {
        let range = pendingRange ?? dateRange
        guard !range.isInvalid(calendar: calendar) else { return }
        send(Vacation.confirmCalls(range))
        pendingRange = nil
        blockedEnableAttempted = false
        overlay.commit(Vacation.modeEntityId, value: "on", live: live(Vacation.modeEntityId), revertAfter: Self.optimisticRevert)
    }

    /// Saves one inline date change; a fix to paused dates re-enables the vacation.
    /// - Parameters:
    ///   - range: The range after the change.
    ///   - changedEnd: The end changed (else the start).
    public func updateSavedRange(_ range: Vacation.DateRange, changedEnd: Bool) {
        let recovering = recoveringInvalidDates
        var calls = [changedEnd
            ? Vacation.setDateTime(Vacation.endEntityId, range.end)
            : Vacation.setDateTime(Vacation.startEntityId, range.start)]
        if recovering, !range.isInvalid(calendar: calendar), range.isFuture(now: now(), calendar: calendar) {
            calls += Vacation.recoveryCalls()
        }
        send(calls)
    }

    // MARK: - Private

    @ObservationIgnored private var lastSend: Task<Void, Never>?

    /// Sends calls in order after any earlier batch; failures are left to the live state (web fire-and-forget).
    private func send(_ calls: [ServiceCall]) {
        let previous = lastSend
        let caller = caller
        lastSend = Task { @MainActor in
            await previous?.value
            for call in calls { try? await caller.call(call) }
        }
    }

    /// Waits for every sent call (tests).
    func drain() async { await lastSend?.value }

    private func liveDidChange() {
        for key in overlay.trackedKeys { overlay.liveChanged(key, to: live(key)) }
    }

    private func observeLive() {
        withObservationTracking {
            for id in Vacation.pageEntityIds { _ = store.entity(id).state }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.liveDidChange()
                self?.observeLive()
            }
        }
    }
}
