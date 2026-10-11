import HassCore
import HassDesign
import SwiftUI

/// Primary navigation, matching the web's `PRIMARY_NAV_ROUTES` (`routes.ts`).
///
/// iPad will move to the overlay flyout (`.agents/design/apple/ipados.md`); until then both use tabs.
struct MainTabView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case home, security, climate, chores, settings
        var id: String { rawValue }

        var title: String {
            switch self {
            case .home: "Home"
            case .security: "Security"
            case .climate: "Climate"
            case .chores: "Chores"
            case .settings: "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .home: SymbolMap.symbol(for: "mdi:home")
            case .security: SymbolMap.symbol(for: "mdi:shield")
            case .climate: SymbolMap.symbol(for: "mdi:thermostat")
            case .chores: SymbolMap.symbol(for: "mdi:clipboard-list")
            case .settings: SymbolMap.symbol(for: "mdi:cog")
            }
        }
    }

    @SceneStorage("selectedTab") private var selection: Tab = .home

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Tab.allCases) { tab in
                NavigationStack {
                    screen(for: tab)
                }
                .tabItem { Label(tab.title, systemImage: tab.symbol) }
                .accessibilityIdentifier("tab.\(tab.rawValue)")
                .tag(tab)
            }
        }
    }

    @ViewBuilder
    private func screen(for tab: Tab) -> some View {
        switch tab {
        // Inventory pages until the Food & Recipes hub links them (FENTON_OPEN_INVENTORY in debug).
        case .home: HomeScreen().inventoryDestinations()
        case .settings: SettingsScreen()
        default: PlaceholderScreen(title: tab.title, symbol: tab.symbol)
        }
    }
}
