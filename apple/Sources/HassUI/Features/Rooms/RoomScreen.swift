import HassCore
import HassDesign
import SwiftUI

/// A config-driven room page (web `SourceRoomPage`). Spec: `.agents/pages/rooms/spec.md`.
///
/// Status rail, then the room's sections in a responsive section grid (two columns where the window is wide), then
/// the sheet for whichever card was opened. Single page in every pose (owner's split rules).
struct RoomScreen: View {
    var page: RoomPage
    @Environment(EntityStore.self) private var store
    @Environment(HassConnection.self) private var connection: HassConnection?
    @Environment(\.roomServiceCaller) private var callerOverride
    @Environment(\.householdViewer) private var injectedViewer
    @State private var viewer: HouseholdResident?
    @State private var viewerIsAdminFlag = false

    var body: some View {
        if let caller = callerOverride ?? connection {
            RoomPageContent(page: page, store: store, caller: caller, imageServer: connection?.server, connection: connection)
                .environment(\.householdViewer, injectedViewer ?? viewer)
                .environment(\.householdViewerIsAdmin, viewerIsAdminFlag)
                .task {
                    // Personalized titles ("Your Side") need the signed-in user; the page shows plain titles until then.
                    guard injectedViewer == nil, let connection, let user = try? await connection.currentUser() else { return }
                    viewer = HouseholdResident.forUser(id: user.id)
                    viewerIsAdminFlag = user.isAdmin
                }
        } else {
            PlaceholderScreen(title: page.title, symbol: "house")
        }
    }
}

/// The page body on a fixed store and caller (hosted tests and the gallery build it directly).
struct RoomPageContent: View {
    @State private var controller: RoomController
    @State private var sheetCard: RoomCard?
    @State private var remote: MediaRemoteController?
    @State private var showsQuickLinks = false
    /// In the shell the header carries Quick Links on every page; the page keeps its own button only outside it.
    @Environment(ShellNavigator.self) private var shellNavigator: ShellNavigator?
    @State private var pendingRoute: HomeRoute?
    @State private var route: HomeRoute?
    @State private var deviceModal: RoomDeviceModal?
    /// A device sheet to open once the current one has closed (wake light → a bed's alarms).
    @State private var queuedModal: RoomDeviceModal?
    /// The Master Bedroom's wake light and beds, shared by its sheets (`.agents/patterns/bedroom-devices.md`).
    @State private var bedroom: BedroomDevices?
    @Environment(\.householdViewerIsAdmin) private var viewerIsAdmin
    /// One controller per bathroom fan, shared by its tile and sheet.
    @State private var fans: [String: BathroomFanController]
    private let imageServer: HassServer?
    private let connection: HassConnection?

    init(page: RoomPage, store: EntityStore, caller: any HassServiceCalling, imageServer: HassServer?,
         connection: HassConnection? = nil) {
        let controller = RoomController(page: page, store: store, caller: caller)
        _controller = State(initialValue: controller)
        var fans: [String: BathroomFanController] = [:]
        for card in page.allCards where card.control == .bathroomFan {
            if let config = BathroomFanConfig.forPowerEntity(card.entityId) {
                fans[card.entityId] = BathroomFanController(config: config, store: store, caller: caller)
            }
        }
        _fans = State(initialValue: fans)
        // Bedroom sheets read service responses; callers that cannot (the gallery's recorder) keep the generic tiles.
        let hasBedroom = page.allCards.contains { card in
            switch controller.sheet(for: card) {
            case .device(.wakeLight), .device(.bed): true
            default: false
            }
        }
        // Editing alarms waits until the signed-in user is known to be an administrator.
        _bedroom = State(initialValue: hasBedroom ? (caller as? any HassServiceResponding).map {
            BedroomDevices(store: store, caller: $0, canEdit: false)
        } : nil)
        self.imageServer = imageServer
        self.connection = connection
    }

