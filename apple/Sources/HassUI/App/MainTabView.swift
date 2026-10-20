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
    @State private var windowTop: CGFloat = 0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(HassConnection.self) private var connection: HassConnection?
    @Environment(PushCoordinator.self) private var push: PushCoordinator?
    @Environment(LocationCoordinator.self) private var location: LocationCoordinator?

    private var style: ShellNavigationStyle {
        ShellNavigationStyle.resolve(isRegularWidth: horizontalSizeClass == .regular)
    }

    private var chrome: ShellChrome { .resolve(style: style) }

    var body: some View {
        ZStack(alignment: .leading) {
            tabs
                // The Chores tab's badge: the viewer's overdue chores, the count Profile and Your Summary read.
                .modifier(OverdueChoresBadge())
                // While the flyout is open its scrim covers the content; hide the content from VoiceOver too.
                .accessibilityHidden(while: navigator.isFlyoutOpen)
                .flyoutEdgeSwipe(navigator, isEnabled: chrome.showsMenuButton)
            if chrome.showsMenuButton {
                NavigationFlyout()
            }
        }
        // Also behind the root, where no page draws: under the tab bar and the home indicator.
        .background { HouseBackdrop() }
        // The status bar's height, for where the inline navigation bar ends (``headerEdgeCap``).
        .background {
            Color.clear.onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top.rounded() } action: { windowTop = $0 }
        }
        .environment(navigator)
        .environment(\.shellNavigationStyle, style)
        .environment(\.shellChrome, chrome)
        // The window's full size, which the page backdrop wallpaper is rendered for and fills on every page.
        .backdropCanvasProvider()
        .environment(\.headerEdgeCap, headerEdgeCap)
        // Direction G: pages sit on the dimmed house photo, so the signed-in shell is always dark. Sheets follow the
        // system appearance instead: `RootView` publishes it, and `hassSheet()` / `HassModal` apply it to themselves
        // (`.agents/design/direction-g.md`, Layers; plan decision 6).
        .preferredColorScheme(.dark)
        .onAppear { navigator.selection = storedSelection }
        // A scroll cost launch (`FENTON_SCROLLCOST_OPEN`) starts on the page it measures.
        .task { if let path = ScrollCostProbe.launchPath { navigator.open(PushDestination(dashboardPath: path)) } }
        .onChange(of: navigator.selection) { _, section in storedSelection = section }
        // A notification's page: also on appear, for a tap that launched the app.
        .onChange(of: push?.pendingRequest, initial: true) { _, request in
            guard let request else { return }
            navigator.open(request.destination, anchor: request.anchor)
            push?.didOpen(request)
        }
        .onChange(of: style) { _, newStyle in
            if newStyle == .tabBar, !chrome.showsMenuButton { navigator.dismissFlyout() }
        }
        // Again once connected: a lookup before the socket is up fails, and the cached name stays meanwhile.
        .task(id: isConnected) { await loadProfileName() }
    }

    /// The root tab view: one `TabView` for every system, the glass floating bar on iOS 26 and the standard bar before
    /// it. Five tabs (owner, 2026-10-16): Quick Links is a header button now, not a trailing tab.
    private var tabs: some View {
        @Bindable var navigator = navigator
        return TabView(selection: $navigator.selection) {
            ForEach(AppSection.allCases) { section in
                sectionStack(for: section)
                    .tabItem { Label(section.title, systemImage: section.symbol) }
                    .badge(NavigationMenu.badge(for: section, overdue: navigator.overdueChores) ?? 0)
                    .tag(section)
            }
        }
    }

    /// A section's stack. Every section pushes full width; Settings pushes its topics on the same path.
    @ViewBuilder
    private func sectionStack(for section: AppSection) -> some View {
        NavigationStack(path: navigator.path(for: section)) {
            Group {
                switch section {
                // Inventory pages until the Food & Recipes hub links them (FENTON_OPEN_INVENTORY in debug).
                case .home: HomeScreen().inventoryDestinations()
                case .security: SecurityScreen()
                case .climate: ClimateScreen()
                case .chores: ChoresScreen()
                case .settings: SettingsTabRoot()
                }
            }
            .sectionRootChrome()
            .pageChrome()
            // Pages a notification opens (``ShellNavigator/open(_:)``) or Quick Links chooses.
            .navigationDestination(for: HomeRoute.self) { HomeRouteDestination(route: $0).pageChrome() }
            .navigationDestination(for: HouseholdSettingsPage.self) { HouseholdSettingsDestination(page: $0).pageChrome() }
            .navigationDestination(for: SettingsRoute.self) { SettingsRouteDestination(route: $0).pageChrome() }
        }
        .shellSheets(caller: connection)
        .environment(\.shellSection, section)
        .environment(\.sectionIsShowing, navigator.isShowing(section))
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

    /// Reads the signed-in user for the profile button (the cached name shows until it arrives) and for the
    /// `mobile_app` registration, which is per Home Assistant user; then offers location once the notification
    /// alert is answered, so the two never stack.
    private func loadProfileName() async {
        guard let connection, let user = try? await connection.currentUser() else { return }
        if navigator.profileName != user.name { navigator.profileName = user.name }
        // Who is viewing, for the Profile badge and sheet (Your Summary) before the Chores tab has ever been opened;
        // the Chores model reads and writes the same key.
        UserDefaults.standard.set(user.id, forKey: ChoresModel.viewerDefaultsKey)
        await push?.didConnect(userID: user.id, userName: user.name)
        location?.offerPermissionIfNeeded()
    }
}

extension View {
    /// Shell chrome every page in a section stack applies, pushed pages included: the header fade (no
    /// translucent band behind the navigation bar; ``HeaderEdgeFade``), the blurred house backdrop
    /// (``HouseBackdrop``), and the root tab bar hidden in flyout style (on iPadOS 18+ the floating top tab bar
    /// too). A pushed page without it brings the tab bar back and draws no backdrop.
    func pageChrome() -> some View { modifier(PageChrome()) }
}

/// Implementation of ``SwiftUI/View/pageChrome()``. Inside a sheet a page takes the sheet's chrome instead: wallpaper
/// is never drawn in sheets (direction G, Layers), and the header buttons belong to pages, not sheets.
private struct PageChrome: ViewModifier {
    @Environment(\.shellNavigationStyle) private var style
    @Environment(\.shellChrome) private var chrome
    @Environment(ShellNavigator.self) private var navigator: ShellNavigator?
    @Environment(\.tileSurface) private var surface

    func body(content: Content) -> some View {
        if surface == .sheet {
            content.modalChrome()
        } else {
            pageContent(content)
        }
    }

    @ViewBuilder
    private func pageContent(_ content: Content) -> some View {
        let isFlyoutOpen = navigator?.isFlyoutOpen ?? false
        #if os(iOS)
        // Both layers: SwiftUI vends a page's own elements past UIKit, and the UIKit navigation bar is
        // out of SwiftUI's reach.
        content
            .headerEdgeFade()
            .shellHeaderButtons()
            .toolbarTitleDisplayMode(chrome.titleInHeader ? .inlineLarge : .automatic)
            .scrollContentBackground(.hidden)
            .pageBackdrop()
            .accessibilityHidden(while: isFlyoutOpen)
            .toolbar(style == .flyout ? .hidden : .automatic, for: .tabBar)
            .background(TabControllerAccessibilityHider(hidden: isFlyoutOpen))
        #else
        content
            .headerEdgeFade()
            .shellHeaderButtons()
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
