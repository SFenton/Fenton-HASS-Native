import HassCore
import HassDesign
import SwiftUI

// MARK: - Section bar

/// The vacuum sheet's sections in the bottom glass section bar (``ModalTabBar``; direction G, Sheets: "symbols only at
/// five segments (the vacuum)"). Fewer sections (a run in progress shows Controls, Auto-Clean and Info) read as text.
enum VacuumTabSymbols {
    /// The symbol for a section (mockup n6-vacuum-sheet: robot, floor plan, auto-clean clock, dock, info).
    static func symbol(for tab: VacuumTab) -> String {
        switch tab {
        case .controls: VacuumStyle.symbol(tab.icon)
        case .zones: VacuumStyle.symbol(tab.icon)
        case .autoClean: "clock.arrow.circlepath"
        case .more: "ev.charger"
        case .info: VacuumStyle.symbol(tab.icon)
        }
    }
}

// MARK: - Clean target

/// Rooms or Area, the Controls section's segmented choice (web `VacuumCleanTargetSelector`), and what picking one
/// does. Pure, so the confirmation rules are unit-tested apart from the view.
enum VacuumCleanTarget: Hashable {
    case rooms, area

    /// What a pick leads to.
    enum Outcome: Equatable {
        /// Open the Rooms section.
        case openRooms
        /// Open the area editor.
        case openAreaEditor
        /// Ask before discarding the drawn area.
        case confirmRooms
        /// Ask before clearing the selected rooms.
        case confirmArea
        /// Nothing (the map is not ready for drawing).
        case none
    }

    /// The target the sheet is on.
    static func current(areaDrawn: Bool) -> Self { areaDrawn ? .area : .rooms }

    /// The outcome of picking `target` (the web's target buttons).
    static func outcome(picking target: Self, areaDrawn: Bool, roomsSelected: Bool, mapReady: Bool) -> Outcome {
        switch target {
        case .rooms: return areaDrawn ? .confirmRooms : .openRooms
        case .area:
            guard mapReady else { return .none }
            return roomsSelected && !areaDrawn ? .confirmArea : .openAreaEditor
        }
    }
}

// MARK: - Controls

/// Cleaning setup, state actions and power settings (web `VacuumControlsTab`; mockups n6-vacuum-sheet and
/// n6-vacuum-cleaning: while a run is going, the setup collapses to one card with Pause and Stop).
struct VacuumControlsTab: View {
    var controller: VacuumController
    var mapState: VacuumMapState
    /// The runtime mode drawn. While a clean starts or ends the sheet keeps drawing the outgoing mode as it fades out
    /// (web `useVacuumRuntimeContentTransition`).
    var mode: VacuumRuntimeMode
    var onOpenRooms: () -> Void
    var onEditArea: () -> Void
    @State private var confirming: Confirmation?
    @Environment(\.dynamicTypeSize) private var typeSize

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
                    ModuleList {
                        ForEach(settings) { setting in
                            VacuumSettingRow(setting: setting) { controller.select(setting.entityId, option: $0) }
                        }
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
            VStack(alignment: .leading, spacing: HassTokens.Spacing.l) {
                if setup {
                    if controller.supportsAreaCleaning { targetPicker }
                    if controller.areaSelection != nil && controller.supportsAreaCleaning { areaSetup } else { roomsSetup }
                }
                if !actions.isEmpty { runtimeCard(actions) }
                if let error = controller.cleanError {
                    InlineAlert(error, severity: .error)
                        .padding(.horizontal, HassTokens.Spacing.l)
                        .accessibilityIdentifier("vacuum.cleanError")
                }
            }
        } else if !controller.status.primaryAvailable || controller.status.currentIssue.status == .present {
            VacuumSection(VacuumFormat.state(controller.state)) {
                Text(controller.status.currentIssue.raw.map(VacuumFormat.issue) ?? "Home Assistant does not have a current status for the vacuum.")
                    .font(.body)
                    .foregroundStyle(HassTokens.Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(HassTokens.Spacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .vacuumGroup()
            }
        }
    }

    // MARK: Runtime

    /// The run's state and its commands in one card (mockup n6-vacuum-cleaning). Two commands sit side by side;
    /// more, or any at accessibility sizes, stack. A disabled command shows why under it.
    private func runtimeCard(_ actions: [VacuumController.Action]) -> some View {
        let visual = VacuumVisual.state(controller.state)
        let layout = typeSize.isAccessibilitySize || actions.count > 2
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        return VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            Label {
                Text(VacuumFormat.state(controller.state, fallback: "Vacuum"))
                    .font(.headline)
                    .foregroundStyle(HassTokens.Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: VacuumStyle.symbol(visual.icon))
                    .foregroundStyle(VacuumStyle.color(visual.tone))
            }
            .accessibilityAddTraits(.isHeader)
            layout {
                ForEach(actions) { action in
                    VacuumActionButton(action: action, showsDetail: action.isDisabled) { controller.run(action.kind) }
                }
            }
        }
        .padding(HassTokens.Spacing.l)
        .vacuumGroup()
        .accessibilityElement(children: .contain)
    }

