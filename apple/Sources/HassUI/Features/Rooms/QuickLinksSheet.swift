import HassCore
import HassDesign
import SwiftUI

// MARK: - Button

/// The toolbar button that opens Quick Links where it is not the trailing circle (``CompactTabLayout``): iPad, the
/// unfolded Duo, and iOS before 26. The web shows a floating action button on every page; iOS puts the same action
/// in the navigation bar (HIG: Toolbars), labeled "Quick Links" for VoiceOver.
struct QuickLinksButton: View {
    /// The Quick Links symbol, shared by this button and the trailing tab.
    static let symbol = "square.grid.2x2"

    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(QuickLinks.title, systemImage: Self.symbol)
        }
        .accessibilityIdentifier("quickLinks.open")
    }
}

extension View {
    /// Adds the Quick Links toolbar button or floating circle and the sheet; a chosen page pushes through
    /// ``HomeRouteDestination`` once the sheet has gone, so the push never races the dismissal.
    /// - Parameters:
    ///   - caller: Service caller for the Security System and room-visit actions.
    ///   - showsButton: Show the toolbar button (false where Quick Links is the trailing tab or the floating circle).
    ///   - showsFloatingButton: Show the floating circle bottom trailing (regular width).
    func quickLinks(caller: (any HassServiceCalling)?, showsButton: Bool = true, showsFloatingButton: Bool = false) -> some View {
        modifier(QuickLinksPresenter(caller: caller, showsButton: showsButton, showsFloatingButton: showsFloatingButton))
    }
}

private struct QuickLinksPresenter: ViewModifier {
    var caller: (any HassServiceCalling)?
    var showsButton: Bool
    var showsFloatingButton: Bool
    @Environment(ShellNavigator.self) private var navigator: ShellNavigator?
    @Environment(\.shellSection) private var section
    @State private var localIsPresented = false
    @State private var pending: HomeRoute?
    @State private var route: HomeRoute?

    /// In the shell, the navigator says which section's root presents the sheet, so the trailing circle, the
    /// flyout row and this button all open it over the selected section, once. Elsewhere it is local.
    private var isPresented: Binding<Bool> {
        guard let navigator, let section else { return $localIsPresented }
        return Binding(
            get: { navigator.quickLinksSection == section },
            set: { if !$0, navigator.quickLinksSection == section { navigator.quickLinksSection = nil } }
        )
    }

    private func open() {
        if let navigator, section != nil { navigator.openQuickLinks() } else { localIsPresented = true }
    }

    func body(content: Content) -> some View {
        content
            .toolbar {
                if showsButton {
                    ToolbarItem(placement: .primaryAction) { QuickLinksButton(action: open) }
                }
            }
            // A bottom inset, not an overlay: scroll content gets room to scroll clear of the circle, which sits
            // above the home indicator and inside the side safe areas (the unfolded Duo's trailing bar).
            .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
                if showsFloatingButton {
                    FloatingQuickLinksButton(action: open)
                        .padding(.trailing, HassTokens.Spacing.l)
                        .padding(.bottom, HassTokens.Spacing.s)
                }
            }
            .sheet(isPresented: isPresented, onDismiss: {
                route = pending
                pending = nil
            }) {
                QuickLinksSheet(caller: caller) { pending = $0 }
            }
            .homeRouteDestination($route)
    }
}

// MARK: - Sheet

/// Quick Links (web `GlobalQuickLinksAction`): Rooms and Security System open inside the sheet with Back; the other
/// tiles close it and open their page.
struct QuickLinksSheet: View {
    var caller: (any HassServiceCalling)?
    var onNavigate: (HomeRoute) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var path: [QuickLink.Detail] = []

