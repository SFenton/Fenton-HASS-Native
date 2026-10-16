import HassCore
import HassDesign
import Observation
import SwiftUI

/// The map for one sheet: the loader plus the prepared scene, rebuilt only when the map changes.
@MainActor
@Observable
final class VacuumMapState {
    let loader: ValetudoMapLoader
    private(set) var scene: ValetudoMapScene?
    @ObservationIgnored private let vacuum: VacuumConfig
    @ObservationIgnored private var sceneMap: ValetudoMap?
    @ObservationIgnored private var sceneProvenance: ValetudoMapProvenance = .none

    init(vacuum: VacuumConfig, loader: ValetudoMapLoader) {
        self.vacuum = vacuum
        self.loader = loader
        refresh()
    }

    /// Rebuilds the scene if the loader holds a different map.
    func refresh() {
        guard loader.map != sceneMap || loader.provenance != sceneProvenance else { return }
        sceneMap = loader.map
        sceneProvenance = loader.provenance
        scene = loader.map.map { ValetudoMapScene(map: $0, vacuum: vacuum, provenance: loader.provenance) }
    }

    /// A live map is loaded (area drawing needs one).
    var isReady: Bool { scene != nil && loader.provenance == .live }

    /// The area lies inside the focus crop (`selectionAllowed`).
    func allows(_ area: MapGridRect?) -> Bool {
        guard let area, let scene, scene.focus.mode == .focused else { return true }
        return ValetudoMapFocus.rect(area, isWithin: scene.focus.interactionBounds)
    }
}

/// Map, status chips, notices and the cleaning report: the sheet's leading pane (web `VacuumMapAndStatus`; mockup
/// n6-vacuum-sheet).
struct VacuumMapPanel: View {
    var controller: VacuumController
    var mapState: VacuumMapState
    /// The displayed section and runtime mode: the map marks skipped rooms on Auto-Clean and grows while a run is going.
    var content: VacuumSheetContent
    var pictureURL: URL?
    var areaVisible: Bool
    var onOpenReport: (VacuumOutcomeContract) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            VacuumMapFrame(controller: controller, mapState: mapState, content: content,
                           area: areaVisible ? controller.areaSelection : nil)
                .task(id: MapTaskKey(url: pictureURL, live: controller.status.primaryAvailable)) {
                    await mapState.loader.run(url: pictureURL, live: controller.status.primaryAvailable)
                }
                .onChange(of: mapState.loader.map) { _, _ in mapState.refresh() }
                .onChange(of: mapState.loader.provenance) { _, _ in mapState.refresh() }
            if mapState.loader.provenance == .reported {
                InlineAlert("\(mapState.loader.map?.robotPosition == nil ? "Last Reported Map" : "Last Reported Position"): This is the last map the vacuum reported before contact was lost. The exact report time is unknown, and the vacuum may have been moved since then.")
            }
            VacuumStatusSummary(controller: controller, mapProvenance: mapState.loader.provenance)
            VacuumCleaningReport(controller: controller, onOpen: onOpenReport)
        }
    }

    private struct MapTaskKey: Hashable { var url: URL?; var live: Bool }
}

/// The map card with its Locate button, loading and unavailable states (direction G, Controls: Vacuum map).
struct VacuumMapFrame: View {
    var controller: VacuumController
    var mapState: VacuumMapState
    var content: VacuumSheetContent
    var area: MapGridRect?

    /// The map's height limit: it grows while a run is going, when the controls below collapse to one card
    /// (mockup n6-vacuum-cleaning).
    static func maxHeight(_ mode: VacuumRuntimeMode) -> CGFloat { mode == .minimal ? 460 : 300 }

