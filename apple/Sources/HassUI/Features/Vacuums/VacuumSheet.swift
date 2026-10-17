import HassCore
import HassDesign
import SwiftUI

/// The vacuum sheet (pattern: `.agents/patterns/vacuum-sheet.md`; web `VacuumModal`; direction G mockups
/// n6-vacuum-*).
///
/// Map and status lead, the section's panel follows, and the sections sit in the bottom glass section bar
/// (``ModalTabBar``, symbols only at five sections). Where a split is allowed (iPad and unfolded iPhone Duo in
/// landscape) and the sheet is wide enough, the map and status take a leading column and the tabs scroll in the
/// trailing one; everywhere else it is one scrolling column. The area editor and the cleaning report push onto
/// the sheet's navigation stack.
public struct VacuumSheet: View {
    @State private var controller: VacuumController
    @State private var mapState: VacuumMapState
    @State private var content: VacuumSheetContent
    @State private var path: [Route] = []
    /// The navigation bar's height over the tab column's scroll view.
    @State private var barInset: CGFloat = 0
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
        _content = State(initialValue: VacuumSheetContent(tab: initialTab, controller: controller))
        _window = State(initialValue: window ?? WindowMetrics())
        self.server = server
        self.catalog = catalog
        fixedServices = services
    }

    private var pictureURL: URL? {
        guard let server else { return nil }
        return ValetudoMapLoader.pictureURL(controller.store.entity(controller.vacuum.mapCameraEntityId).state, server: server)
    }

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
                                    .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { barInset = $0 }
                            }
                            .coordinateSpace(.named(VacuumSheetLayout.tabScrollSpace))
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
                            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { barInset = $0 }
                            .coordinateSpace(.named(VacuumSheetLayout.tabScrollSpace))
                        }
                    }
                }
                .accessibilityIdentifier(twoColumns ? "vacuum.layout.twoColumn" : "vacuum.layout.singleColumn")
            }
            .background { WindowMetricsReader(metrics: $window) }
            .modalChrome()
            .navigationTitle("\(controller.vacuum.title) Robot Vacuum")
            .inlineNavigationTitle()
            .modifier(VacuumSheetChrome(controller: controller, content: content))
            .toolbar { SheetCloseItem { dismiss() } }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .areaEditor: VacuumAreaEditor(controller: controller, mapState: mapState).modalChrome()
                case let .report(box): VacuumOutcomeDetailView(vacuum: controller.vacuum, contract: box.contract).modalChrome()
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
        VacuumMapPanel(controller: controller, mapState: mapState, content: content, pictureURL: pictureURL,
                       areaVisible: controller.areaSelection != nil) { contract in
            path.append(.report(VacuumOutcomeContractBox(contract)))
        }
    }

    private func tabColumn(reader: ScrollViewProxy) -> some View {
        VacuumTabColumn(controller: controller, mapState: mapState, content: content, reader: reader, barInset: barInset) {
            path.append(.areaEditor)
        }
    }
}

/// The sheet's tab and runtime-mode state. It lives outside the sheet's body, so switching tabs redraws only the
/// tab column and never the map canvas (a full sheet redraw per tab change made switching stutter, owner report
/// 2026-10-13).
@MainActor
@Observable
final class VacuumSheetContent {
    /// What the tab column draws: a tab in a runtime mode.
    struct Key: Equatable {
        var tab: VacuumTab
        var mode: VacuumRuntimeMode
    }

    /// The tab the reader picked.
    var requestedTab: VacuumTab
    /// Fades the column between keys. A change of runtime mode (a clean starting or ending) also animates the layout,
    /// so the setup collapses and the tab control drops or regains its tabs while the content is hidden.
    let swap: SmoothContentSwap<Key>
    /// Bumped when a tab swap should bring the tab control back to the top of the column.
    private(set) var scrollResets = 0

    init(tab: VacuumTab, controller: VacuumController, animator: SmoothContentSwap<Key>.Animator? = nil) {
        requestedTab = tab
        let initial = Self.key(requested: tab, controller: controller)
        swap = animator.map { SmoothContentSwap(initial, animator: $0) } ?? SmoothContentSwap(initial)
        swap.timing.fadeOut = 0.13
        swap.timing.fadeIn = 0.17
        swap.animatesLayout = { $0.mode != $1.mode }
        swap.didSwap = { [weak self] key in
            guard let self else { return }
            if key.tab != self.lastTab { scrollResets += 1 }
            lastTab = key.tab
        }
        lastTab = initial.tab
    }

