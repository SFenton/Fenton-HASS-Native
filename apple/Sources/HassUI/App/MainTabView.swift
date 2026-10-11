import HassCore
import HassDesign
import SwiftUI

/// Primary navigation, matching the web's `PRIMARY_NAV_ROUTES` (`routes.ts`).
///
/// One root `TabView` in every window so each section keeps its stack and scroll position. Compact width
/// shows the tab bar (web `bottom` layout). Regular width (iPad, unfolded iPhone Duo) hides it and
/// navigates through ``NavigationFlyout`` instead (web `drawer-only`; FestivalNativeApps keeps the
/// `TabView` under its flyout because a plain view switch lost the first responder on each change).
struct MainTabView: View {
    @SceneStorage("selectedTab") private var storedSelection: AppSection = .home
    @State private var navigator = ShellNavigator()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var style: ShellNavigationStyle {
        ShellNavigationStyle.resolve(isRegularWidth: horizontalSizeClass == .regular)
    }

    var body: some View {
        @Bindable var navigator = navigator
        ZStack(alignment: .leading) {
            TabView(selection: $navigator.selection) {
                ForEach(AppSection.allCases) { section in
                    sectionStack(for: section)
                        .tabItem { Label(section.title, systemImage: section.symbol) }
                        .badge(NavigationMenu.badge(for: section, overdue: navigator.overdueChores) ?? 0)
                        .tag(section)
                }
            }
            // While the flyout is open its scrim covers the content; hide the content from VoiceOver too.
            .accessibilityHidden(while: navigator.isFlyoutOpen)
            .flyoutEdgeSwipe(navigator, isEnabled: style == .flyout)
            if style == .flyout {
                NavigationFlyout()
            }
        }
        .environment(navigator)
        .environment(\.shellNavigationStyle, style)
        .onAppear { navigator.selection = storedSelection }
        .onChange(of: navigator.selection) { _, section in storedSelection = section }
        .onChange(of: style) { _, newStyle in
            if newStyle == .tabBar { navigator.dismissFlyout() }
        }
    }

    /// A section's stack. Sections with list/detail pages use ``OnDemandSplitStack``; the rest push full width.
    @ViewBuilder
    private func sectionStack(for section: AppSection) -> some View {
        switch section {
        case .settings:
            SettingsStack(path: navigator.path(for: section))
        default:
            NavigationStack(path: navigator.path(for: section)) {
                Group {
                    if section == .home {
                        HomeScreen()
                    } else {
                        PlaceholderScreen(title: section.title, symbol: section.symbol)
                    }
                }
                .sectionRootChrome()
                .pageChrome()
            }
        }
    }
}

extension View {
    /// Shell chrome every page in a section stack applies, pushed pages included: hides the root tab bar
    /// in flyout style (on iPadOS 18+ the floating top tab bar too). A pushed page without it brings the
    /// tab bar back.
    func pageChrome() -> some View { modifier(PageChrome()) }
}

/// Implementation of ``SwiftUI/View/pageChrome()``.
private struct PageChrome: ViewModifier {
    @Environment(\.shellNavigationStyle) private var style

    func body(content: Content) -> some View {
        #if os(iOS)
        content.toolbar(style == .flyout ? .hidden : .automatic, for: .tabBar)
        #else
        content
        #endif
    }
}
