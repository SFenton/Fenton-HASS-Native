import HassCore
import HassDesign
import SwiftUI

/// Vacation Mode (web `VacationModePage`): the mode card, then the pre-vacation checklist or, once enabled,
/// the vacation dates. Enabling opens ``VacationConfirmationSheet``. While a Solo Trip owns the household
/// plan, the page shows its status instead.
struct VacationModeScreen: View {
    @State private var controller: VacationModeController

    init(store: EntityStore, household: HouseholdAwayController, caller: any HassServiceCalling) {
        _controller = State(initialValue: VacationModeController(store: store, household: household, caller: caller))
    }

    var body: some View {
        ScrollView {
            Group {
                if controller.soloTripEngaged {
                    SoloTripStatusView(
                        status: SoloTripStatus.make(snapshot: controller.household.snapshot, errorCode: controller.household.errorCode),
                        notice: SoloTripNotice.make(snapshot: controller.household.snapshot, viewer: nil),
                        actionsDisabled: controller.household.pending || !controller.household.snapshot.canCommand
                    ) { action in
                        Task { await perform(action) }
                    }
                } else {
                    AwaySectionGrid {
                        modeSection
                        if controller.showsInlineDates { datesSection } else { checklistSection }
                    }
                }
            }
            .padding(HassTokens.Spacing.l)
        }
        .navigationTitle(Vacation.Copy.modeTitle)
        .sheet(isPresented: confirming) {
            VacationConfirmationSheet(controller: controller)
        }
        .alert(Vacation.Copy.disableAlertTitle, isPresented: confirmingDisable) {
            Button(Vacation.Copy.disableAlertConfirm, role: .destructive) { controller.confirmDisable() }
                .accessibilityIdentifier("vacation.disable.confirm")
            Button(Vacation.Copy.disableAlertCancel, role: .cancel) { controller.cancelDisable() }
                .accessibilityIdentifier("vacation.disable.cancel")
        }
    }

    // MARK: - Sections

    /// No section title: the navigation title already says Vacation Mode (as on Solo Trip, owner 2026-10-13).
    private var modeSection: some View {
        AwaySection(description: Vacation.Copy.modeDescription) {
            if controller.showsPreChecklistError { InlineAlert(Vacation.Copy.preChecklistError, severity: .error) }
            GlassTile(
                title: Vacation.Copy.modeTitle,
                subtitle: controller.cardSubtitle,
                symbol: SymbolMap.symbol(for: "mdi:airplane"),
                tint: controller.isConfirming ? AwayTint.pending : AwayTint.vacation,
                isActive: controller.cardEnabled || controller.isConfirming,
                isUnavailable: controller.modeUnavailable,
                kind: .toggle
            ) { controller.tapCard() }
                .disabled(controller.cardDisabled)
                .accessibilityValue(controller.cardSubtitle)
                .accessibilityHint(controller.cardAccessibilityHint)
                .accessibilityIdentifier("vacation.modeCard")
        }
    }

    /// The checklist as one inset list, its header counting what is done ("Pre-Vacation Checklist · 3 of 5",
    /// mockup n5-vacation-mode).
    private var checklistSection: some View {
        // A closure, not `controller.isChecked`: the main-actor method reference would lose its isolation.
        let done = Vacation.checklist.count(where: { controller.isChecked($0) })
        return AwaySection(title: "\(Vacation.Copy.checklistTitle) · \(done) of \(Vacation.checklist.count)") {
            // A module on the wallpaper, the sheet's cell colour in the Account and Quick Links sheets.
            ModuleList {
                ForEach(Array(Vacation.checklist.enumerated()), id: \.element.id) { index, item in
                    VacationChecklistRow(
                        title: item.title,
                        isChecked: controller.isChecked(item),
                        isUnavailable: controller.isUnavailable(item)
                    ) { controller.toggle(item) }
                        .accessibilityIdentifier("vacation.checklist.\(index)")
                }
            }
        }
    }

    private var datesSection: some View {
        AwaySection(title: Vacation.Copy.datesTitle) {
            VacationDateFields(
                range: controller.dateRange,
                invalid: controller.invalidDateRange,
                identifierPrefix: "vacation.dates",
                commitDelay: liveDateCommitDelay
            ) { range, changedEnd in
                controller.updateSavedRange(range, changedEnd: changedEnd)
            }
        }
    }

