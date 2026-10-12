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

/// Map, status pills, notices and the cleaning report: the sheet's leading pane (web `VacuumMapAndStatus`).
struct VacuumMapPanel: View {
    var controller: VacuumController
    var mapState: VacuumMapState
    var pictureURL: URL?
    var areaVisible: Bool
    var onOpenReport: (VacuumOutcomeContract) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.l) {
            VacuumMapFrame(controller: controller, mapState: mapState, area: areaVisible ? controller.areaSelection : nil)
                .task(id: MapTaskKey(url: pictureURL, live: controller.status.primaryAvailable)) {
                    await mapState.loader.run(url: pictureURL, live: controller.status.primaryAvailable)
                }
                .onChange(of: mapState.loader.map) { _, _ in mapState.refresh() }
                .onChange(of: mapState.loader.provenance) { _, _ in mapState.refresh() }
            if mapState.loader.provenance == .reported {
                VacuumNotice(mapState.loader.map?.robotPosition == nil ? "Last Reported Map" : "Last Reported Position", tone: .warning,
                             text: "This is the last map the vacuum reported before contact was lost. The exact report time is unknown, and the vacuum may have been moved since then.")
            }
            VacuumStatusSummary(controller: controller, mapProvenance: mapState.loader.provenance)
            VacuumCleaningReport(controller: controller, onOpen: onOpenReport)
        }
    }

    private struct MapTaskKey: Hashable { var url: URL?; var live: Bool }
}

/// The map frame with its Locate button, loading and unavailable states.
struct VacuumMapFrame: View {
    var controller: VacuumController
    var mapState: VacuumMapState
    var area: MapGridRect?

    var body: some View {
        let scene = mapState.scene
        ZStack(alignment: .bottomTrailing) {
            if let scene {
                GeometryReader { proxy in
                    ValetudoMapCanvas(scene: scene, roomOrders: roomOrders, area: area)
                        .contentShape(Rectangle())
                        .onTapGesture(coordinateSpace: .local) { location in
                            guard roomsTappable, let room = scene.room(at: location, size: proxy.size),
                                  let zone = controller.vacuum.zones.first(where: { $0.entityId == room.entityId }) else { return }
                            toggle(zone)
                        }
                }
                .aspectRatio(scene.aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 420)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(controller.vacuum.title) Valetudo map")
                .accessibilityValue(mapAccessibilityValue)
                .accessibilityIdentifier("vacuum.map")
            } else {
                fallback
            }
            if controller.status.primaryAvailable {
                Button { controller.locate() } label: {
                    Label("Locate", systemImage: "mappin.and.ellipse")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, HassTokens.Spacing.m)
                        .frame(minHeight: HassTokens.minTarget)
                        .background(.regularMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(HassTokens.Ink.primary)
                .padding(HassTokens.Spacing.s)
                .accessibilityHint("Asks the robot to play a sound.")
                .accessibilityIdentifier("vacuum.locate")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous))
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
                ProgressView()
                Text(controller.status.primaryAvailable ? "Loading Current Map…" : "Loading Last Vacuum Map Position…")
                    .font(.subheadline)
            }
        }
        .foregroundStyle(Color.white)
        .padding(HassTokens.Spacing.l)
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(ValetudoMapScene.color(MapRGBA(6, 12, 18, 0.9)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("vacuum.map.fallback")
    }
}

// MARK: - Status

/// Status pills and notices (web `VacuumStatusSummary`).
struct VacuumStatusSummary: View {
    var controller: VacuumController
    var mapProvenance: ValetudoMapProvenance
    @ScaledMetric(relativeTo: .subheadline) private var minPillWidth: CGFloat = 150