    // MARK: Target

    /// Rooms / Area as a system segmented control (direction G, Controls: 2–4 short options).
    private var targetPicker: some View {
        let selection = Binding<VacuumCleanTarget>(
            get: { VacuumCleanTarget.current(areaDrawn: controller.areaSelection != nil) },
            // A closure, not the bare method: a reference to a main-actor method can't become Binding's
            // nonisolated setter in Swift 6.
            set: { pick($0) }
        )
        return Picker("Cleaning Target", selection: selection) {
            Text("Rooms").tag(VacuumCleanTarget.rooms)
            Text("Area").tag(VacuumCleanTarget.area)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        .disabled(controller.normalCommandsDisabled)
        .accessibilityIdentifier("vacuum.target")
        .accessibilityHint(mapState.isReady ? "" : "Area drawing needs the live map.")
    }

    private func pick(_ target: VacuumCleanTarget) {
        switch VacuumCleanTarget.outcome(picking: target, areaDrawn: controller.areaSelection != nil,
                                         roomsSelected: !controller.selectedZones.isEmpty, mapReady: mapState.isReady) {
        case .openRooms: onOpenRooms()
        case .openAreaEditor: onEditArea()
        case .confirmRooms: confirming = .toRooms
        case .confirmArea: confirming = .toArea
        case .none: break
        }
    }

    // MARK: Rooms setup

    @ViewBuilder private var roomsSetup: some View {
        let hasRooms = !controller.vacuum.zones.isEmpty
        let passes = controller.passesSetting
        if hasRooms || passes != nil {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                // Selected Rooms has no glyph, so the hairline under it starts at its text.
                ModuleList(hasGlyphs: !hasRooms) {
                    if hasRooms { selectedRooms }
                    if let passes {
                        VacuumSettingRow(setting: passes) { controller.select(passes.entityId, option: $0) }
                    }
                }
                if hasRooms { VacuumDescription("The vacuum cleans the selected rooms in order.") }
            }
        }
        VacuumActionButton(action: controller.cleanAction) { controller.run(.clean) }
    }

    /// The selected rooms as numbered chips, or the Full Clean warning; opens the Rooms section (the web's Rooms
    /// target button did).
    private var selectedRooms: some View {
        let rooms = controller.selectedZones
        return Button(action: onOpenRooms) {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                HStack {
                    Text(rooms.isEmpty ? "Full Clean" : "Selected Rooms")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HassTokens.Ink.secondary)
                    Spacer(minLength: HassTokens.Spacing.s)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(HassTokens.Ink.secondary)
                }
                if rooms.isEmpty {
                    InlineAlert("No rooms are selected, and no areas are drawn. If you begin cleaning, the robot vacuum will attempt to clean every mapped area.")
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(rooms.enumerated()), id: \.element.id) { index, room in
                            VacuumOrderChip(order: index + 1, title: room.title)
                        }
                    }
                }
            }
            .padding(.horizontal, HassTokens.Spacing.l)
            .padding(.top, HassTokens.Spacing.m)
            .padding(.bottom, HassTokens.Spacing.l)
            .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rooms.isEmpty ? "Full Clean" : "Selected Rooms")
        .accessibilityValue(rooms.isEmpty
            ? "No rooms are selected. Cleaning starts on every mapped area."
            : rooms.enumerated().map { "\($0 + 1). \($1.title)" }.joined(separator: ", "))
        .accessibilityHint("Opens the Rooms section.")
        .accessibilityIdentifier("vacuum.selectedRooms")
    }

    // MARK: Area setup

    @ViewBuilder private var areaSetup: some View {
        VacuumDescription("Draw one rectangular cleaning area on the map. The vacuum will use the mode, suction, water, and pass settings shown below.")
        HStack(alignment: .top, spacing: 10) {
            VacuumActionButton(action: .init(kind: .cleanArea, title: "Edit Area", icon: "mdi:pencil", tone: .neutral, detail: nil,
                                             isDisabled: controller.normalCommandsDisabled || !mapState.isReady),
                               identifier: "vacuum.area.edit", perform: onEditArea)
            VacuumActionButton(action: .init(kind: .cleanArea, title: "Clear Area", icon: "mdi:delete-outline", tone: .neutral, detail: nil, isDisabled: false),
                               identifier: "vacuum.area.clearSelection") { controller.areaSelection = nil }
        }
        if controller.services != nil && !controller.areaServiceReady, let script = controller.vacuum.areaCleaning?.script {
            VacuumDescription("Local preview only: \(script) is not installed in Home Assistant, so starting an area clean is disabled.")
        }
        if let passes = controller.passesSetting {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                ModuleList {
                    VacuumSettingRow(setting: passes) { controller.select(passes.entityId, option: $0) }
                }
                VacuumDescription("These settings are confirmed in Home Assistant before the area-cleaning command is sent.")
            }
        } else {
            VacuumDescription("These settings are confirmed in Home Assistant before the area-cleaning command is sent.")
        }
        VacuumActionButton(action: controller.areaCleanAction(mapReady: mapState.isReady, selectionAllowed: mapState.allows(controller.areaSelection))) {
            controller.run(.cleanArea, pixelSize: mapState.scene?.interactionGeometry.pixelSize)
        }
    }
}

