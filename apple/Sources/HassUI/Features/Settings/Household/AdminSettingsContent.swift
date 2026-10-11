import HassCore
import HassDesign
import SwiftUI

/// Admin Controls (web `AdminPage`, DashboardViewPage.tsx:2871): six sections top to bottom; the presence
/// override and auto-reset grids open as sheets (`.agents/patterns/modal-sheet.md`).
struct AdminSettingsContent: View {
    var controller: HouseholdSettingsController
    @State private var sheet: AdminSheet?

    /// The two sheets the page opens (web hashes `#presence-based-overrides` and `#presence-based-overrides-auto`).
    enum AdminSheet: String, Identifiable {
        case presenceOverrides, autoReset
        var id: String { rawValue }
    }

    private typealias Admin = HouseholdSettingsConfig.Admin

    var body: some View {
        SettingsSection(title: Admin.security.title, paragraphs: Admin.security.paragraphs) {
            HouseholdTileGrid(minWidth: 240, maxColumns: 2) {
                ForEach(Admin.securityTiles) { HouseholdToggleTile(tile: $0, controller: controller) }
            }
        }

        SettingsSection(title: Admin.powerRecovery.title, paragraphs: Admin.powerRecovery.paragraphs) {
            HouseholdTileGrid(minWidth: 240, maxColumns: 2) {
                GlassTile(
                    title: Admin.powerRecoveryTitle,
                    symbol: SymbolMap.symbol(for: "mdi:flash"),
                    tint: HassTokens.Tint.settingsSwitch,
                    isActive: true,
                    kind: .command
                ) {
                    controller.triggerPowerRecovery()
                }
                .accessibilityHint("Runs the Living Room power recovery automation.")
                .accessibilityIdentifier("admin.powerRecovery")
            }
        }

        SettingsSection(title: Admin.relayControl.title, paragraphs: Admin.relayControl.paragraphs) {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
                HouseholdTileGrid(minWidth: 240, maxColumns: 2) {
                    ForEach(Admin.relayTiles) { HouseholdToggleTile(tile: $0, controller: controller) }
                }
                if controller.showsRelayGuestModeWarning {
                    InlineAlert(Admin.relayGuestModeWarning)
                        .accessibilityIdentifier("admin.relayWarning")
                }
            }
        }

        SettingsSection(title: Admin.presenceOverrides.title, paragraphs: Admin.presenceOverrides.paragraphs) {
            opener(Admin.presenceOpenerTitle, symbol: "mdi:lightbulb-auto", sheet: .presenceOverrides)
        }

        SettingsSection(title: Admin.showSpecific.title, paragraphs: Admin.showSpecific.paragraphs) {
            HouseholdTileGrid(minWidth: 200, maxColumns: 2) {
                ForEach(Admin.showSpecificTiles) { HouseholdToggleTile(tile: $0, controller: controller) }
            }
        }

        SettingsSection(title: Admin.autoReset.title, paragraphs: Admin.autoReset.paragraphs) {
            opener(Admin.autoResetOpenerTitle, symbol: "mdi:autorenew", sheet: .autoReset)
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .presenceOverrides: PresenceOverridesSheet(controller: controller)
            case .autoReset: AutoResetSheet(controller: controller)
            }
        }
    }

    /// A wide tile that opens a sheet (web `ModalOpenerRow`).
    private func opener(_ title: String, symbol: String, sheet: AdminSheet) -> some View {
        HouseholdTileGrid(minWidth: 240, maxColumns: 2) {
            GlassTile(
                title: title,
                symbol: SymbolMap.symbol(for: symbol),
                tint: HassTokens.Tint.settingsSwitch,
                isActive: true,
                kind: .navigate
            ) {
                self.sheet = sheet
            }
            .accessibilityIdentifier("admin.open.\(sheet.rawValue)")
        }
    }
}

// MARK: - Sheet chrome

/// A household sheet: its own navigation stack with a title and Done (`.agents/patterns/modal-sheet.md`).
struct HouseholdSheet<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        content
            .navigationTitle(title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("household.sheet.done")
                }
            }
    }
}

// MARK: - Presence-Based Overrides

/// The room grid; a room pushes its mode list inside the sheet (web `AdminPresenceOverrideGrid` and
/// `PresenceOverrideDetailPage`).
struct PresenceOverridesSheet: View {
    var controller: HouseholdSettingsController
    @State private var path: [HouseholdSettingsConfig.PresenceRoom] = []

    /// Opens on a room's detail (gallery and tests).
    init(controller: HouseholdSettingsController, initialRoom: HouseholdSettingsConfig.PresenceRoom? = nil) {
        self.controller = controller
        _path = State(initialValue: initialRoom.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            HouseholdSheet(title: HouseholdSettingsConfig.Admin.presenceSheetTitle) {
                ScrollView {
                    HouseholdTileGrid(minWidth: 150, maxColumns: 4) {
                        ForEach(HouseholdSettingsConfig.Admin.presenceRooms) { room in
                            let mode = controller.presence(room.presenceEntityId)
                            GlassTile(
                                title: room.title,
                                subtitle: mode.summary,
                                symbol: SymbolMap.symbol(for: "mdi:lightbulb-auto"),
                                tint: mode.tint,
                                isActive: mode != .unavailable,
                                isUnavailable: mode == .unavailable,
                                kind: .navigate
                            ) {
                                path.append(room)
                            }
                                            .accessibilityIdentifier("presence.room.\(room.presenceEntityId)")
                        }
                    }
                    .padding()
                }
            }
            .navigationDestination(for: HouseholdSettingsConfig.PresenceRoom.self) { room in
                PresenceOverrideDetail(room: room, controller: controller)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

/// A room's four modes as a single-choice list (one column on phones, two where there is room).
struct PresenceOverrideDetail: View {
    var room: HouseholdSettingsConfig.PresenceRoom
    var controller: HouseholdSettingsController

    var body: some View {
        let shown = controller.presence(room.presenceEntityId)
        ScrollView {
            DynamicGridLayout(minCellWidth: 300, maxColumns: 2) {
                ForEach(PresenceOverrideState.choices) { mode in
                    SelectableOptionRow(
                        title: mode.label,
                        detail: mode.detail,
                        symbol: SymbolMap.symbol(for: mode.icon),
                        tint: mode.tint,
                        isSelected: shown == mode,
                        isDisabled: shown == .unavailable
                    ) {
                        controller.setPresence(room.presenceEntityId, to: mode)
                    }
                    .accessibilityIdentifier("presence.option.\(mode.rawValue)")
                }
            }
            .padding()
            if shown == .unavailable {
                Text(PresenceOverrideState.unavailable.detail)
                    .font(.subheadline)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .padding(.horizontal)
            }
        }
        .navigationTitle("\(room.title) Presence Lighting")
        .inlineNavigationTitle()
        .accessibilityIdentifier("presence.detail")
    }
}

// MARK: - Auto-Reset

/// The morning auto re-enable toggles, one per room (web `#presence-based-overrides-auto`).
struct AutoResetSheet: View {
    var controller: HouseholdSettingsController

    var body: some View {
        NavigationStack {
            HouseholdSheet(title: HouseholdSettingsConfig.Admin.autoResetSheetTitle) {
                ScrollView {
                    HouseholdTileGrid(minWidth: 150, maxColumns: 4) {
                        ForEach(HouseholdSettingsConfig.Admin.autoResetTiles) { HouseholdToggleTile(tile: $0, controller: controller) }
                    }
                    .padding()
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
