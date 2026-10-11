import HassCore
import HassDesign
import SwiftUI

// MARK: - Button

/// The toolbar button that opens Quick Links. The web shows a floating action button on every page; iOS puts the
/// same action in the navigation bar (HIG: Toolbars), labeled "Quick Links" for VoiceOver.
struct QuickLinksButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(QuickLinks.title, systemImage: "square.grid.2x2")
        }
        .accessibilityIdentifier("quickLinks.open")
    }
}

extension View {
    /// Adds the Quick Links toolbar button and sheet; a chosen page pushes through ``HomeRouteDestination`` once the
    /// sheet has gone, so the push never races the dismissal.
    func quickLinks(caller: (any HassServiceCalling)?) -> some View {
        modifier(QuickLinksPresenter(caller: caller))
    }
}

private struct QuickLinksPresenter: ViewModifier {
    var caller: (any HassServiceCalling)?
    @State private var isPresented = false
    @State private var pending: HomeRoute?
    @State private var route: HomeRoute?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) { QuickLinksButton { isPresented = true } }
            }
            .sheet(isPresented: $isPresented, onDismiss: {
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

    var body: some View {
        NavigationStack {
            ScrollView {
                QuickLinksGrid { link in
                    if case let .navigate(path) = link.action, let route = HomeRoute(path: path) { go(route) }
                }
                .padding(HassTokens.Spacing.l)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(QuickLinks.title)
            .inlineNavigationTitle()
            .navigationDestination(for: QuickLink.Detail.self) { detail in
                switch detail {
                case .rooms:
                    ScrollView {
                        RoomNavigationGrid(caller: caller) { go(.room($0)) }
                            .padding(HassTokens.Spacing.l)
                    }
                    .navigationTitle("Rooms")
                    .inlineNavigationTitle()
                case .securitySystem:
                    QuickLinksSecurityDetail()
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("quickLinks.sheet")
    }

    private func go(_ route: HomeRoute) {
        onNavigate(route)
        dismiss()
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

    @ViewBuilder
    private func tile(_ link: QuickLink) -> some View {
        let face = QuickLinkTile(link: link)
        let subtitle = QuickLinkTile.subtitle(link, store: store)
        switch link.action {
        case let .detail(detail):
            NavigationLink(value: detail) { face }
                .buttonStyle(.plain)
                .quickLinkAccessibility(link, subtitle: subtitle)
        case .navigate:
            Button { onNavigate(link) } label: { face }
                .buttonStyle(.plain)
                .quickLinkAccessibility(link, subtitle: subtitle)
        }
    }
}

private extension View {
    /// One element per tile: the face is drawing only, so VoiceOver activates the parent link or button.
    func quickLinkAccessibility(_ link: QuickLink, subtitle: String?) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(link.title)
            .accessibilityValue(subtitle ?? "")
            .accessibilityIdentifier("quickLinks.\(link.id)")
    }
}

/// One Quick Links tile (web `QuickLinkTile`): a disclosure tile, tinted by the alarm state for Security System.
struct QuickLinkTile: View {
    var link: QuickLink
    @Environment(EntityStore.self) private var store

    /// The tile's state line, which the parent control also reads to VoiceOver.
    static func subtitle(_ link: QuickLink, store: EntityStore) -> String? {
        switch link.status {
        case .entityState: ScreenshotPrivacy.isRedacting ? "Hidden" : RoomFormat.compact(link.entityId.flatMap { store.entity($0).state })
        case .allFood: QuickLinks.allFoodSubtitle { store.entity($0).state?.state }
        case nil: nil
        }
    }

    var body: some View {
        let state = link.entityId.flatMap { store.entity($0).state }
        let security = link.id == "security-system" ? QuickLinks.securityAppearance(state?.state) : nil
        let subtitle = Self.subtitle(link, store: store)
        let wash: Color? = security.map { $0.color.color.opacity(0.5) } ?? link.backgroundColor?.color
        GlassTile(title: link.title, subtitle: subtitle, symbol: SymbolMap.symbol(for: security?.icon ?? link.icon),
                  tint: link.tone.color, isActive: true, kind: .navigate,
                  wash: ScreenshotPrivacy.isRedacting && security != nil ? nil : wash)
            // The parent link or button is the control; this face only draws.
            .allowsHitTesting(false)
    }
}

/// Security System inside Quick Links. Hook point: the Security lane replaces this with its alarm controls
/// (web `SecurityControls`).
struct QuickLinksSecurityDetail: View {
    @Environment(EntityStore.self) private var store

    var body: some View {
        let state = store.entity(QuickLinks.securityEntityId).state
        ContentUnavailableView {
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
                Button {
                    if let caller { RoomController.recordVisit(item, caller: caller) }
                    onOpen(item.path)
                } label: {
                    GlassTile(title: item.title, symbol: SymbolMap.symbol(for: item.icon), tint: item.color.color,
                              isActive: true, kind: .navigate, wash: item.color.color.opacity(0.45))
                        .allowsHitTesting(false)
                }
                .buttonStyle(.plain)
                // One element: the tile face is drawing only, so VoiceOver activates this button.
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(item.title)
                .accessibilityHint("Opens the \(item.title) page")
                .accessibilityIdentifier("rooms.\(item.path)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rooms")
    }
}