    var body: some View {
        NavigationStack(path: $path) {
            QuickLinksRoot(onNavigate: open)
                .modalChrome()
                .inlineNavigationTitle()
                .navigationDestination(for: QuickLink.Detail.self) { detail in
                    QuickLinksDetailView(detail: detail, caller: caller) { go(.room($0)) }
                        .modalChrome()
                }
                .toolbar { SheetCloseItem(identifier: "quickLinks.close") { dismiss() } }
        }
        .hassSheet(.page, height: .full) // Navigates to rooms and detail pages
        .accessibilityIdentifier("quickLinks.sheet")
    }

    /// Rooms and Security System push inside the sheet; page links close it and open their page.
    func open(_ link: QuickLink) {
        switch link.action {
        case let .detail(detail): path.append(detail)
        case let .navigate(path): if let route = HomeRoute(path: path) { go(route) }
        }
    }

    func go(_ route: HomeRoute) {
        onNavigate(route)
        dismiss()
    }
}

// MARK: - Tab

/// Quick Links as the tab bar's trailing tab (iOS 26 and later in compact width; ``CompactTabLayout``). Like a
/// Search tab, it is its own page: Rooms and Security System open inside it, and the pages it links push on its
/// own stack, so leaving the tab returns to the section underneath unchanged.
struct QuickLinksTab: View {
    var caller: (any HassServiceCalling)?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            QuickLinksRoot { link in
                switch link.action {
                case let .detail(detail): path.append(detail)
                case let .navigate(route): if let route = HomeRoute(path: route) { path.append(route) }
                }
            }
            .navigationDestination(for: QuickLink.Detail.self) { detail in
                QuickLinksDetailView(detail: detail, caller: caller) { path.append(HomeRoute.room($0)) }
                    .pageChrome()
            }
            .navigationDestination(for: HomeRoute.self) { HomeRouteDestination(route: $0).pageChrome() }
            .sectionRootChrome()
            .pageChrome()
        }
        .accessibilityIdentifier("quickLinks.tab")
    }
}

// MARK: - Shared content

/// The Quick Links page body: its tiles, titled for the stack it sits in.
struct QuickLinksRoot: View {
    var onNavigate: (QuickLink) -> Void

    var body: some View {
        ScrollView {
            QuickLinksGrid(onNavigate: onNavigate)
                .padding(HassTokens.Spacing.l)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
        }
        .navigationTitle(QuickLinks.title)
    }
}

/// Rooms or Security System, opened from a Quick Links tile.
struct QuickLinksDetailView: View {
    var detail: QuickLink.Detail
    var caller: (any HassServiceCalling)?
    /// Opens a room page by web path.
    var onRoom: (String) -> Void

    var body: some View {
        switch detail {
        case .rooms:
            ScrollView {
                RoomNavigationGrid(caller: caller, onOpen: onRoom)
                    .padding(HassTokens.Spacing.l)
            }
            .navigationTitle("Rooms")
            .inlineNavigationTitle()
        case .securitySystem:
            QuickLinksSecurityDetail(caller: caller)
        }
    }
}

/// The Quick Links tiles in two columns (web `DynamicGrid columns={2}`).
struct QuickLinksGrid: View {
    var onNavigate: (QuickLink) -> Void
    @Environment(EntityStore.self) private var store
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 140

    var body: some View {
        DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 2) {
            ForEach(QuickLinks.visible { store.entity($0).state?.state }) { link in
                tile(link)
            }
        }
    }

    private func tile(_ link: QuickLink) -> some View {
        // The tile is the control. (A Button or NavigationLink around a tile drawn with hit testing off never
        // received taps: a label that is not hit-testable leaves the outer control nothing to tap.)
        QuickLinkTile(link: link) { onNavigate(link) }
            .accessibilityHint(link.action.isDetail ? "Opens \(link.title) in Quick Links" : "Opens the \(link.title) page")
            .accessibilityIdentifier("quickLinks.\(link.id)")
    }
}

private extension QuickLink.Action {
    var isDetail: Bool {
        if case .detail = self { return true }
        return false
    }
}