    var body: some View {
        let status = controller.status
        let state = controller.statusState
        let stateLabel = VacuumFormat.state(state)
        let visual = VacuumVisual.state(state)
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            DynamicGridLayout(minCellWidth: minPillWidth, maxColumns: 2) {
                VacuumInfoPill(icon: visual.icon, label: "Status", value: stateLabel, tone: visual.tone)
                    .accessibilityIdentifier("vacuum.status")
                VacuumInfoPill(icon: "mdi:battery", label: "Battery", value: controller.batteryLabel,
                               tone: status.primaryAvailable ? .neutral : .unavailable)
                if controller.vacuum.dockControls != nil {
                    let dock = VacuumVisual.dock(controller.dockState)
                    VacuumInfoPill(icon: dock.icon, label: "Dock Status", value: controller.dockLabel,
                                   tone: status.primaryAvailable ? dock.tone : .unavailable)
                }
            }
            if !status.primaryAvailable && mapProvenance != .reported {
                VacuumNotice(stateLabel, text: "Home Assistant does not have a current status for the vacuum.")
            }
            if status.primaryAvailable && status.currentIssue.status == .unknown {
                VacuumNotice("Error Source Unavailable", tone: .warning,
                             text: "The current vacuum error status cannot be confirmed because its error source is unavailable.")
            }
            if status.currentIssue.status == .present, let raw = status.currentIssue.raw {
                VacuumNotice("Current Issue", tone: .warning, text: raw)
            }
            ForEach(status.activeConditions, id: \.code) { condition in
                VacuumNotice("Home Assistant Condition", text: VacuumStatusResolver.conditionText(condition))
            }
            if let last = status.lastIssue,
               !status.primaryAvailable || status.currentIssue.status == .unknown || status.policyReason == "source_unreadable" {
                VacuumNotice("Previous Issue",
                             text: "Previous Vacuum Issue · \(last.raw) • Observed \(last.reportedAt.formatted(date: .abbreviated, time: .shortened))")
            }
        }
    }
}

// MARK: - Cleaning report

/// The coordinator's while-away report (web `VacuumWhileAwaySection`).
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
            VacuumSection("\(title) (\(contract.rooms.count))") {
                GlassTile(title: day, subtitle: VacuumOutcomeText.overviewSubtitle(counts).nilIfEmpty,
                          symbol: VacuumStyle.symbol(visual.icon), tint: VacuumStyle.color(visual.tone), isActive: true, kind: .navigate) {
                    onOpen(contract)
                }
                .accessibilityLabel("Open \(controller.vacuum.title) Automatic Cleaning Report for \(day)")
                .accessibilityIdentifier("vacuum.report")
            }
        case let .legacy(cleaned, issues):
            VacuumSection(title) { lists(cleaned: cleaned, issues: issues) }
        case let .protocolNotice(kind, cleaned, issues):
            VacuumSection(title) {
                let copy = VacuumOutcomeText.protocolTitle(kind)
                VacuumNotice(copy.title, tone: .warning, text: copy.description)
                if !cleaned.isEmpty || !issues.isEmpty {
                    DisclosureGroup("Unstructured Report Details", isExpanded: $legacyOpen) {
                        VacuumDescription("These details may be inconsistent with the typed status.")
                        lists(cleaned: cleaned, issues: issues)
                    }
                    .accessibilityLabel("\(legacyOpen ? "Hide" : "Show") \(controller.vacuum.title) Unstructured Report Details")
                }
            }
        }
    }

    @ViewBuilder private func lists(cleaned: [String], issues: [String]) -> some View {
        if !cleaned.isEmpty {
            VacuumNotice("Cleaned", tone: .ok, text: cleaned.map { "• " + $0 }.joined(separator: "\n"))
        }
        if !issues.isEmpty {
            VacuumNotice("Issues", tone: .warning, text: issues.map { "• " + $0 }.joined(separator: "\n"))
        }
    }
}

/// The report detail page: one chip per room (web `VacuumOutcomeDetail`).
struct VacuumOutcomeDetailView: View {
    var vacuum: VacuumConfig
    var contract: VacuumOutcomeContract
    @ScaledMetric(relativeTo: .subheadline) private var minChipWidth: CGFloat = 220

    var body: some View {
        let names = VacuumOutcomeText.roomNames(contract, vacuum: vacuum)
        ScrollView {
            DynamicGridLayout(minCellWidth: minChipWidth, maxColumns: 2) {
                ForEach(contract.rooms) { room in
                    let visual = VacuumOutcomeText.statusVisual(room.status)
                    VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                        HStack(spacing: HassTokens.Spacing.s) {
                            Image(systemName: VacuumStyle.symbol(visual.icon)).foregroundStyle(VacuumStyle.color(visual.tone))
                            Text(room.roomName).font(.subheadline.weight(.semibold)).foregroundStyle(HassTokens.Ink.primary)
                            Spacer(minLength: HassTokens.Spacing.s)
                            Text(VacuumOutcomeText.statusTitle(room.status)).font(.footnote.weight(.semibold)).foregroundStyle(HassTokens.Ink.secondary)
                        }
                        Text(VacuumOutcomeText.detail(room, roomNames: names))
                            .font(.footnote)
                            .foregroundStyle(HassTokens.Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(HassTokens.Spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(VacuumStyle.rowFill, in: VacuumStyle.rowShape)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("vacuum.outcome.\(room.roomId)")
                }
            }
            .padding(HassTokens.Spacing.l)
        }
        .navigationTitle("\(vacuum.title) · Automatic Cleaning Report (\(contract.rooms.count))")
        .inlineNavigationTitle()
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