    private var page: RoomPage { controller.page }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
                if !page.overviewCards.isEmpty {
                    RoomStatusRail(controller: controller, onOpen: open)
                }
                sections
                    .padding(.horizontal, HassTokens.Spacing.l)
            }
            .padding(.vertical, HassTokens.Spacing.m)
        }
        .scrollTelemetry("Room · \(page.id)")
        .accessibilityIdentifier("room.scroll.\(page.id)")
        .navigationTitle(page.title)
        .toolbar {
            if shellNavigator == nil {
                ToolbarItem(placement: .primaryAction) {
                    QuickLinksButton { showsQuickLinks = true }
                }
            }
        }
        .sheet(item: $sheetCard, content: cardSheet)
        .sheet(item: Binding(get: { remote.map { RemoteSelection(controller: $0) } }, set: { remote = $0?.controller }),
               content: remoteSheet)
        .sheet(isPresented: $showsQuickLinks, onDismiss: quickLinksDismissed, content: quickLinksSheet)
        .sheet(item: $deviceModal, onDismiss: deviceSheetDismissed, content: deviceSheet)
        .task { openLinkedSheet() }
        .onChange(of: shellNavigator?.pendingSheet) { openLinkedSheet() }
        .onChange(of: viewerIsAdmin, initial: true) { _, isAdmin in bedroom?.wakeLight.canEdit = isAdmin }
        .homeRouteDestination($route)
    }

    @ViewBuilder
    private var sections: some View {
        let visible = page.visibleSections
        let isKitchen = page.id == "kitchen"
        if visible.isEmpty && !isKitchen {
            ContentUnavailableView("Nothing Here Yet!", systemImage: SymbolMap.symbol(for: RoomNavigation.item(for: page.id)?.icon ?? "mdi:home"),
                                   description: Text("Once some devices are added to this room, we can display them here."))
                .accessibilityIdentifier("room.empty")
        } else {
            let count = visible.count + (isKitchen ? 1 : 0)
            DynamicGridLayout(minCellWidth: 340, maxColumns: 2, spacing: HassTokens.Spacing.xl) {
                if isKitchen {
                    KitchenGroceriesSection(controller: controller) { route = $0 }
                        .gridSpan(count == 1 ? 2 : 1)
                }
                ForEach(visible) { section in
                    RoomSectionView(controller: controller, section: section, imageServer: imageServer, fans: fans, bedroom: bedroom,
                                    onOpen: open)
                        .gridSpan(RoomSectionView.isFullWidth(section, sectionCount: count) ? 2 : 1)
                }
            }
        }
    }

    // MARK: Sheets

    func cardSheet(_ card: RoomCard) -> some View {
        RoomCardSheet(controller: controller, card: card)
            .hassSheet(.page, height: .full) // Navigates room to lights to a light
    }

    func remoteSheet(_ selection: RemoteSelection) -> some View {
        MediaRemoteSheet(controller: selection.controller, imageServer: imageServer, initialTab: .controls)
            .hassSheet(.page, height: .full) // A remote
    }

    func deviceSheet(_ modal: RoomDeviceModal) -> some View {
        RoomDeviceModalSheet(modal: modal, store: controller.store, caller: controller.caller, connection: connection) { side in
            if let bedroom { queuedModal = .bed(bedroom, side: side, tab: .alarms) }
        }
    }

    /// Opens the card a link's `#anchor` names (a Live Activity tap on a vacuum opens its sheet).
    func openLinkedSheet() {
        guard let anchor = shellNavigator?.takeSheet(forPage: page.id),
              let card = page.allCards.first(where: { $0.sheet == anchor }) else { return }
        open(card)
    }

    /// Opens a sheet queued while the last one was closing.
    func deviceSheetDismissed() {
        deviceModal = queuedModal
        queuedModal = nil
    }

    func quickLinksSheet() -> some View {
        QuickLinksSheet(caller: controller.caller) { pendingRoute = $0 }
    }

    /// Pushes the page Quick Links chose once the sheet has gone, so the push never races the dismissal.
    func quickLinksDismissed() {
        route = pendingRoute
        pendingRoute = nil
    }

    /// Opens a card: its remote sheet, its device lane's sheet, else its room sheet.
    func open(_ card: RoomCard) {
        switch Self.opening(card, controller: controller, hasConnection: connection != nil, fans: fans, bedroom: bedroom) {
        case let .remote(shared): remote = shared
        case let .device(modal): deviceModal = modal
        case .sheet: sheetCard = card
        }
    }

    /// Where opening a card goes: the shared remote sheet for remote cards, a device lane's sheet when one is wired
    /// (``RoomDeviceModal``), else the room sheet.
    static func opening(_ card: RoomCard, controller: RoomController, hasConnection: Bool = false,
                        fans: [String: BathroomFanController] = [:], bedroom: BedroomDevices? = nil) -> RoomCardOpening {
        switch controller.sheet(for: card) {
        case let .mediaRemote(id):
            if let shared = controller.remote(id) { return .remote(shared) }
        case let .device(device):
            if let modal = RoomDeviceModal.resolve(device, hasConnection: hasConnection, fan: { fans[$0] }, bedroom: bedroom) {
                return .device(modal)
            }
        default:
            break
        }
        return .sheet
    }
}

/// Where a room card opens (``RoomPageContent/opening(_:controller:hasConnection:fans:bedroom:)``).
enum RoomCardOpening {
    case remote(MediaRemoteController)
    case device(RoomDeviceModal)
    case sheet
}