// MARK: - Rooms

/// Ordered room toggles (web `VacuumZones`; mockup n6-vacuum-rooms): dark cards, white with a black order badge
/// once chosen.
struct VacuumRoomsTab: View {
    var controller: VacuumController
    @State private var pendingZone: VacuumConfig.Zone?
    @ScaledMetric(relativeTo: .subheadline) private var minCellWidth: CGFloat = 150
    /// Room cards are tile-sized (76 pt minimum, icon above the title), larger than the web's 58 px buttons, so
    /// the two-column iPhone grid reads as tappable cards (owner, 2026-10-13). A floor, not scaled: larger text grows the
    /// card through its content. HIG: Layout, Buttons.
    private let cardHeight: CGFloat = 76

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            ForEach(controller.vacuum.zoneDescription, id: \.self) { VacuumDescription($0) }
            VacuumDescription("Rooms are cleaned in the order you select them. The numbered badges show the cleaning sequence.")
            DynamicGridLayout(minCellWidth: minCellWidth, maxColumns: 2, spacing: HassTokens.Spacing.s, equalRowHeights: true) {
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
        let editable = controller.roomsEditable
        let ink = selected ? VacuumStyle.selectedInk : HassTokens.Ink.primary
        return Button {
            if controller.roomToggleNeedsConfirmation(zone) { pendingZone = zone } else { controller.toggleRoom(zone) }
        } label: {
            // Tile layout (icon and order badge on top, title below) so the title gets the card's full width:
            // beside the icon and badge, "Kitchen" broke mid-word on iPhone.
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                HStack(alignment: .top) {
                    Image(systemName: VacuumStyle.symbol(zone.icon))
                        .font(.title3)
                        // A locked card dims its glyph only; the title keeps its contrast (entity-tile pattern).
                        .foregroundStyle(selected ? VacuumStyle.selectedInk : HassTokens.Ink.secondary)
                        .opacity(editable ? 1 : 0.5)
                    Spacer(minLength: HassTokens.Spacing.xs)
                    if let order { VacuumOrderBadge(order: order) }
                }
                Text(zone.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(HassTokens.Spacing.m)
            // Fills the row the grid proposes, so cards in a row match the tallest title.
            .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: .infinity, alignment: .topLeading)
            .background(selected ? VacuumStyle.selectedFill : HassTokens.Surface.sheetCell, in: VacuumStyle.cardShape)
            .contentShape(VacuumStyle.cardShape)
        }
        .buttonStyle(.plain)
        .disabled(!editable)
        .accessibilityLabel(order.map { "\(zone.title), cleaning order \($0)" } ?? zone.title)
        .accessibilityValue(selected ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier("vacuum.room.\(zone.entityId)")
    }
}

// MARK: - Auto-clean

/// Rooms the coordinator skips (web `VacuumAutoCleanDisabledRooms`; mockup n6-vacuum-autoclean): a checkmark list
/// whose checked rooms read "Skipped" and are hatched on the map.
struct VacuumAutoCleanTab: View {
    var controller: VacuumController

    var body: some View {
        VacuumSection("Disabled Auto-Clean Rooms",
                      footer: "Checked rooms are skipped when the coordinator starts an automatic away clean. Use this for closed doors, guests, or projects on the floor; manual selected-room cleans still use the Rooms section.") {
            ModuleList {
                ForEach(controller.vacuum.autoCleanDisabledRooms) { room in
                    row(room)
                }
            }
        }
    }

