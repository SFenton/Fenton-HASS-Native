import HassCore
import HassDesign
import SwiftUI

/// The vacuum sheet (pattern: `.agents/patterns/vacuum-sheet.md`; web `VacuumModal`).
///
/// Map and status lead, the tab panel follows. Where a split is allowed (iPad and unfolded iPhone Duo in
/// landscape) and the sheet is wide enough, the map and status take a leading column and the tabs scroll in the
/// trailing one; everywhere else it is one scrolling column. The area editor and the cleaning report push onto
/// the sheet's navigation stack.
public struct VacuumSheet: View {
    @State private var controller: VacuumController
    @State private var mapState: VacuumMapState
    @State private var tab: VacuumTab = .controls
    @State private var path: [Route] = []
    @State private var window = WindowMetrics()
    private let server: HassServer?
    private let catalog: (any HassServiceCatalog)?
    private let fixedServices: Set<String>?
    @Environment(\.dismiss) private var dismiss

    enum Route: Hashable {
        case areaEditor
        case report(VacuumOutcomeContractBox)
    }

    /// Creates the sheet on the app's connection.
    public init(vacuum: VacuumConfig, connection: HassConnection) {
        self.init(controller: VacuumController(vacuum: vacuum, store: connection.store, caller: connection),
                  loader: ValetudoMapLoader(), server: connection.server, catalog: connection, services: nil)
    }

    /// Creates the sheet on an existing controller (gallery and hosted tests).
    /// - Parameters:
    ///   - loader: Supplies the map; a gallery loader holds a fixture map and no `server`.
    ///   - server: Resolves the map camera's picture; `nil` keeps the loader's map.
    ///   - catalog: Reads Home Assistant's services; `services` sets them directly instead.
    init(controller: VacuumController, loader: ValetudoMapLoader, server: HassServer?, catalog: (any HassServiceCatalog)?,
         services: Set<String>?, initialTab: VacuumTab = .controls, window: WindowMetrics? = nil) {
        _controller = State(initialValue: controller)
        _mapState = State(initialValue: VacuumMapState(vacuum: controller.vacuum, loader: loader))
        _tab = State(initialValue: initialTab)
        _window = State(initialValue: window ?? WindowMetrics())
        self.server = server
        self.catalog = catalog
        fixedServices = services
    }

    private var pictureURL: URL? {
        guard let server else { return nil }
        return ValetudoMapLoader.pictureURL(controller.store.entity(controller.vacuum.mapCameraEntityId).state, server: server)
    }

    /// The selected tab, or Controls when the mode hides it.
    private var shownTab: VacuumTab { controller.tabs.contains(tab) ? tab : .controls }

    public var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { proxy in
                let twoColumns = MediaRemoteLayout.usesTwoColumns(
                    window: window.size ?? proxy.size, isRegularWidth: window.isRegularWidth, container: proxy.size)
                Group {
                    if twoColumns {
                        HStack(alignment: .top, spacing: 0) {
                            ScrollView { mapColumn.padding(HassTokens.Spacing.l) }
                                .frame(width: proxy.size.width / 2)
                            ScrollViewReader { reader in
                                ScrollView { tabColumn(reader: reader).padding(HassTokens.Spacing.l) }
                            }
                            .frame(width: proxy.size.width / 2)
                        }
                    } else {
                        ScrollViewReader { reader in
                            ScrollView {
                                VStack(spacing: HassTokens.Spacing.xl) {
                                    mapColumn
                                    tabColumn(reader: reader)
                                }
                                .frame(maxWidth: 640)
                                .frame(maxWidth: .infinity)
                                .padding(HassTokens.Spacing.l)
                            }
                        }
                    }
                }
                .accessibilityIdentifier(twoColumns ? "vacuum.layout.twoColumn" : "vacuum.layout.singleColumn")
            }
            .background { WindowMetricsReader(metrics: $window) }
            .navigationTitle("\(controller.vacuum.title) Robot Vacuum")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .areaEditor: VacuumAreaEditor(controller: controller, mapState: mapState)
                case let .report(box): VacuumOutcomeDetailView(vacuum: controller.vacuum, contract: box.contract)
                }
            }
        }
        .task { await loadServices() }
    }

    private func loadServices() async {
        if let fixedServices { controller.services = fixedServices; return }
        guard let catalog, controller.services == nil else { return }
        controller.services = try? await catalog.serviceNames()
    }

    // MARK: - Columns

    private var mapColumn: some View {
        VacuumMapPanel(controller: controller, mapState: mapState, pictureURL: pictureURL,
                       areaVisible: controller.areaSelection != nil) { contract in
            path.append(.report(VacuumOutcomeContractBox(contract)))
        }
    }

    private func tabColumn(reader: ScrollViewProxy) -> some View {
        let tabs = controller.tabs
        return VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
            if tabs.count > 1 {
                VacuumTabPicker(tabs: tabs, title: controller.vacuum.title, selection: Binding(get: { shownTab }, set: { tab = $0 }))
                    .id(VacuumSheetLayout.tabTopID)
            }
            switch shownTab {
            case .controls:
                VacuumControlsTab(controller: controller, mapState: mapState,
                                  onOpenRooms: { if tabs.contains(.zones) { tab = .zones } },
                                  onEditArea: { path.append(.areaEditor) })
            case .zones: VacuumRoomsTab(controller: controller)
            case .autoClean: VacuumAutoCleanTab(controller: controller)
            case .more: VacuumActionsTab(controller: controller)
            case .info: VacuumInfoTab(controller: controller)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: tab) { _, _ in reader.scrollTo(VacuumSheetLayout.tabTopID, anchor: .top) }
    }
}

/// Layout constants.
enum VacuumSheetLayout {
    static let tabTopID = "vacuum.tabTop"
}

/// Wraps a report so it can ride the navigation path (equal by day and room statuses).
struct VacuumOutcomeContractBox: Hashable {
    let contract: VacuumOutcomeContract
    init(_ contract: VacuumOutcomeContract) { self.contract = contract }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.contract == rhs.contract }
    func hash(into hasher: inout Hasher) {
        hasher.combine(contract.day)
        for room in contract.rooms { hasher.combine(room.roomId); hasher.combine(room.status.rawValue) }
    }
}

public extension View {
    /// Presents the vacuum sheet like the remote: full height, drag indicator, page-size on iPad.
    func vacuumPresentation() -> some View { mediaRemotePresentation() }
}
