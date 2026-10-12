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

    var body: some View {
        if let caller = callerOverride ?? connection {
            RoomPageContent(page: page, store: store, caller: caller, imageServer: connection?.server)
                .environment(\.householdViewer, injectedViewer ?? viewer)
                .task {
                    // Personalized titles ("Your Side") need the signed-in user; the page shows plain titles until then.
                    guard injectedViewer == nil, let connection, let user = try? await connection.currentUser() else { return }
                    viewer = HouseholdResident.forUser(id: user.id)
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
    @State private var pendingRoute: HomeRoute?
    @State private var route: HomeRoute?
    private let imageServer: HassServer?

    init(page: RoomPage, store: EntityStore, caller: any HassServiceCalling, imageServer: HassServer?) {
        _controller = State(initialValue: RoomController(page: page, store: store, caller: caller))
        self.imageServer = imageServer
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
        .accessibilityIdentifier("room.scroll.\(page.id)")
        .navigationTitle(page.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                QuickLinksButton { showsQuickLinks = true }
            }
        }
        .sheet(item: $sheetCard, content: cardSheet)
        .sheet(item: Binding(get: { remote.map { RemoteSelection(controller: $0) } }, set: { remote = $0?.controller }),
               content: remoteSheet)
        .sheet(isPresented: $showsQuickLinks, onDismiss: quickLinksDismissed, content: quickLinksSheet)
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
                    RoomSectionView(controller: controller, section: section, imageServer: imageServer, onOpen: open)
                        .gridSpan(RoomSectionView.isFullWidth(section, sectionCount: count) ? 2 : 1)
                }
            }
        }
    }

    // MARK: Sheets

    func cardSheet(_ card: RoomCard) -> some View {
        RoomCardSheet(controller: controller, card: card)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
    }

    func remoteSheet(_ selection: RemoteSelection) -> some View {
        MediaRemoteSheet(controller: selection.controller, imageServer: imageServer, initialTab: .controls)
            .mediaRemotePresentation()
    }

    func quickLinksSheet() -> some View {
        QuickLinksSheet(caller: controller.caller) { pendingRoute = $0 }
    }

    /// Pushes the page Quick Links chose once the sheet has gone, so the push never races the dismissal.
    func quickLinksDismissed() {
        route = pendingRoute
        pendingRoute = nil
    }

    /// Opens a card: its remote sheet when it has one, else its room sheet.
    func open(_ card: RoomCard) {
        switch Self.opening(card, controller: controller) {
        case let .remote(shared): remote = shared
        case .sheet: sheetCard = card
        }
    }

    /// Where opening a card goes: the shared remote sheet for remote cards, else the room sheet.
    static func opening(_ card: RoomCard, controller: RoomController) -> RoomCardOpening {
        if case let .mediaRemote(id) = controller.sheet(for: card), let shared = controller.remote(id) { return .remote(shared) }
        return .sheet
    }
}

/// Where a room card opens (``RoomPageContent/opening(_:controller:)``).
enum RoomCardOpening {
    case remote(MediaRemoteController)
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
    var onOpen: (RoomCard) -> Void
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 140

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
    /// as "Humidifier" at AX5 on iPad, HIG: Typography).
    private func grid(_ cards: [RoomCard], columns: Int? = nil) -> some View {
        DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: columns ?? 4) {
            ForEach(cards) { item in
                card(item).gridSpan(item.isFullWidth ? 4 : 1)
            }
        }
    }

    private func card(_ card: RoomCard) -> some View {
        RoomCardView(controller: controller, card: card) { onOpen(card) }
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
            DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 4) {
                GlassTile(title: G.listTitle, subtitle: G.subtitle(count: controller.displayedState(G.listEntityId)),
                          symbol: SymbolMap.symbol(for: "mdi:clipboard-list"), tint: G.listBackground.color, isActive: true,
                          kind: .navigate, wash: G.listBackground.color) { navigate(.groceryList) }
                    .accessibilityIdentifier("room.groceries.list")
                GlassTile(title: "Food", subtitle: QuickLinks.allFoodSubtitle { controller.displayedState($0) },
                          symbol: SymbolMap.symbol(for: "mdi:food-fork-drink"), tint: QuickLinks.foodBackground.color, isActive: true,
                          kind: .navigate, wash: QuickLinks.foodBackground.color) { navigate(.food) }
                    .accessibilityIdentifier("room.groceries.food")
            }
        }
        .accessibilityElement(children: .contain)
    }
}