/// Wraps a remote controller for `.sheet(item:)`.
@MainActor
struct RemoteSelection: Identifiable {
    var controller: MediaRemoteController
    let id: String

    init(controller: MediaRemoteController) {
        self.controller = controller
        id = controller.config.id
    }
}

// MARK: - Sections

/// One titled section and its cards in the web's section layouts (`RoomGrid`, `DashboardViewPage.tsx:284`).
struct RoomSectionView: View {
    var controller: RoomController
    var section: RoomSection
    var imageServer: HassServer?
    var fans: [String: BathroomFanController] = [:]
    /// The Master Bedroom's beds, so their cards read each side's level and power.
    var bedroom: BedroomDevices?
    var onOpen: (RoomCard) -> Void
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 140
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Whether a lead row's lead card joins the two-column grid instead of spanning the page: a bathroom fan at regular
    /// width (owner, 2026-10-17: a 1,300 pt tile on iPad). On a phone the fan keeps its full-width lead row, which is
    /// what gives its text, two buttons and chevron room.
    static func leadJoinsGrid(_ section: RoomSection, regularWidth: Bool) -> Bool {
        regularWidth && section.cards.first?.control == .bathroomFan
    }

    /// App launchers, and a page's only section, span both section columns (web `ResponsiveSectionItem span`).
    static func isFullWidth(_ section: RoomSection, sectionCount: Int) -> Bool {
        if case .appLaunch = section.layout { return true }
        return sectionCount == 1
    }

    /// Three or more cards after a lead card switch to two filling columns (web `leadRowFollowUpLayout`).
    static func followUpColumns(_ count: Int) -> Int? { count > 2 ? 2 : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            RoomSectionHeader(title: section.title)
            switch section.layout {
            case .grid:
                grid(section.cards)
            case .twoColumnFill:
                grid(section.cards, columns: 2)
            case .leadRow where Self.leadJoinsGrid(section, regularWidth: sizeClass == .regular):
                grid(section.cards, columns: 2, spansPage: false)
            case .leadRow:
                if let lead = section.cards.first {
                    card(lead)
                }
                let rest = Array(section.cards.dropFirst())
                if !rest.isEmpty { grid(rest, columns: Self.followUpColumns(rest.count)) }
            case let .appLaunch(remoteId):
                if let remote = controller.remote(remoteId) {
                    RoomAppLaunchGrid(remote: remote, imageServer: imageServer)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("room.section.\(section.title)")
    }

    /// The default grid (up to 4 columns), or at most `columns` filling the width. Both keep the scaled minimum tile
    /// width, so they reflow to one column at accessibility sizes (a fixed two columns clipped single long words such
    /// as "Humidifier" at AX5 on iPad, HIG: Typography). Tiles in a grid share one height, set by the tallest
    /// (direction G, Controls: Tiles).
    private func grid(_ cards: [RoomCard], columns: Int? = nil, spansPage: Bool = true) -> some View {
        DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: columns ?? 4, equalRowHeights: true) {
            ForEach(cards) { item in
                card(item).gridSpan(spansPage && item.isFullWidth ? 4 : 1)
            }
        }
        .equalHeightTiles()
    }

    private func card(_ card: RoomCard) -> some View {
        RoomCardView(controller: controller, card: card, fan: fans[card.entityId], bedroom: bedroom) { onOpen(card) }
    }
}

// MARK: - Kitchen

/// The Kitchen's Groceries section: the grocery list and Food (web `KitchenGroceriesSection`).
struct KitchenGroceriesSection: View {
    var controller: RoomController
    var navigate: (HomeRoute) -> Void
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 140

    private typealias G = RoomsConfig.Groceries

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            RoomSectionHeader(title: "Groceries")
            // Pages, not devices: dark tiles with no colour family (direction G, Colour families).
            DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 4, equalRowHeights: true) {
                GlassTile(title: G.listTitle, subtitle: G.subtitle(count: controller.displayedState(G.listEntityId)),
                          symbol: SymbolMap.symbol(for: "mdi:clipboard-list"), family: .neutral, isActive: false,
                          kind: .navigate) { navigate(.groceryList) }
                    .accessibilityIdentifier("room.groceries.list")
                GlassTile(title: "Food", subtitle: QuickLinks.allFoodSubtitle { controller.displayedState($0) },
                          symbol: SymbolMap.symbol(for: "mdi:food-fork-drink"), family: .neutral, isActive: false,
                          kind: .navigate) { navigate(.food) }
                    .accessibilityIdentifier("room.groceries.food")
            }
            .equalHeightTiles()
        }
        .accessibilityElement(children: .contain)
    }
}
