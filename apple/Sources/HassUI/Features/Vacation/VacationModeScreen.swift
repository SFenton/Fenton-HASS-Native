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
    }

    // MARK: - Sections

    private var modeSection: some View {
        AwaySection(title: Vacation.Copy.modeTitle, description: Vacation.Copy.modeDescription) {
            if controller.showsPreChecklistError { AwayInlineAlert(text: Vacation.Copy.preChecklistError) }
            if let error = SoloTripCopy.commandError(controller.household.errorCode) { AwayInlineAlert(text: error) }
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
                .accessibilityHint(controller.cardOpensSheet ? "Asks for the vacation dates." : "")
                .accessibilityIdentifier("vacation.modeCard")
        }
    }

    private var checklistSection: some View {
        AwaySection(title: Vacation.Copy.checklistTitle) {
            VStack(spacing: HassTokens.Spacing.s) {
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

/// One pre-vacation task (web `CheckboxRow`): a checkbox with the task title.
struct VacationChecklistRow: View {
    var title: String
    var isChecked: Bool
    var isUnavailable: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: HassTokens.Spacing.m) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isChecked ? AwayTint.vacation : HassTokens.Ink.secondary)
                Text(title)
                    .font(.body)
                    .foregroundStyle(HassTokens.Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, HassTokens.Spacing.m)
            .padding(.vertical, HassTokens.Spacing.s)
            .frame(minHeight: HassTokens.minTarget)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isUnavailable)
        .opacity(isUnavailable ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isUnavailable ? "Unavailable" : isChecked ? "Checked" : "Not checked")
        .accessibilityAddTraits(.isToggle)
    }
}

// MARK: - Dates

/// The vacation's four date and time fields with the range error (web `VacationDateControls`).
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
            if invalid { AwayInlineAlert(text: Vacation.Copy.dateRangeError) }
            ScheduleDateFields(fields: [
                ScheduleDateField(Vacation.Copy.startDate, .date, range.start, id: "\(identifierPrefix).startDate") {
                    onChange(Vacation.DateRange(start: $0, end: range.end), false)
                },
                ScheduleDateField(Vacation.Copy.startTime, .time, range.start, id: "\(identifierPrefix).startTime") {
                    onChange(Vacation.DateRange(start: $0, end: range.end), false)
                },
                ScheduleDateField(Vacation.Copy.endDate, .date, range.end, id: "\(identifierPrefix).endDate") {
                    onChange(Vacation.DateRange(start: range.start, end: $0), true)
                },
                ScheduleDateField(Vacation.Copy.endTime, .time, range.end, id: "\(identifierPrefix).endTime") {
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
            .navigationTitle(Vacation.Copy.confirmTitle)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { controller.cancelConfirmation() }
                        .accessibilityIdentifier("vacation.confirm.cancel")
                }
            }
        }
        .presentationDetents([.large])
    }
}