/// One Quick Links tile (web `QuickLinkTile`): a dark disclosure tile with its glyph in the page's colour family
/// (direction G mockup n1 quick links); Security System's glyph follows the alarm mode.
struct QuickLinkTile: View {
    var link: QuickLink
    var action: () -> Void = {}
    @Environment(EntityStore.self) private var store

    /// The tile's state line, which the parent control also reads to VoiceOver.
    static func subtitle(_ link: QuickLink, store: EntityStore) -> String? {
        switch link.status {
        case .entityState: ScreenshotPrivacy.isRedacting ? "Hidden" : RoomFormat.compact(link.entityId.flatMap { store.entity($0).state })
        case .allFood: QuickLinks.allFoodSubtitle { store.entity($0).state?.state }
        case nil: nil
        }
    }

    /// The colour family a link's glyph takes (`.agents/design/direction-g.md`, Colour families). Rooms and Food have
    /// none; Security System follows the alarm mode, and is neutral while redacted so screenshots don't show it.
    static func family(_ link: QuickLink, alarmState: String?) -> ColorFamily {
        switch link.id {
        case "security-system": ScreenshotPrivacy.isRedacting ? ColorFamily.neutral : ColorFamily.security(alarmState: alarmState) ?? .neutral
        case "vacuums": .cleaning
        case "media": .media
        case "custom-lights": .lights
        case "sprinklers": .water
        default: .neutral
        }
    }

    var body: some View {
        let state = link.entityId.flatMap { store.entity($0).state }
        let security = link.id == "security-system" ? QuickLinks.securityAppearance(state?.state) : nil
        // A navigation tile is never "on": the off face keeps the tile dark with its glyph in the family colour.
        GlassTile(title: link.title, subtitle: Self.subtitle(link, store: store),
                  // Redacted screenshots keep the plain shield, so the glyph can't give the alarm mode away.
                  symbol: SymbolMap.symbol(for: ScreenshotPrivacy.isRedacting ? link.icon : security?.icon ?? link.icon),
                  family: Self.family(link, alarmState: state?.state), isActive: false, kind: .navigate, action: action)
    }
}

/// Security System inside Quick Links: the Security page's alarm modes (web `SecurityControls`). Without a caller
/// (no connection yet) it shows the state only.
struct QuickLinksSecurityDetail: View {
    var caller: (any HassServiceCalling)?
    @Environment(EntityStore.self) private var store

    var body: some View {
        if let caller {
            SecurityControls(caller: caller)
        } else {
            stateOnly
        }
    }

    private var stateOnly: some View {
        let state = store.entity(QuickLinks.securityEntityId).state
        return ContentUnavailableView {
            Label("Security System", systemImage: SymbolMap.symbol(for: QuickLinks.securityAppearance(state?.state).icon))
        } description: {
            Text(ScreenshotPrivacy.isRedacting ? "Hidden" : RoomFormat.compact(state))
        }
        .navigationTitle("Security System")
        .inlineNavigationTitle()
    }
}

// MARK: - Rooms grid

/// Every room, most-visited first (web `RoomNavigationGrid`). Opening a room counts the visit.
struct RoomNavigationGrid: View {
    var caller: (any HassServiceCalling)?
    var onOpen: (String) -> Void
    @Environment(EntityStore.self) private var store
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 140

    var body: some View {
        DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 4) {
            ForEach(RoomNavigation.ranked { store.entity($0).state?.state }) { item in
                // Rooms have no colour of their own (direction G, Colour families).
                GlassTile(title: item.title, symbol: SymbolMap.symbol(for: item.icon), family: .neutral,
                          isActive: false, kind: .navigate) { open(item) }
                    .accessibilityHint("Opens the \(item.title) page")
                    .accessibilityIdentifier("rooms.\(item.path)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rooms")
    }

    /// Counts the visit, then opens the room.
    func open(_ item: RoomNavigationItem) {
        if let caller { RoomController.recordVisit(item, caller: caller) }
        onOpen(item.path)
    }
}
