import HassCore
import HassDesign
import SwiftUI

/// Solo Trip (web `SoloTripPage`): the Solo Trip toggle beside the traveler choice. Turning it on opens
/// ``SoloTripEditorSheet``; turning it off ends or cancels the trip. While a trip runs, the return time can
/// be moved and the status section shows anything that needs attention.
struct SoloTripScreen: View {
    @State private var controller: SoloTripController
    private let viewer: HouseholdResident?

    init(household: HouseholdAwayController, viewer: HouseholdResident?) {
        self.viewer = viewer
        _controller = State(initialValue: SoloTripController(household: household))
    }

    var body: some View {
        ScrollView {
            AwaySectionGrid {
                toggleSection
                travelerSection
            }
            .padding(HassTokens.Spacing.l)
        }
        .navigationTitle(SoloTripCopy.title)
        .onAppear { controller.viewer = viewer }
        .onChange(of: viewer) { _, viewer in controller.viewer = viewer }
        .sheet(isPresented: editorOpen) {
            SoloTripEditorSheet(controller: controller)
        }
    }

    // MARK: - Sections

    private var toggleSection: some View {
        AwaySection(title: SoloTripCopy.title) {
            if let notice = controller.notice { SoloTripNoticeBox(notice: notice) }
            Text(SoloTripCopy.description)
                .font(.subheadline)
                .foregroundStyle(HassTokens.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            GlassTile(
                title: SoloTripCopy.title,
                subtitle: controller.toggleSubtitle,
                symbol: SymbolMap.symbol(for: "mdi:bag-suitcase"),
                tint: AwayTint.soloTrip,
                isActive: controller.toggleChecked,
                kind: .toggle
            ) { Task { await controller.toggle() } }
                .disabled(controller.toggleDisabled)
                .accessibilityHint(controller.toggleChecked ? "" : "Asks for the departure and return times.")
                .accessibilityIdentifier("soloTrip.toggle")
            if let setupError = controller.setupError { AwayInlineAlert(text: setupError) }
        }
    }

    private var travelerSection: some View {
        AwaySection(title: SoloTripCopy.awayFromHomeTitle, description: SoloTripCopy.awayFromHomeDescription) {
            DynamicGridLayout(minCellWidth: 140, maxColumns: 2, spacing: HassTokens.Spacing.s) {
                ForEach(controller.travelerTiles) { tile in
                    TravelerTileView(tile: tile) { controller.selectTraveler(tile.resident) }
                }
            }
            if controller.showsReturnFields {
                ScheduleDateFields(fields: [
                    ScheduleDateField(SoloTripCopy.endDate, .date, controller.returnDraft, id: "soloTrip.return.date") { end in
                        Task { await controller.updateReturn(end) }
                    },
                    ScheduleDateField(SoloTripCopy.endTime, .time, controller.returnDraft, id: "soloTrip.return.time") { end in
                        Task { await controller.updateReturn(end) }
                    },
                ], commitDelay: liveDateCommitDelay)
                .disabled(controller.returnFieldsDisabled)
                if let error = controller.returnError { AwayInlineAlert(text: error) }
            }
            if let status = controller.status {
                SoloTripStatusView(status: status, notice: nil, actionsDisabled: controller.restoreDisabled) { action in
                    Task {
                        switch action {
                        case .keepCurrent: await controller.resolveRestore(.keepCurrent)
                        case .restoreSaved: await controller.resolveRestore(.restoreSaved)
                        case .endNow: await controller.toggle()
                        }
                    }
                }
            }
        }
    }

    private var editorOpen: Binding<Bool> {
        Binding { controller.editorOpen } set: { if !$0 { controller.closeEditor() } }
    }
}

// MARK: - Traveler tile

/// A resident tile: selectable before a trip, then showing Away or Home.
struct TravelerTileView: View {
    var tile: SoloTripController.TravelerTile
    var action: () -> Void

    var body: some View {
        GlassTile(
            title: tile.title,
            subtitle: tile.subtitle,
            symbol: SymbolMap.symbol(for: tile.icon),
            tint: AwayTint.soloTrip,
            isActive: tile.isSelected && !tile.isMuted,
            kind: .command
        ) { if tile.isInteractive { action() } }
            .disabled(tile.isDisabled)
            .accessibilityValue(tile.subtitle ?? "")
            .accessibilityAddTraits(tile.isSelected ? .isSelected : [])
            .accessibilityHint(tile.isInteractive ? (tile.isSelected ? "Clears the traveler." : "Selects the traveler.") : "")
            .accessibilityIdentifier("soloTrip.traveler.\(tile.resident.rawValue)")
    }
}

// MARK: - Status

/// The Solo Trip status block (web `SoloTripStatusSection`).
struct SoloTripStatusView: View {
    var status: SoloTripStatus
    var notice: SoloTripNotice?
    var actionsDisabled: Bool
    var perform: (SoloTripStatus.Action) -> Void

    var body: some View {
        AwaySection(title: status.title, description: status.description) {
            if let error = status.error { AwayInlineAlert(text: error) }
            if status.showsActiveNotice, let notice { SoloTripNoticeBox(notice: notice) }
            ForEach(status.actions, id: \.self) { action in
                AwayActionButton(title: action.title, role: action == .endNow ? .destructive : nil,
                                 identifier: "soloTrip.status.\(action.rawValue)") { perform(action) }
                    .disabled(actionsDisabled)
            }
        }
        // A container keeps the action buttons' own identifiers (an identifier on a plain stack overwrote them).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("soloTrip.status")
    }
}

// MARK: - Editor

/// Departure and return for a new Solo Trip (web `SoloTripEditorModal`).
struct SoloTripEditorSheet: View {
    var controller: SoloTripController

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HassTokens.Spacing.l) {
                    Text(SoloTripCopy.editorDescription)
                        .font(.subheadline)
                        .foregroundStyle(HassTokens.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ScheduleDateFields(fields: [
                        ScheduleDateField(SoloTripCopy.startDate, .date, controller.scheduleDraft.start, id: "soloTrip.editor.startDate") {
                            controller.scheduleDraft.start = $0
                        },
                        ScheduleDateField(SoloTripCopy.startTime, .time, controller.scheduleDraft.start, id: "soloTrip.editor.startTime") {
                            controller.scheduleDraft.start = $0
                        },
                        ScheduleDateField(SoloTripCopy.endDate, .date, controller.scheduleDraft.end, id: "soloTrip.editor.endDate") {
                            controller.scheduleDraft.end = $0
                        },
                        ScheduleDateField(SoloTripCopy.endTime, .time, controller.scheduleDraft.end, id: "soloTrip.editor.endTime") {
                            controller.scheduleDraft.end = $0
                        },
                    ])
                    .disabled(controller.isScheduling)
                    ForEach(controller.editorAlerts, id: \.self) { AwayInlineAlert(text: $0) }
                    AwayActionButton(title: SoloTripCopy.editorConfirm, prominent: true, identifier: "soloTrip.editor.confirm") {
                        Task { await controller.confirmSchedule() }
                    }
                    .disabled(controller.editorConfirmDisabled)
                }
                .padding(HassTokens.Spacing.l)
            }
            .navigationTitle(SoloTripCopy.editorTitle)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { controller.closeEditor() }
                        .disabled(controller.isScheduling || controller.household.pending)
                        .accessibilityIdentifier("soloTrip.editor.cancel")
                }
            }
        }
        .interactiveDismissDisabled(controller.isScheduling)
        .presentationDetents([.large])
    }
}
