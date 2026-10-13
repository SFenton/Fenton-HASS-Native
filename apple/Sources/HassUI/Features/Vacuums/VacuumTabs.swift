import HassCore
import HassDesign
import SwiftUI

// MARK: - Tab picker

/// The segmented tab control; a menu at accessibility text sizes (HIG: Segmented controls).
struct VacuumTabPicker: View {
    var tabs: [VacuumTab]
    var title: String
    @Binding var selection: VacuumTab
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let picker = Picker("\(title) sections", selection: $selection) {
            ForEach(tabs) { Text($0.title).tag($0) }
        }
        .accessibilityIdentifier("vacuum.tabs")
        if typeSize.isAccessibilitySize || tabs.count > 4 && typeSize >= .xLarge {
            picker.pickerStyle(.menu).frame(minHeight: HassTokens.minTarget)
        } else {
            picker.pickerStyle(.segmented).labelsHidden()
        }
    }
}

// MARK: - Controls

/// Cleaning setup, state actions and power settings (web `VacuumControlsTab`).
struct VacuumControlsTab: View {
    var controller: VacuumController
    var mapState: VacuumMapState
    /// The runtime mode drawn. While a clean starts or ends the sheet keeps drawing the outgoing mode as it fades out
    /// (web `useVacuumRuntimeContentTransition`).
    var mode: VacuumRuntimeMode
    var onOpenRooms: () -> Void
    var onEditArea: () -> Void
    @State private var confirming: Confirmation?

