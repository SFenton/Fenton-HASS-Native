import HassCore
import HassDesign
import SwiftUI

// MARK: - Button

/// The header button that opens Quick Links, beside Profile on every page (owner, 2026-10-16). The web shows a floating
/// action button on every page; iOS puts the same action in the navigation bar (HIG Toolbars: "Trailing: important
/// always-available items"), a glass circle labeled "Quick Links" for VoiceOver.
struct QuickLinksButton: View {
    /// The Quick Links symbol, shared by this button.
    static let symbol = "square.grid.2x2"

    var action: () -> Void

    var body: some View {
        // A custom image on its own glass circle, like Profile beside it (``SwiftUI/View/headerCircle()``): the system sizes
        // a bar item built from a `Label` itself and ignores a frame (it measured 39 x 36).
        Button(action: action) {
            Image(systemName: Self.symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .headerCircle()
        }
        .accessibilityLabel(QuickLinks.title)
        .accessibilityShowsLargeContentViewer {
            Label(QuickLinks.title, systemImage: Self.symbol)
        }
        .accessibilityIdentifier("quickLinks.open")
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

/// The Quick Links tiles in two columns (web `DynamicGrid columns={2}`), all one size: the tallest tile (a two-line title
/// over a two-line state) sets the height of every row (owner, 2026-10-16: "Quick Links now have different tile sizes
/// (prefer consistency of what we had before)"). The arrangement is the Rooms grid's, glyph top-leading and text on the
/// bottom, because a row has no width for "12 Items • 2 Expiring Soon" beside a glyph and a chevron.
struct QuickLinksGrid: View {
    var onNavigate: (QuickLink) -> Void
    @Environment(EntityStore.self) private var store
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 140

    var body: some View {
        DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 2, equalRowHeights: true) {
            ForEach(QuickLinks.visible { store.entity($0).state?.state }) { link in
                tile(link)
            }
        }
        .equalHeightTiles()
        .tileLayout(.anchoredBottom)
        .tileTitleLines(2)
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

/// One Quick Links tile (web `QuickLinkTile`): a solid colour per link with a filled white glyph and white text
/// (``QuickLinkPalette``); Security System's colour and glyph follow the alarm mode.
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

    /// The fill a link takes (`.agents/design/direction-g.md`, Colour: Quick Links tiles). Security System follows the alarm
    /// mode, and is a neutral slate while redacted so screenshots don't show it.
    static func fill(_ link: QuickLink, alarmState: String?) -> UInt32? {
        QuickLinkPalette.fill(forLink: link.id, alarmState: alarmState, isRedacted: ScreenshotPrivacy.isRedacting)
    }

    var body: some View {
        let state = link.entityId.flatMap { store.entity($0).state }
        let security = link.id == "security-system" ? QuickLinks.securityAppearance(state?.state) : nil
        // A navigation tile is never "on": a solid fill with a filled white glyph, like a room (owner, 2026-10-16).
        GlassTile(title: link.title, subtitle: Self.subtitle(link, store: store),
                  // Redacted screenshots keep the plain shield, so the glyph can't give the alarm mode away.
                  symbol: SymbolMap.symbol(for: ScreenshotPrivacy.isRedacting ? link.icon : security?.icon ?? link.icon),
                  family: .neutral, fillRGB: Self.fill(link, alarmState: state?.state), isActive: false, kind: .navigate,
                  action: action)
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

/// Every room as a coloured tile (``RoomPalette``), most-visited first (web `RoomNavigationGrid`). Opening a room counts
/// the visit.
struct RoomNavigationGrid: View {
    var caller: (any HassServiceCalling)?
    var onOpen: (String) -> Void
    @Environment(EntityStore.self) private var store
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 140

    var body: some View {
        DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 4, equalRowHeights: true) {
            ForEach(RoomNavigation.ranked { store.entity($0).state?.state }) { item in
                // A solid fill per room with a filled white glyph (direction G, Colour: Room tiles; owner, 2026-10-16).
                GlassTile(title: item.title, symbol: SymbolMap.symbol(for: item.icon), family: .neutral,
                          fillRGB: RoomPalette.fill(forRoom: item.path), isActive: false, kind: .navigate) { open(item) }
                    .accessibilityHint("Opens the \(item.title) page")
                    .accessibilityIdentifier("rooms.\(item.path)")
            }
        }
        // Glyph top-leading, the name on the bottom line, room for two lines at this text size and one height for every
        // tile (owner, 2026-10-16: "Rooms should have taller tiles with room for two lines of text").
        .equalHeightTiles()
        .tileLayout(.anchoredBottom)
        .tileTitleLines(2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rooms")
    }

    /// Counts the visit, then opens the room.
    func open(_ item: RoomNavigationItem) {
        if let caller { RoomController.recordVisit(item, caller: caller) }
        onOpen(item.path)
    }
}