    private func row(_ room: VacuumConfig.AutoCleanRoom) -> some View {
        let skipped = controller.isAutoCleanDisabled(room)
        let unavailable = VacuumStatusResolver.isUnavailable(controller.store.entity(room.entityId).state?.state)
        return Button { controller.toggleAutoClean(room) } label: {
            ModuleRow(room.title, subtitle: unavailable ? "Unavailable" : skipped ? "Skipped" : nil,
                      symbol: VacuumStyle.symbol(room.icon)) {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(HassTokens.Ink.action)
                    .opacity(skipped ? 1 : 0)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(ModuleRowButtonStyle())
        .disabled(unavailable)
        .accessibilityLabel("\(room.title) auto-clean")
        .accessibilityValue(unavailable ? "Unavailable" : skipped ? "Skipped" : "Included")
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier("vacuum.autoCleanRoom.\(room.entityId)")
    }
}

// MARK: - Dock

/// Dock controls (web `VacuumDockControlsSection`; mockup n6-vacuum-dock): each command is a row with a blue title and
/// what it does.
struct VacuumActionsTab: View {
    var controller: VacuumController

    var body: some View {
        let actions = controller.dockActions
        let preparing = controller.dockPreparationActive && controller.vacuum.dockControls != nil
        if !actions.isEmpty || controller.dockPreparationActive {
            VacuumSection("Dock Controls") {
                ModuleList {
                    if preparing {
                        ModuleRow("Washing Mop Pads",
                                  subtitle: "The dock is washing the mop pads for the current cleaning session. To stop, use Cancel Cleaning Session on the Controls section.",
                                  symbol: VacuumStyle.symbol("mdi:water"), glyph: VacuumStyle.color(.active))
                            .accessibilityElement(children: .combine)
                    }
                    ForEach(actions) { action in
                        row(action)
                    }
                }
                if controller.vacuum.dockControls != nil && !controller.mopAttached {
                    InlineAlert("Attach the mop pads before cleaning or drying them at the dock.")
                        .padding(.horizontal, HassTokens.Spacing.l)
                }
                if controller.vacuum.dockControls != nil && controller.services != nil && !controller.dockBridgeAvailable {
                    InlineAlert("Dock cleaning and drying controls will be available after Home Assistant restarts.")
                        .padding(.horizontal, HassTokens.Spacing.l)
                }
            }
        }
    }

    private func row(_ action: VacuumController.Action) -> some View {
        let tint = Self.tint(action)
        return Button { controller.run(action.kind) } label: {
            VacuumActionRow(symbol: VacuumStyle.symbol(action.icon), tint: tint, title: action.title,
                            titleColor: action.isDisabled ? HassTokens.Ink.secondary : HassTokens.Ink.action, subtitle: action.detail)
        }
        .buttonStyle(ModuleRowButtonStyle())
        .disabled(action.isDisabled)
        .accessibilityLabel(action.title)
        .accessibilityHint(action.detail ?? "")
        .accessibilityIdentifier("vacuum.action.\(action.kind.rawValue)")
    }

    /// A dock command's glyph: G's text-action blue, the tone's colour for Stop, grey while it is unavailable.
    static func tint(_ action: VacuumController.Action) -> Color {
        guard !action.isDisabled else { return HassTokens.Ink.secondary }
        return switch action.tone {
        case .warning: HassTokens.Ink.warning
        case .danger: HassTokens.Ink.danger
        case .primary, .neutral: HassTokens.Ink.action
        }
    }
}

// MARK: - Info

/// Bin state and consumables (web `VacuumConsumables`; mockup n6-vacuum-info): rows with the value trailing, orange
/// when it is soon and red when it is due.
struct VacuumInfoTab: View {
    var controller: VacuumController

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
            group("Bin State", controller.vacuum.consumables.filter { $0.valueKind == .status })
            group("Consumables", controller.vacuum.consumables.filter { $0.valueKind == .duration })
        }
    }

    @ViewBuilder private func group(_ title: String, _ consumables: [VacuumConfig.Consumable]) -> some View {
        if !consumables.isEmpty {
            VacuumSection(title) {
                ModuleList {
                    ForEach(consumables) { consumable in
                        row(consumable)
                    }
                }
            }
        }
    }

    private func row(_ consumable: VacuumConfig.Consumable) -> some View {
        let entity = controller.store.entity(consumable.entityId).state
        let visual = VacuumVisual.consumable(consumable, state: entity?.state)
        let value = VacuumFormat.consumable(consumable, state: entity?.state, unit: entity?.attributes["unit_of_measurement"]?.string)
        let tint = Self.tint(visual.tone)
        return ModuleRow(consumable.title, symbol: VacuumStyle.symbol(visual.icon), glyph: tint) {
            Text(value)
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(consumable.title)
        .accessibilityValue(value)
    }

    /// Soon is orange and due is red (direction G, Colour); everything else, OK included, stays neutral.
    static func tint(_ tone: VacuumTone) -> Color {
        switch tone {
        case .warning, .danger: VacuumStyle.color(tone)
        default: HassTokens.Ink.secondary
        }
    }
}