    // MARK: - Helpers

    private var confirmingDisable: Binding<Bool> {
        Binding { controller.isConfirmingDisable } set: { if !$0 { controller.cancelDisable() } }
    }

    private var confirming: Binding<Bool> {
        Binding { controller.isConfirming } set: { if !$0 { controller.cancelConfirmation() } }
    }

    private func perform(_ action: SoloTripStatus.Action) async {
        let household = controller.household
        household.clearError()
        switch action {
        case .keepCurrent: await household.resolveRestore(.keepCurrent)
        case .restoreSaved: await household.resolveRestore(.restoreSaved)
        case .endNow: await household.endNow()
        }
    }
}

// MARK: - Checklist row

/// One pre-vacation task (web `CheckboxRow`): a row of the checklist's ``ModuleList`` with a circle that turns into a
/// green check, as in Reminders (mockup n5-vacation-mode). The title starts 16 + 24 + 14 pt in, where the list insets
/// its hairlines.
struct VacationChecklistRow: View {
    var title: String
    var isChecked: Bool
    var isUnavailable: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: ModuleRowMetrics.gap) {
                // Only the glyph dims while unavailable; the title keeps its contrast (direction G, tiles).
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .imageScale(.large)
                    .foregroundStyle(isChecked ? AwayTint.checked : HassTokens.Ink.secondary)
                    .opacity(isUnavailable ? 0.5 : 1)
                Text(title)
                    .font(.body)
                    .foregroundStyle(HassTokens.Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, HassTokens.Spacing.l)
            .padding(.vertical, HassTokens.Spacing.m)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isUnavailable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isUnavailable ? "Unavailable" : isChecked ? "Checked" : "Not checked")
        .accessibilityAddTraits(.isToggle)
    }
}

// MARK: - Dates

/// The vacation's start and end, each one date-and-time picker, with the range error (web
/// `VacationDateControls`, whose four fields the owner asked to condense, 2026-10-13).
struct VacationDateFields: View {
    var range: Vacation.DateRange
    var invalid: Bool
    var identifierPrefix: String
    /// Quiet time before a change is reported (inline dates write to Home Assistant).
    var commitDelay: Duration?
    /// The new range and whether the end changed.
    var onChange: (Vacation.DateRange, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            Text(Vacation.Copy.datesDescription)
                .font(.subheadline)
                .foregroundStyle(HassTokens.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if invalid { InlineAlert(Vacation.Copy.dateRangeError, severity: .error) }
            ScheduleDateFields(fields: [
                ScheduleDateField(Vacation.Copy.starts, .dateAndTime, range.start, id: "\(identifierPrefix).start") {
                    onChange(Vacation.DateRange(start: $0, end: range.end), false)
                },
                ScheduleDateField(Vacation.Copy.ends, .dateAndTime, range.end, id: "\(identifierPrefix).end") {
                    onChange(Vacation.DateRange(start: range.start, end: $0), true)
                },
            ], commitDelay: commitDelay)
        }
    }
}

/// Dates for a new vacation (web `VacationConfirmationModal`).
struct VacationConfirmationSheet: View {
    var controller: VacationModeController

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HassTokens.Spacing.l) {
                    VacationDateFields(range: controller.dateRange, invalid: controller.invalidDateRange, identifierPrefix: "vacation.confirm") { range, _ in
                        controller.updatePendingRange(range)
                    }
                    if !controller.invalidDateRange {
                        AwayActionButton(title: Vacation.Copy.confirmAction, prominent: true, identifier: "vacation.confirm.action") {
                            controller.confirm()
                        }
                    }
                }
                .padding(HassTokens.Spacing.l)
            }
            .modalChrome()
            .navigationTitle(Vacation.Copy.confirmTitle)
            .inlineNavigationTitle()
            // A create sheet (direction G, Sheets): circle x Cancel leading drops the dates; the primary button confirms.
            .toolbar { SheetCancelItem(identifier: "vacation.confirm.cancel") { controller.cancelConfirmation() } }
        }
        .hassSheet()
    }
}