    @ObservationIgnored private var lastTab: VacuumTab = .controls

    /// The requested tab in the live mode, or Controls when that mode hides it (web `vacuumModalTabsForMode`).
    static func key(requested: VacuumTab, controller: VacuumController) -> Key {
        let mode = controller.runtimeMode
        return Key(tab: controller.tabs(in: mode).contains(requested) ? requested : .controls, mode: mode)
    }

    /// The tab the control shows as selected: the reader's pick at once (the content follows after its fade).
    func selection(in tabs: [VacuumTab]) -> VacuumTab {
        tabs.contains(requestedTab) ? requestedTab : swap.displayed.tab
    }
}

/// The state line under the title and the bottom section bar. A modifier of its own, so a battery tick or a section
/// change redraws only the bar and the subtitle, never the map canvas.
struct VacuumSheetChrome: ViewModifier {
    var controller: VacuumController
    var content: VacuumSheetContent

    func body(content root: Content) -> some View {
        let tabs = controller.tabs(in: content.swap.displayed.mode)
        let symbol: (VacuumTab) -> String = { VacuumTabSymbols.symbol(for: $0) }
        // Always applied, even at one section: a conditional bar would rebuild the sheet's root (and the map) when a
        // clean starts or ends. Every configured vacuum has Controls plus Auto-Clean or Info.
        root
            .sheetSubtitle(Self.subtitle(state: controller.statusState, battery: controller.batteryLabel))
            .modalTabBar(tabs, label: "\(controller.vacuum.title) sections", title: \.title, symbol: symbol,
                         selection: Binding(get: { content.selection(in: tabs) }, set: { content.requestedTab = $0 }),
                         identifier: "vacuum.tabs")
    }

    /// "Docked · 100%", or the state alone while the battery is unknown (mockup n6-vacuum-sheet).
    static func subtitle(state: String, battery: String) -> String {
        let label = VacuumFormat.state(state)
        return battery == "Unknown" ? label : "\(label) · \(battery)"
    }
}

/// The displayed section's content (web `VacuumModalTabContent`'s right pane); the section bar is
/// ``VacuumSheetChrome``.
struct VacuumTabColumn: View {
    var controller: VacuumController
    var mapState: VacuumMapState
    var content: VacuumSheetContent
    var reader: ScrollViewProxy
    /// The navigation bar's height over the scroll view.
    var barInset: CGFloat
    var onEditArea: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The panel's top edge in the scroll view.
    @State private var panelTop: CGFloat = .infinity

    var body: some View {
        let shown = content.swap.displayed
        let target = VacuumSheetContent.key(requested: content.requestedTab, controller: controller)
        panel(shown)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(content.swap.isHidden ? 0 : 1)
            .allowsHitTesting(!content.swap.isHidden)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("vacuum.tabContent")
            .id(VacuumSheetLayout.tabTopID)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named(VacuumSheetLayout.tabScrollSpace)).minY
            } action: { panelTop = $0 }
            .onChange(of: target) { _, next in
                if next.tab != content.requestedTab { content.requestedTab = next.tab }
                content.swap.show(next, reduceMotion: reduceMotion)
            }
            .onChange(of: content.scrollResets) { _, _ in
                // Only when the panel's top has scrolled under the bar or off the top, so a new section would open
                // mid-content; scrolling on every change jumped the sheet (owner report 2026-10-13).
                if panelTop < barInset { reader.scrollTo(VacuumSheetLayout.tabTopID, anchor: .top) }
            }
    }

    @ViewBuilder private func panel(_ shown: VacuumSheetContent.Key) -> some View {
        switch shown.tab {
        case .controls:
            VacuumControlsTab(controller: controller, mapState: mapState, mode: shown.mode,
                              onOpenRooms: { if controller.tabs.contains(.zones) { content.requestedTab = .zones } },
                              onEditArea: onEditArea)
        case .zones: VacuumRoomsTab(controller: controller)
        case .autoClean: VacuumAutoCleanTab(controller: controller)
        case .more: VacuumActionsTab(controller: controller)
        case .info: VacuumInfoTab(controller: controller)
        }
    }
}

/// Layout constants.
enum VacuumSheetLayout {
    static let tabTopID = "vacuum.tabTop"
    /// The scroll view holding the tab column.
    static let tabScrollSpace = "vacuum.tabScroll"
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
