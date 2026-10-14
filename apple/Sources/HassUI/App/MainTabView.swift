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
    @State private var canvas: CGSize = .zero
    @State private var windowTop: CGFloat = 0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(HassConnection.self) private var connection: HassConnection?
    @Environment(PushCoordinator.self) private var push: PushCoordinator?

    private var style: ShellNavigationStyle {
        ShellNavigationStyle.resolve(isRegularWidth: horizontalSizeClass == .regular)
    }

    private var layout: CompactTabLayout {
        if #available(iOS 26.0, macOS 26.0, *) { return .resolve(supportsTrailingTab: true) }
        return .resolve(supportsTrailingTab: false)
    }

    private var chrome: ShellChrome { .resolve(style: style, layout: layout) }

    /// Sections shown as tabs: all of them under the flyout (the bar is hidden), else the compact layout's.
    private var tabSections: [AppSection] {
        style == .flyout ? AppSection.allCases : layout.visibleSections
    }

    private var settingsIsTab: Bool { tabSections.contains(.settings) }

    var body: some View {
        ZStack(alignment: .leading) {
            tabs
                // While the flyout is open its scrim covers the content; hide the content from VoiceOver too.
                .accessibilityHidden(while: navigator.isFlyoutOpen)
                .flyoutEdgeSwipe(navigator, isEnabled: chrome.showsMenuButton)
            if chrome.showsMenuButton {
                NavigationFlyout()
            }
        }
        // Also behind the root, where no page draws: under the tab bar and the home indicator.
        .background { HouseBackdrop() }
        // The window's full size, which the page backdrop photo fills on every page (``HouseBackdrop``).
        .background {
            Color.clear
                .ignoresSafeArea()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { canvas = $0 }
        }
        // The status bar's height, for where the inline navigation bar ends (``headerEdgeCap``).
        .background {
            Color.clear.onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top.rounded() } action: { windowTop = $0 }
        }
        .environment(navigator)
        .environment(\.shellNavigationStyle, style)
        .environment(\.shellChrome, chrome)
        .environment(\.backdropCanvas, canvas)
        .environment(\.headerEdgeCap, headerEdgeCap)
        // Direction G: pages sit on the dimmed house photo, so the signed-in app is always dark, sheets included
        // in v1 (`.agents/design/direction-g.md`, Layers; plan decision 3).
        .preferredColorScheme(.dark)
        .onAppear {
            navigator.settingsIsTab = settingsIsTab
            navigator.selection = storedSelection
            if !settingsIsTab { navigator.settingsLeftTabBar() }
        }
        .onChange(of: settingsIsTab) { _, isTab in
            navigator.settingsIsTab = isTab
            if !isTab { navigator.settingsLeftTabBar() }
        }
        .onChange(of: navigator.selection) { _, section in storedSelection = section }
        // A notification's page: also on appear, for a tap that launched the app.
        .onChange(of: push?.pendingRequest, initial: true) { _, request in
            guard let request else { return }
            navigator.open(request.destination)
            push?.didOpen(request)
        }
        .onChange(of: style) { _, newStyle in
            if newStyle == .tabBar, !chrome.showsMenuButton { navigator.dismissFlyout() }
            if newStyle == .flyout { navigator.closeQuickLinks() }
        }
        // Again once connected: a lookup before the socket is up fails, and the cached name stays meanwhile.
        .task(id: isConnected) { await loadProfileName() }
    }

    /// The root tab view: iOS 26 and later use the `Tab` API with the trailing Quick Links tab in compact width.
    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            let navigator = navigator, settingsIsTab = settingsIsTab
            // A selection the bar does not show (Settings while the window turns compact) reads as Home until
            // ``ShellNavigator/settingsLeftTabBar()`` moves it, so the tab view never selects a missing tab.
            let selection = Binding<RootTab>(
                get: { navigator.rootTab == .section(.settings) && !settingsIsTab ? .section(.home) : navigator.rootTab },
                set: { navigator.rootTab = $0 }
            )
            TabView(selection: selection) {
                ForEach(tabSections) { section in
                    Tab(section.title, systemImage: section.symbol, value: RootTab.section(section)) {
                        sectionStack(for: section)
                    }
                    .badge(NavigationMenu.badge(for: section, overdue: navigator.overdueChores) ?? 0)
                }
                // The trailing tab. The system draws it inside the bar here (FestivalNativeApps' Search tab, whose
                // page is `.searchable`, is drawn apart). Under the flyout the bar is hidden and nothing selects it
                // (``ShellNavigator/closeQuickLinks()``).
                Tab(QuickLinks.title, systemImage: QuickLinksButton.symbol, value: RootTab.quickLinks, role: .search) {
                    QuickLinksTab(caller: connection)
                }
            }
        } else {
            @Bindable var navigator = navigator
            TabView(selection: $navigator.selection) {
                ForEach(AppSection.allCases) { section in
                    sectionStack(for: section)
                        .tabItem { Label(section.title, systemImage: section.symbol) }
                        .badge(NavigationMenu.badge(for: section, overdue: navigator.overdueChores) ?? 0)
                        .tag(section)
                }
            }
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
                    switch section {
                    // Inventory pages until the Food & Recipes hub links them (FENTON_OPEN_INVENTORY in debug).
                    case .home: HomeScreen().inventoryDestinations()
                    case .security: SecurityScreen()
                    case .climate: ClimateScreen()
                    case .chores: ChoresScreen()
                    default: PlaceholderScreen(title: section.title, symbol: section.symbol)
                    }
                }
                .sectionRootChrome()
                .pageChrome()
                .navigationDestination(for: ShellRoute.self) { _ in SettingsPage() }
                // Pages a notification opens (``ShellNavigator/open(_:)``), as Quick Links pushes them.
                .navigationDestination(for: HomeRoute.self) { HomeRouteDestination(route: $0).pageChrome() }
            }
        }
    }

    /// Where the inline navigation bar ends: the status bar plus a compact bar
    /// (`UINavigationBar.sizeThatFits`), so the header fade never hides a page's expanded large title.
    private var headerEdgeCap: CGFloat? {
        #if os(iOS)
        guard windowTop > 0 else { return nil }
        return windowTop + Self.barHeight
        #else
        return nil
        #endif
    }

    #if os(iOS)
    /// A compact navigation bar's height on this device.
    private static let barHeight: CGFloat = UINavigationBar().sizeThatFits(CGSize(width: 1000, height: 1000)).height
    #endif

    private var isConnected: Bool {
        if case .connected = connection?.status { return true }
        return false
    }

    /// Reads the signed-in user for the profile button (the cached name shows until it arrives) and for push
    /// registration, which is per Home Assistant user.
    private func loadProfileName() async {
        guard let connection, let user = try? await connection.currentUser() else { return }
        if navigator.profileName != user.name { navigator.profileName = user.name }
        await push?.didConnect(userID: user.id)
    }
}