    var body: some View {
        let scene = mapState.scene
        let shown = content.swap.displayed
        ZStack(alignment: .topLeading) {
            if let scene {
                GeometryReader { proxy in
                    ValetudoMapCanvas(scene: scene,
                                      roomOrders: shown.tab == .autoClean ? [:] : roomOrders,
                                      skippedRooms: shown.tab == .autoClean ? skippedRooms : [],
                                      area: area)
                        .contentShape(Rectangle())
                        .onTapGesture(coordinateSpace: .local) { location in
                            guard roomsTappable, let room = scene.room(at: location, size: proxy.size),
                                  let zone = controller.vacuum.zones.first(where: { $0.entityId == room.entityId }) else { return }
                            toggle(zone)
                        }
                }
                .aspectRatio(scene.aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: Self.maxHeight(shown.mode))
                .padding(HassTokens.Spacing.m)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(controller.vacuum.title) Valetudo map")
                .accessibilityValue(mapAccessibilityValue)
                .accessibilityIdentifier("vacuum.map")
            } else {
                fallback
            }
            if controller.status.primaryAvailable {
                Button { controller.locate() } label: {
                    Image(systemName: "scope")
                        .font(.body.weight(.semibold))
                        .frame(width: HassTokens.minTarget, height: HassTokens.minTarget)
                        .navigationGlass(in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(HassTokens.Ink.primary)
                .padding(HassTokens.Spacing.s)
                .accessibilityLabel("Locate")
                .accessibilityHint("Asks the robot to play a sound.")
                .accessibilityIdentifier("vacuum.locate")
            }
        }
        .frame(maxWidth: .infinity)
        .background(ValetudoMapScene.color(ValetudoMapScene.Palette.ground))
        .clipShape(VacuumStyle.groupShape)
        .alert("Switch to Rooms", isPresented: $confirmingRoom, presenting: pendingZone) { zone in
            Button("Continue") { controller.toggleRoom(zone) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You have an area drawn right now. Switching to Rooms will discard that area. Are you sure you want to continue?")
        }
    }

    @State private var confirmingRoom = false
    @State private var pendingZone: VacuumConfig.Zone?

    private var roomsTappable: Bool { controller.vacuum.mapRoomSelection && controller.roomsEditable && mapState.loader.provenance == .live }

    private func toggle(_ zone: VacuumConfig.Zone) {
        if controller.roomToggleNeedsConfirmation(zone) {
            pendingZone = zone
            confirmingRoom = true
        } else {
            controller.toggleRoom(zone)
        }
    }

    private var roomOrders: [String: Int] {
        Dictionary(uniqueKeysWithValues: controller.selectedZones.enumerated().map { ($1.entityId, $0 + 1) })
    }

    /// Rooms the coordinator skips on automatic cleans, as map zones (matched by title, which the Main Floor's
    /// auto-clean rooms and zones share).
    private var skippedRooms: Set<String> {
        let titles = Set(controller.vacuum.autoCleanDisabledRooms.filter { controller.isAutoCleanDisabled($0) }.map(\.title))
        return Set(controller.vacuum.zones.filter { titles.contains($0.title) }.map(\.entityId))
    }

    private var mapAccessibilityValue: String {
        let rooms = controller.selectedZones.map(\.title)
        return rooms.isEmpty ? "" : "Selected rooms: " + rooms.joined(separator: ", ")
    }

    @ViewBuilder private var fallback: some View {
        let unavailable = mapState.loader.failed || (!controller.status.primaryAvailable && mapState.loader.provenance == .none)
        VStack(spacing: HassTokens.Spacing.s) {
            if unavailable {
                Text("Map Unavailable").font(.headline)
                Text("Home Assistant cannot currently confirm the vacuum's map or position.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
            } else {
                ArcSpinner(.page).accessibilityHidden(true)
                Text(controller.status.primaryAvailable ? "Loading Current Map…" : "Loading Last Vacuum Map Position…")
                    .font(.subheadline)
            }
        }
        // The map card is always dark (`#262628`).
        .foregroundStyle(HassTokens.Ink.onDark)
        .padding(HassTokens.Spacing.l)
        .frame(maxWidth: .infinity, minHeight: 220)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("vacuum.map.fallback")
    }
}

// MARK: - Status

/// Status chips and notices (web `VacuumStatusSummary`; mockup n6-vacuum-sheet: Docked, 100%, Dock Idle).
struct VacuumStatusSummary: View {
    var controller: VacuumController
    var mapProvenance: ValetudoMapProvenance

    var body: some View {
        let status = controller.status
        let state = controller.statusState
        let stateLabel = VacuumFormat.state(state)
        let visual = VacuumVisual.state(state)
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            FlowLayout(spacing: HassTokens.Spacing.s) {
                VacuumStatusChip(symbol: Self.stateSymbol(state, visual: visual), tint: VacuumStyle.color(visual.tone),
                                 label: "Status", value: stateLabel)
                    .accessibilityIdentifier("vacuum.status")
                VacuumStatusChip(symbol: Self.batterySymbol(controller.batteryLabel),
                                 tint: status.primaryAvailable ? HassTokens.Ink.primary : HassTokens.Ink.secondary,
                                 label: "Battery", value: controller.batteryLabel)
                if controller.vacuum.dockControls != nil {
                    let dock = VacuumVisual.dock(controller.dockState)
                    let tone = status.primaryAvailable ? dock.tone : .unavailable
                    VacuumStatusChip(symbol: tone == .neutral || tone == .unavailable ? "ev.charger" : VacuumStyle.symbol(dock.icon),
                                     tint: tone == .neutral ? HassTokens.Ink.primary : VacuumStyle.color(tone),
                                     label: "Dock Status", value: "Dock \(controller.dockLabel)")
                }
            }
            if !status.primaryAvailable && mapProvenance != .reported {
                InfoBox(title: stateLabel, message: "Home Assistant does not have a current status for the vacuum.")
            }
            if status.primaryAvailable && status.currentIssue.status == .unknown {
                InlineAlert("Error Source Unavailable: The current vacuum error status cannot be confirmed because its error source is unavailable.")
            }
            if status.currentIssue.status == .present, let raw = status.currentIssue.raw {
                InlineAlert("Current Issue: \(raw)")
            }
            ForEach(status.activeConditions, id: \.code) { condition in
                InfoBox(title: "Home Assistant Condition", message: VacuumStatusResolver.conditionText(condition))
            }
            if let last = status.lastIssue,
               !status.primaryAvailable || status.currentIssue.status == .unknown || status.policyReason == "source_unreadable" {
                InfoBox(title: "Previous Issue",
                        message: "Previous Vacuum Issue · \(last.raw) · Observed \(last.reportedAt.formatted(date: .abbreviated, time: .shortened))")
            }
        }
    }

    /// Docked reads as a green check (mockup n6-vacuum-sheet); other states keep their own glyph.
    static func stateSymbol(_ state: String, visual: VacuumVisual) -> String {
        state.lowercased() == "docked" ? "checkmark.circle.fill" : VacuumStyle.symbol(visual.icon)
    }

    /// The battery glyph nearest the level in a label such as `87%`; the empty battery while the level is unknown.
    static func batterySymbol(_ label: String) -> String {
        guard label.hasSuffix("%"), let level = Double(label.dropLast()) else { return "battery.0percent" }
        return switch level {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

// MARK: - Cleaning report

/// The coordinator's while-away report (web `VacuumWhileAwaySection`; mockup n6-vacuum-info): one row that opens
/// the room details.
struct VacuumCleaningReport: View {
    var controller: VacuumController
    var onOpen: (VacuumOutcomeContract) -> Void
    @State private var legacyOpen = false

    var body: some View {
        let title = "\(controller.vacuum.title) Cleaning Report"
        switch controller.whileAway {
        case .empty:
            EmptyView()
        case let .typed(contract):
            let counts = VacuumOutcomeText.counts(contract)
            let visual = VacuumOutcomeText.overviewVisual(counts)
            let day = VacuumOutcomeText.day(contract.day)
            let overview = VacuumOutcomeText.overviewSubtitle(counts)
            VacuumSection("Cleaning Report") {
                ModuleList {
                    Button { onOpen(contract) } label: {
                        ModuleRow("\(title) (\(contract.rooms.count))",
                                  subtitle: overview.isEmpty ? day : "\(day) · \(overview)",
                                  symbol: VacuumStyle.symbol(visual.icon), glyph: VacuumStyle.color(visual.tone),
                                  showsChevron: true)
                    }
                    .buttonStyle(ModuleRowButtonStyle())
                    .accessibilityLabel("Open \(controller.vacuum.title) Automatic Cleaning Report for \(day)")
                    .accessibilityValue(overview)
                    .accessibilityIdentifier("vacuum.report")
                }
            }
        case let .legacy(cleaned, issues):
            VacuumSection(title) { lists(cleaned: cleaned, issues: issues) }
        case let .protocolNotice(kind, cleaned, issues):
            VacuumSection(title) {
                let copy = VacuumOutcomeText.protocolTitle(kind)
                InlineAlert("\(copy.title): \(copy.description)")
                if !cleaned.isEmpty || !issues.isEmpty {
                    DisclosureGroup("Unstructured Report Details", isExpanded: $legacyOpen) {
                        VacuumDescription("These details may be inconsistent with the typed status.")
                        lists(cleaned: cleaned, issues: issues)
                    }
                    .tint(HassTokens.Ink.action)
                    .padding(.horizontal, HassTokens.Spacing.l)
                    .accessibilityLabel("\(legacyOpen ? "Hide" : "Show") \(controller.vacuum.title) Unstructured Report Details")
                }
            }
        }
    }

    @ViewBuilder private func lists(cleaned: [String], issues: [String]) -> some View {
        if !cleaned.isEmpty {
            InfoBox(title: "Cleaned", message: cleaned.map { "• " + $0 }.joined(separator: "\n"), tone: .success)
        }
        if !issues.isEmpty {
            InlineAlert("Issues:\n" + issues.map { "• " + $0 }.joined(separator: "\n"))
        }
    }
}

/// The report detail page: one row per room (web `VacuumOutcomeDetail`).
struct VacuumOutcomeDetailView: View {
    var vacuum: VacuumConfig
    var contract: VacuumOutcomeContract

    var body: some View {
        let names = VacuumOutcomeText.roomNames(contract, vacuum: vacuum)
        ScrollView {
            ModuleList {
                ForEach(contract.rooms) { room in
                    let visual = VacuumOutcomeText.statusVisual(room.status)
                    ModuleRow(room.roomName, subtitle: VacuumOutcomeText.detail(room, roomNames: names),
                              symbol: VacuumStyle.symbol(visual.icon), glyph: VacuumStyle.color(visual.tone)) {
                        Text(VacuumOutcomeText.statusTitle(room.status))
                            .font(.subheadline)
                            .foregroundStyle(HassTokens.Ink.secondary)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("vacuum.outcome.\(room.roomId)")
                }
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(HassTokens.Spacing.l)
        }
        .navigationTitle("\(vacuum.title) · Automatic Cleaning Report (\(contract.rooms.count))")
        .inlineNavigationTitle()
    }
}
