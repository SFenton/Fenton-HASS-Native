import HassCore
import HassDesign
import SwiftUI

/// Pages pushed from Home (web Home sub-routes, `routes.ts` `HOME_SUB_ROUTE_PATHS`), reached from the Quick
/// Links grid (web `QUICK_ACCESS_ITEMS`, `atAGlance.ts:233-276`).
///
/// Each page thread adds its case, its ``QuickLink`` and its destination here.
enum HomeRoute: String, Hashable, Identifiable, CaseIterable {
    case media
    case customLights = "custom-lights"
    case sprinklers

    var id: String { rawValue }

    /// The Quick Links tile that opens this page.
    var link: QuickLink {
        switch self {
        case .media: QuickLink(title: "Media", icon: "mdi:remote")
        case .customLights: QuickLink(title: "Custom Lights", icon: "mdi:lightbulb-group")
        case .sprinklers: QuickLink(title: "Sprinklers", icon: "mdi:sprinkler-variant",
                                    visibilityEntityId: SprinklersConfig.visibilityEntityId)
        }
    }

    /// The page, on the app's connection.
    @MainActor @ViewBuilder
    func destination(connection: HassConnection) -> some View {
        switch self {
        case .media: MediaScreen(store: connection.store, caller: connection, imageServer: connection.server)
        case .customLights: CustomLightsScreen(store: connection.store, caller: connection)
        case .sprinklers: SprinklersScreen(store: connection.store, caller: connection)
        }
    }

    /// One Quick Links tile.
    struct QuickLink: Hashable {
        var title: String
        var icon: String
        /// Shown only while this entity is `on` (web `visibilityEntityId`).
        var visibilityEntityId: String?

        func isVisible(_ store: EntityStore) -> Bool {
            visibilityEntityId.map { store.entity($0).state?.state == "on" } ?? true
        }
    }
}

/// Home's Quick Links grid: one navigation tile per Home page.
struct HomeQuickLinks: View {
    @Environment(EntityStore.self) private var store
    var open: (HomeRoute) -> Void
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 140

    var body: some View {
        let routes = HomeRoute.allCases.filter { $0.link.isVisible(store) }
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            Text("Quick Links")
                .font(.title3.weight(.semibold))
                .foregroundStyle(HassTokens.Ink.primary)
                .accessibilityAddTraits(.isHeader)
            DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 4) {
                ForEach(routes) { route in
                    GlassTile(title: route.link.title, symbol: SymbolMap.symbol(for: route.link.icon),
                              tint: .accentColor, isActive: false, kind: .navigate) { open(route) }
                        .accessibilityIdentifier("home.link.\(route.rawValue)")
                }
            }
        }
    }
}