extension View {
    /// Shell chrome every page in a section stack applies, pushed pages included: the header fade (no
    /// translucent band behind the navigation bar; ``HeaderEdgeFade``), the blurred house backdrop
    /// (``HouseBackdrop``), and the root tab bar hidden in flyout style (on iPadOS 18+ the floating top tab bar
    /// too). A pushed page without it brings the tab bar back and draws no backdrop.
    func pageChrome() -> some View { modifier(PageChrome()) }
}

/// Implementation of ``SwiftUI/View/pageChrome()``.
private struct PageChrome: ViewModifier {
    @Environment(\.shellNavigationStyle) private var style
    @Environment(ShellNavigator.self) private var navigator: ShellNavigator?

    func body(content: Content) -> some View {
        let isFlyoutOpen = navigator?.isFlyoutOpen ?? false
        #if os(iOS)
        // Both layers: SwiftUI vends a page's own elements past UIKit, and the UIKit navigation bar is
        // out of SwiftUI's reach.
        content
            .headerEdgeFade()
            .scrollContentBackground(.hidden)
            .pageBackdrop()
            .accessibilityHidden(while: isFlyoutOpen)
            .toolbar(style == .flyout ? .hidden : .automatic, for: .tabBar)
            .background(TabControllerAccessibilityHider(hidden: isFlyoutOpen))
        #else
        content
            .headerEdgeFade()
            .scrollContentBackground(.hidden)
            .pageBackdrop()
            .accessibilityHidden(while: isFlyoutOpen)
        #endif
    }
}

extension View {
    /// Draws ``HouseBackdrop`` behind this page: as the navigation container's background on iOS 18 and later
    /// (it fills the page, under the bars, and is never masked by the header fade), else as a background.
    @ViewBuilder
    func pageBackdrop() -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            containerBackground(for: .navigation) { HouseBackdrop() }
        } else {
            background { HouseBackdrop() }
        }
        #else
        background { HouseBackdrop() }
        #endif
    }
}

#if os(iOS)
/// Hides the root `UITabBarController` (every page and its UIKit navigation bar) from assistive
/// technologies while the flyout covers it.
///
/// SwiftUI's `accessibilityHidden` on the `TabView` or on a page did not reach the UIKit navigation bar:
/// the iPad audit still read the large title under the scrim (2.5:1). The flyout is a sibling outside the
/// tab controller, so it stays reachable.
private struct TabControllerAccessibilityHider: UIViewRepresentable {
    var hidden: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        let hidden = hidden
        // Next turn: on the first update the view is not in a window yet.
        DispatchQueue.main.async {
            var responder: UIResponder? = view
            while let current = responder, !(current is UIViewController) { responder = current.next }
            guard let tabs = (responder as? UIViewController)?.tabBarController,
                  tabs.view.accessibilityElementsHidden != hidden else { return }
            tabs.view.accessibilityElementsHidden = hidden
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }
}
#endif