    enum Confirmation: Identifiable {
        case toRooms, toArea
        var id: Self { self }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
            stateSection
            let settings = controller.powerSettings(in: mode)
            if !settings.isEmpty {
                VacuumSection("Power Settings") {
                    ForEach(settings) { setting in
                        VacuumSettingRow(setting: setting) { controller.select(setting.entityId, option: $0) }
                    }
                }
            }
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible, presenting: confirming) { confirmation in
            switch confirmation {
            case .toRooms:
                Button("Switch to Rooms", role: .destructive) {
                    controller.areaSelection = nil
                    onOpenRooms()
                }
            case .toArea:
                Button("Switch to Area", role: .destructive) {
                    controller.clearRoomsForArea()
                    onEditArea()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { confirmation in
            Text(confirmation == .toRooms
                 ? "You have an area drawn right now. Switching to Rooms will discard that area. Are you sure you want to continue?"
                 : "Continuing clears your selected rooms and opens area drawing.")
        }
    }

    private var confirmTitle: String { confirming == .toRooms ? "Switch to Rooms" : "Switch to Area?" }

    @ViewBuilder private var stateSection: some View {
        // The live mode's actions (Pause, Stop) wait for the swap rather than popping into the fading setup.
        let actions = mode == controller.runtimeMode ? controller.runtimeActions : []
        let setup = controller.showsCleaningSetup(in: mode)
        if setup || !actions.isEmpty || controller.cleanError != nil {
            VacuumSection(VacuumFormat.state(controller.state, fallback: "Vacuum")) {
                if setup {
                    if controller.supportsAreaCleaning { targetPicker }
                    if controller.areaSelection != nil && controller.supportsAreaCleaning { areaSetup } else { roomsSetup }
                }
                ForEach(actions) { action in
                    VacuumActionButton(action: action) { controller.run(action.kind) }
                }
                if let error = controller.cleanError {
                    VacuumNotice(nil, tone: .danger, text: error)
                        .accessibilityIdentifier("vacuum.cleanError")
                }
            }
        } else if !controller.status.primaryAvailable || controller.status.currentIssue.status == .present {
            VacuumSection(VacuumFormat.state(controller.state)) {
                VacuumDescription(controller.status.currentIssue.raw ?? "Home Assistant does not have a current status for the vacuum.")
            }
        }
    }

    /// Rooms / Area (web `VacuumCleanTargetSelector`).
    private var targetPicker: some View {
        let area = controller.areaSelection != nil
        let disabled = controller.normalCommandsDisabled
        return HStack(spacing: HassTokens.Spacing.s) {
            targetButton("Rooms", symbol: "square.split.2x2", selected: !area, disabled: disabled, id: "rooms") {
                if area { confirming = .toRooms } else { onOpenRooms() }
            }
            targetButton("Area", symbol: "rectangle.dashed", selected: area, disabled: disabled || !mapState.isReady, id: "area") {
                if !controller.selectedZones.isEmpty && !area { confirming = .toArea } else { onEditArea() }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cleaning target")
    }

    private func targetButton(_ title: String, symbol: String, selected: Bool, disabled: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
                .foregroundStyle(selected ? Color.white : HassTokens.Ink.primary)
                .background(selected ? AnyShapeStyle(VacuumStyle.primaryFill) : AnyShapeStyle(VacuumStyle.rowFill), in: VacuumStyle.rowShape)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("vacuum.target.\(id)")
    }

    @ViewBuilder private var roomsSetup: some View {
        VacuumDescription("Choose how many passes the vacuum should make, then start cleaning with the selected rooms.")
        if !controller.vacuum.zones.isEmpty {
            let rooms = controller.selectedZones
            if rooms.isEmpty {
                VacuumNotice("Full Clean", tone: .warning,
                             text: "No rooms are selected, and no areas are drawn. If you begin cleaning, the robot vacuum will attempt to clean every mapped area.")
                    .accessibilityIdentifier("vacuum.selectedRooms")
            } else {
                VacuumNotice("Selected Rooms", tone: .ok,
                             text: rooms.enumerated().map { "\($0 + 1). \($1.title)" }.joined(separator: "\n"))
                    .accessibilityIdentifier("vacuum.selectedRooms")
            }
        }
        if let passes = controller.passesSetting {
            VacuumSettingRow(setting: passes) { controller.select(passes.entityId, option: $0) }
        }
        VacuumActionButton(action: controller.cleanAction) { controller.run(.clean) }
    }

    @ViewBuilder private var areaSetup: some View {
        VacuumDescription("Draw one rectangular cleaning area on the map. The vacuum will use the mode, suction, water, and pass settings shown below.")
        HStack(spacing: HassTokens.Spacing.s) {
            VacuumActionButton(action: .init(kind: .cleanArea, title: "Edit Area", icon: "mdi:pencil", tone: .primary, detail: nil,
                                             isDisabled: controller.normalCommandsDisabled || !mapState.isReady),
                               identifier: "vacuum.area.edit", perform: onEditArea)
            VacuumActionButton(action: .init(kind: .cleanArea, title: "Clear Area", icon: "mdi:delete-outline", tone: .neutral, detail: nil, isDisabled: false),
                               identifier: "vacuum.area.clearSelection") { controller.areaSelection = nil }
        }
        if controller.services != nil && !controller.areaServiceReady, let script = controller.vacuum.areaCleaning?.script {
            VacuumDescription("Local preview only: \(script) is not installed in Home Assistant, so starting an area clean is disabled.")
        }
        VacuumDescription("These settings are confirmed in Home Assistant before the area-cleaning command is sent.")
        if let passes = controller.passesSetting {
            VacuumSettingRow(setting: passes) { controller.select(passes.entityId, option: $0) }
        }
        VacuumActionButton(action: controller.areaCleanAction(mapReady: mapState.isReady, selectionAllowed: mapState.allows(controller.areaSelection))) {
            controller.run(.cleanArea, pixelSize: mapState.scene?.interactionGeometry.pixelSize)
        }
    }
}

// MARK: - Rooms

/// Ordered room toggles (web `VacuumZones`).
struct VacuumRoomsTab: View {
    var controller: VacuumController
    @State private var pendingZone: VacuumConfig.Zone?
    @ScaledMetric(relativeTo: .subheadline) private var minCellWidth: CGFloat = 150
    /// Room cards are tile-sized (76 pt minimum, icon above the title), larger than the web's 58 px buttons, so
    /// the two-column iPhone grid reads as tappable cards (owner, 2026-10-13). A floor, not scaled: larger text grows the
    /// card through its content. HIG: Layout, Buttons.
    private let cardHeight: CGFloat = 76

    var body: some View {
        VacuumSection("Rooms") {
            ForEach(controller.vacuum.zoneDescription, id: \.self) { VacuumDescription($0) }
            VacuumDescription("Rooms are cleaned in the order you select them. The numbered badges show the current cleaning sequence.")
            DynamicGridLayout(minCellWidth: minCellWidth, maxColumns: 2) {
                ForEach(controller.vacuum.zones) { zone in
                    roomButton(zone)
                }
            }
        }
        .alert("Switch to Rooms", isPresented: Binding(get: { pendingZone != nil }, set: { if !$0 { pendingZone = nil } }), presenting: pendingZone) { zone in
            Button("Continue") { controller.toggleRoom(zone) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You have an area drawn right now. Switching to Rooms will discard that area. Are you sure you want to continue?")
        }
    }

    private func roomButton(_ zone: VacuumConfig.Zone) -> some View {
        let selected = controller.isSelected(zone)
        let order = controller.order(of: zone)
        return Button {
            if controller.roomToggleNeedsConfirmation(zone) { pendingZone = zone } else { controller.toggleRoom(zone) }
        } label: {
            // Tile layout (icon and order badge on top, title below) so the title gets the card's full width:
            // beside the icon and badge, "Kitchen" broke mid-word on iPhone.
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                HStack(alignment: .top) {
                    Image(systemName: VacuumStyle.symbol(zone.icon))
                        .font(.title2)
                        .foregroundStyle(selected ? VacuumStyle.primaryFill : HassTokens.Ink.secondary)
                    Spacer(minLength: HassTokens.Spacing.xs)
                    if let order {
                        Text("\(order)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 28, minHeight: 28)
                            .background(VacuumStyle.primaryFill, in: Circle())
                    }
                }
                Text(zone.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(HassTokens.Ink.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(HassTokens.Spacing.m)
            // Fills the row the grid proposes, so cards in a row match the tallest title.
            .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: .infinity, alignment: .topLeading)
            .background(VacuumStyle.rowFill, in: VacuumStyle.cardShape)
            .overlay { VacuumStyle.cardShape.strokeBorder(selected ? VacuumStyle.primaryFill : .clear, lineWidth: 2) }
            .contentShape(VacuumStyle.cardShape)
        }
        .buttonStyle(.plain)
        .disabled(!controller.roomsEditable)
        .opacity(controller.roomsEditable ? 1 : 0.45)
        .accessibilityLabel(order.map { "\(zone.title), cleaning order \($0)" } ?? zone.title)
        .accessibilityValue(selected ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier("vacuum.room.\(zone.entityId)")
    }
}

// MARK: - Auto-clean

/// Rooms the coordinator skips (web `VacuumAutoCleanDisabledRooms`).
struct VacuumAutoCleanTab: View {
    var controller: VacuumController
    @ScaledMetric(relativeTo: .subheadline) private var minCellWidth: CGFloat = 150
    /// Matches the Rooms tab's card height.
    private let cardHeight: CGFloat = 76

    var body: some View {
        VacuumSection("Disabled Auto-Clean Rooms") {
            VacuumDescription("Check rooms that should be skipped when the coordinator starts an automatic away clean. Use this for closed doors, guests, or projects on the floor; manual selected-room cleans still use the Rooms tab.")
            DynamicGridLayout(minCellWidth: minCellWidth, maxColumns: 2) {
                ForEach(controller.vacuum.autoCleanDisabledRooms) { room in
                    let skipped = controller.isAutoCleanDisabled(room)
                    let unavailable = VacuumStatusResolver.isUnavailable(controller.store.entity(room.entityId).state?.state)
                    Button { controller.toggleAutoClean(room) } label: {
                        HStack(spacing: HassTokens.Spacing.m) {
                            Image(systemName: skipped ? "checkmark.square.fill" : "square")
                                .font(.title2)
                                .foregroundStyle(skipped ? VacuumStyle.primaryFill : HassTokens.Ink.secondary)
                                .frame(minWidth: 32)
                            Text(room.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(HassTokens.Ink.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, HassTokens.Spacing.m)
                        .padding(.vertical, HassTokens.Spacing.s)
                        .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: .infinity, alignment: .leading)
                        .background(VacuumStyle.rowFill, in: VacuumStyle.cardShape)
                        .contentShape(VacuumStyle.cardShape)
                    }
                    .buttonStyle(.plain)
                    .disabled(unavailable)
                    .opacity(unavailable ? 0.45 : 1)
                    .accessibilityLabel("\(room.title) auto-clean")
                    .accessibilityValue(unavailable ? "Unavailable" : skipped ? "Skipped" : "Included")
                    .accessibilityAddTraits(.isToggle)
                    .accessibilityIdentifier("vacuum.autoCleanRoom.\(room.entityId)")
                }
            }
        }
    }
}

// MARK: - Actions

/// Dock controls (web `VacuumDockControlsSection`).
struct VacuumActionsTab: View {
    var controller: VacuumController

    var body: some View {
        let actions = controller.dockActions
        if !actions.isEmpty || controller.dockPreparationActive {
            VacuumSection("Dock Controls") {
                if controller.dockPreparationActive && controller.vacuum.dockControls != nil {
                    VacuumInfoPill(icon: "mdi:water", label: "Dock Status", value: "Washing Mop Pads", tone: .active)
                    VacuumDescription("The dock is washing the mop pads for the current cleaning session. To stop, use Cancel Cleaning Session on the Controls tab.")
                }
                ForEach(actions) { action in
                    VacuumActionButton(action: action) { controller.run(action.kind) }
                }
                if controller.vacuum.dockControls != nil && !controller.mopAttached {
                    VacuumNotice(nil, tone: .warning, text: "Attach the mop pads before cleaning or drying them at the dock.")
                }
                if controller.vacuum.dockControls != nil && controller.services != nil && !controller.dockBridgeAvailable {
                    VacuumNotice(nil, tone: .warning, text: "Dock cleaning and drying controls will be available after Home Assistant restarts.")
                }
            }
        }
    }
}

// MARK: - Info

/// Bin state and consumables (web `VacuumConsumables`).
struct VacuumInfoTab: View {
    var controller: VacuumController
    @ScaledMetric(relativeTo: .subheadline) private var minPillWidth: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
            group("Bin State", controller.vacuum.consumables.filter { $0.valueKind == .status })
            group("Consumables", controller.vacuum.consumables.filter { $0.valueKind == .duration })
        }
    }

    @ViewBuilder private func group(_ title: String, _ consumables: [VacuumConfig.Consumable]) -> some View {
        if !consumables.isEmpty {
            VacuumSection(title) {
                DynamicGridLayout(minCellWidth: minPillWidth, maxColumns: 2) {
                    ForEach(consumables) { consumable in
                        let entity = controller.store.entity(consumable.entityId).state
                        let visual = VacuumVisual.consumable(consumable, state: entity?.state)
                        VacuumInfoPill(icon: visual.icon, label: consumable.title,
                                       value: VacuumFormat.consumable(consumable, state: entity?.state,
                                                                      unit: entity?.attributes["unit_of_measurement"]?.string),
                                       tone: visual.tone)
                    }
                }
            }
        }
    }
}
