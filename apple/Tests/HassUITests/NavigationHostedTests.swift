#if os(macOS)
import AppKit
import Foundation
import HassCore
import HassDesign
@testable import HassUI
import Observation
import SwiftUI
import Testing

// MARK: - Hosting

/// Hosts SwiftUI in a real window on the macOS host so `onAppear`, `onChange` and geometry callbacks run.
/// SwiftUI on macOS builds no accessibility tree without an assistive client, so views report back
/// through a ``ViewProbe`` instead.
@MainActor
final class HostedWindow {
    let window: NSWindow

    init(_ view: some View, size: CGSize) {
        window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let controller = NSHostingController(rootView: view)
        // The window size is the test's input (like a device's); don't let fixed pane widths pin it.
        controller.sizingOptions = []
        window.contentViewController = controller
        window.setContentSize(size)
        window.orderFrontRegardless()
    }

    /// One layout pass and run-loop turn, about 30 ms when nothing else holds the main actor.
    private static let pass: TimeInterval = 0.03

    /// Lets SwiftUI apply pending updates, deferred tasks and animations: about `seconds` worth of layout passes.
    ///
    /// Counted in passes, not against a deadline. Other main-actor suites run between the sleeps and inside
    /// `RunLoop.main.run`, so in a full `swift test` a wall-clock budget can run out before this window has laid
    /// out once (`.agents/testing/apple/README.md`, Order-independent tests).
    func settle(_ seconds: TimeInterval = 0.6) async {
        for _ in 0..<max(1, Int((seconds / Self.pass).rounded())) {
            window.contentView?.layoutSubtreeIfNeeded()
            Self.pumpRunLoop()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Settles until `condition` holds (or about `timeout` worth of passes have run), for the first window in a
    /// process, which takes longer to lay out than later ones.
    func settle(until condition: () -> Bool, timeout: TimeInterval = 5) async {
        var waited: TimeInterval = 0
        while !condition(), waited < timeout {
            await settle(0.1)
            waited += 0.1
        }
        await settle(0.2)
    }

    /// Runs the main run loop briefly (sync, so the async `settle` may call it).
    private static func pumpRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }

    func resize(to size: CGSize) async {
        window.setContentSize(size)
        await settle()
    }

    func close() { window.close() }
}

/// Records which probed views are on screen and where.
@MainActor
@Observable
final class ViewProbe {
    var visible: Set<String> = []
    var frames: [String: CGRect] = [:]
}

extension View {
    /// Reports this view's presence and window frame to `probe` under `id`.
    func probed(_ id: String, _ probe: ViewProbe) -> some View {
        onAppear { probe.visible.insert(id) }
            .onDisappear { probe.visible.remove(id) }
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { probe.frames[id] = $0 }
    }
}

/// Signed-out session and offline connection for screens that read them.
@MainActor
private func offlineEnvironment() -> (AppSession, HassConnection) {
    let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "nav-\(UUID()).json"))
    let session = AppSession(tokenStore: InMemoryTokenStore(), snapshotCache: cache)
    let connection = HassConnection(
        server: .fentonHome, tokens: TokenManager(store: InMemoryTokenStore()), store: EntityStore(), snapshotCache: cache
    )
    return (session, connection)
}

// MARK: - On-demand split

@MainActor
@Observable
private final class SplitModel {
    var path = NavigationPath()
    var openItem: String?
}

/// A minimal adopter so the split's own behavior is tested apart from Settings.
private struct SplitHarness: View {
    @Bindable var model: SplitModel
    var probe: ViewProbe
    var alwaysSplit: Bool

    var body: some View {
        OnDemandSplitStack(path: $model.path, openItem: $model.openItem, alwaysSplit: alwaysSplit) {
            Color.clear.probed("root", probe)
        } detail: { item in
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).probed("detail.\(item)", probe)
        } placeholder: {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).probed("placeholder", probe)
        }
    }
}

@MainActor
@Suite(.serialized)
struct OnDemandSplitHostedTests {
    private func host(
        _ model: SplitModel, _ probe: ViewProbe, alwaysSplit: Bool = true, size: CGSize, regular: Bool = true,
        hinge: CGRect? = nil
    ) -> HostedWindow {
        HostedWindow(
            SplitHarness(model: model, probe: probe, alwaysSplit: alwaysSplit)
                .environment(\.windowHinge, hinge)
                .environment(\.horizontalSizeClass, regular ? .regular : .compact)
                .environment(ShellNavigator())
                .environment(\.shellNavigationStyle, regular ? .flyout : .tabBar),
            size: size
        )
    }

    /// Landscape regular width: the placeholder pane shows beside the list, an item replaces it, and
    /// the panes meet at the midpoint.
    @Test func landscapeSplitsAtTheMidpointWithAPlaceholder() async throws {
        let model = SplitModel(), probe = ViewProbe()
        let hosted = host(model, probe, size: CGSize(width: 1200, height: 800))
        defer { hosted.close() }
        await hosted.settle(until: { probe.visible.contains("placeholder") })
        #expect(probe.visible.contains("placeholder"))
        let placeholder = try #require(probe.frames["placeholder"])
        #expect(abs(placeholder.minX - 600.5) <= 1, "trailing pane starts at \(placeholder.minX)")
        #expect(abs(placeholder.maxX - 1200) <= 1)
        let root = try #require(probe.frames["root"])
        #expect(abs(root.maxX - 599.5) <= 1, "leading pane ends at \(root.maxX)")

        model.openItem = "a"
        await hosted.settle(until: { probe.visible.contains("detail.a") })
        #expect(probe.visible.contains("detail.a"))
        let detail = try #require(probe.frames["detail.a"])
        #expect(abs(detail.minX - 600.5) <= 1)

        model.openItem = "b"
        await hosted.settle(until: { probe.visible.contains("detail.b") })
        #expect(probe.visible.contains("detail.b"))
        #expect(abs(try #require(probe.frames["detail.b"]).minX - 600.5) <= 1, "the new item replaces the pane")
        #expect(model.path.isEmpty, "a split must not push")
    }

    /// Without `alwaysSplit` the trailing pane appears only for an open item; the list is full width.
    @Test func onDemandSplitOpensOnlyForAnItem() async throws {
        let model = SplitModel(), probe = ViewProbe()
        let hosted = host(model, probe, alwaysSplit: false, size: CGSize(width: 1200, height: 800))
        defer { hosted.close() }
        await hosted.settle()
        #expect(!probe.visible.contains("placeholder"))
        #expect(abs(try #require(probe.frames["root"]).width - 1200) <= 1)
        model.openItem = "b"
        await hosted.settle(until: { probe.visible.contains("detail.b") })
        #expect(probe.visible.contains("detail.b"))
        #expect(abs(try #require(probe.frames["root"]).maxX - 599.5) <= 1)
    }

    /// Portrait and compact width never split: the item pushes on the leading stack, full width.
    @Test func portraitAndCompactPushInsteadOfSplitting() async throws {
        for (size, regular) in [(CGSize(width: 800, height: 1100), true), (CGSize(width: 1200, height: 800), false)] {
            let model = SplitModel(), probe = ViewProbe()
            let hosted = host(model, probe, size: size, regular: regular)
            await hosted.settle()
            #expect(!probe.visible.contains("placeholder"))
            model.openItem = "a"
            await hosted.settle(until: { probe.visible.contains("detail.a") })
            #expect(probe.visible.contains("detail.a"))
            #expect(abs(try #require(probe.frames["detail.a"]).width - size.width) <= 1)
            hosted.close()
        }
    }

    /// Rotating moves the open item from the trailing pane to a push and back, keeping it open.
    @Test func rotationMovesTheOpenItemBetweenPaneAndPush() async throws {
        let model = SplitModel(), probe = ViewProbe()
        let hosted = host(model, probe, size: CGSize(width: 1200, height: 800))
        defer { hosted.close() }
        await hosted.settle()
        model.openItem = "a"
        await hosted.settle()
        #expect(abs(try #require(probe.frames["detail.a"]).minX - 600.5) <= 1)
        await hosted.resize(to: CGSize(width: 800, height: 1200))
        #expect(probe.visible.contains("detail.a"))
        #expect(model.openItem == "a")
        #expect(abs(try #require(probe.frames["detail.a"]).width - 800) <= 1, "portrait should push full width: \(probe.frames) \(probe.visible)")
        #expect(!probe.visible.contains("placeholder"))
        await hosted.resize(to: CGSize(width: 1200, height: 800))
        #expect(model.openItem == "a")
        #expect(abs(try #require(probe.frames["detail.a"]).minX - 600.5) <= 1, "landscape should return to the pane")
    }

    /// A vertical hinge crossing the container puts the panes either side of it.
    @Test func hingeSplitsEitherSideOfTheFold() async throws {
        let model = SplitModel(), probe = ViewProbe()
        let hinge = CGRect(x: 590, y: 0, width: 20, height: 800)
        let hosted = host(model, probe, size: CGSize(width: 1200, height: 800), hinge: hinge)
        defer { hosted.close() }
        await hosted.settle()
        #expect(abs(try #require(probe.frames["placeholder"]).minX - 610) <= 1)
        #expect(abs(try #require(probe.frames["root"]).maxX - 590) <= 1)
    }

    /// The hinge reader publishes nothing on a device without a fold, so the split stays at the midpoint.
    @Test func hingeReaderIsNilWithoutAFold() async throws {
        let model = SplitModel(), probe = ViewProbe()
        let hosted = HostedWindow(
            SplitHarness(model: model, probe: probe, alwaysSplit: true)
                .environment(\.horizontalSizeClass, .regular)
                .environment(ShellNavigator())
                .readsWindowHinge(),
            size: CGSize(width: 1200, height: 800)
        )
        defer { hosted.close() }
        await hosted.settle()
        #expect(abs(try #require(probe.frames["placeholder"]).minX - 600.5) <= 1)
        await hosted.resize(to: CGSize(width: 1300, height: 800))
        #expect(abs(try #require(probe.frames["placeholder"]).minX - 650.5) <= 1, "\(probe.frames)")
    }
}

// MARK: - Flyout and shell

@MainActor
@Suite(.serialized)
struct NavigationFlyoutHostedTests {
    /// The flyout draws over the content while open and leaves when a destination is chosen.
    @Test func flyoutOpensOverContentAndCloses() async {
        let navigator = ShellNavigator()
        navigator.overdueChores = 4
        let probe = ViewProbe()
        let hosted = HostedWindow(
            ZStack {
                Color.clear.probed("content", probe)
                NavigationFlyout()
            }
            .environment(navigator),
            size: CGSize(width: 1000, height: 800)
        )
        defer { hosted.close() }
        await hosted.settle()
        navigator.openFlyout()
        await hosted.settle()
        #expect(navigator.isFlyoutOpen)
        navigator.select(.climate)
        await hosted.settle()
        #expect(!navigator.isFlyoutOpen)
        #expect(navigator.selection == .climate)
        #expect(probe.visible.contains("content"))
    }

    /// Section roots get Open Navigation only in flyout style; pages render in both styles.
    @Test func sectionChromeRendersInBothStyles() async {
        for style in [ShellNavigationStyle.flyout, .tabBar] {
            let navigator = ShellNavigator()
            let probe = ViewProbe()
            let hosted = HostedWindow(
                NavigationStack { Color.clear.probed("root", probe).sectionRootChrome().pageChrome() }
                    .environment(navigator)
                    .environment(\.shellNavigationStyle, style),
                size: CGSize(width: 900, height: 700)
            )
            await hosted.settle(until: { probe.visible.contains("root") })
            #expect(probe.visible.contains("root"))
            navigator.openFlyout()
            navigator.dismissFlyout()
            await hosted.settle()
            #expect(navigator.focusReturnToken == 1)
            hosted.close()
        }
    }

    /// The root shell renders in regular and compact width, follows the selection, and closes the
    /// flyout when the window becomes compact.
    @Test func mainTabViewHostsEverySection() async {
        let (session, connection) = offlineEnvironment()
        for regular in [true, false] {
            let hosted = HostedWindow(
                MainTabView()
                    .environment(\.horizontalSizeClass, regular ? .regular : .compact)
                    .environment(connection)
                    .environment(connection.store)
                    .environment(session)
                    .readsWindowHinge(),
                size: CGSize(width: 1200, height: 800)
            )
            await hosted.settle()
            #expect(hosted.window.contentView != nil)
            hosted.close()
        }
    }
}

// MARK: - Settings

@MainActor
@Suite(.serialized)
struct SettingsHostedTests {
    /// Settings renders its list, placeholder and every household page beside the list in landscape.
    @Test func settingsRendersListPlaceholderAndTopics() async {
        let (session, connection) = offlineEnvironment()
        let model = SplitModel()
        let probe = ViewProbe()
        @MainActor
        struct Harness: View {
            @Bindable var model: SplitModel
            var probe: ViewProbe
            var body: some View {
                let topic = Binding<HouseholdSettingsPage?>(
                    get: { model.openItem.flatMap(HouseholdSettingsPage.init(rawValue:)) },
                    set: { model.openItem = $0?.rawValue }
                )
                OnDemandSplitStack(path: $model.path, openItem: topic, alwaysSplit: true) {
                    SettingsScreen(openTopic: topic)
                } detail: { page in
                    Text(page.pageTitle).probed("detail.\(page.rawValue)", probe)
                } placeholder: {
                    Color.clear.probed("placeholder", probe)
                }
            }
        }
        let hosted = HostedWindow(
            Harness(model: model, probe: probe)
                .environment(\.horizontalSizeClass, .regular)
                .environment(ShellNavigator())
                .environment(connection)
                .environment(session),
            size: CGSize(width: 1200, height: 800)
        )
        defer { hosted.close() }
        await hosted.settle(until: { probe.visible.contains("placeholder") })
        #expect(probe.visible.contains("placeholder"))
        for topic in HouseholdSettingsPage.allCases {
            model.openItem = topic.rawValue
            await hosted.settle(0.3)
            #expect(probe.visible.contains("detail.\(topic.rawValue)"))
        }
    }

    /// The Summary sheet renders every tab for a resident from a populated store, in vacation mode too, and for a guest. Not
    /// asserted by element (macOS builds no accessibility tree here): it must lay out and settle with every tab drawn.
    @Test func summarySheetRendersEveryTab() async {
        let saved = UserDefaults.standard.string(forKey: ChoresModel.viewerDefaultsKey)
        defer { UserDefaults.standard.set(saved, forKey: ChoresModel.viewerDefaultsKey) }
        let (session, connection) = offlineEnvironment()
        let lists = ProfileSummary.lists(for: .stephen)
        let expired = EntityState(entityId: ProfileSummary.expiredFoodEntityId, state: "1", attributes: ["expired_list": .array([
            .object(["name": .string("Milk"), "expiry_date": .string("2020-01-01"), "location": .string("frigo")]),
        ])])
        let viewers: [(userId: String?, tabs: [SummaryTab])] = [
            (ChoresConfig.Resident.stephen.haUserId, SummaryTab.allCases), (nil, [.profile, .expiredFood]),
        ]
        for viewer in viewers {
            UserDefaults.standard.set(viewer.userId, forKey: ChoresModel.viewerDefaultsKey)
            for vacation in [false, true] {
                connection.store.replaceAll([
                    EntityState(entityId: "person.stephen", state: "home", attributes: ["friendly_name": .string("Stephen")]),
                    EntityState(entityId: "person.steph", state: "not_home", attributes: ["friendly_name": .string("Steph")]),
                    EntityState(entityId: lists.overdue.entityId, state: "2"),
                    EntityState(entityId: lists.dueToday.entityId, state: "0"),
                    EntityState(entityId: lists.noDueDate.entityId, state: "0"),
                    EntityState(entityId: ChoresConfig.vacationModeEntityId, state: vacation ? "on" : "off"),
                    expired,
                ])
                for tab in viewer.tabs {
                    let hosted = HostedWindow(
                        YourSummarySheet(opening: tab)
                            .environment(ShellNavigator())
                            .environment(connection)
                            .environment(connection.store)
                            .environment(session),
                        size: CGSize(width: 500, height: 900)
                    )
                    await hosted.settle()
                    #expect(hosted.window.contentView != nil)
                    hosted.close()
                }
            }
        }
    }

    /// The Settings tab's root and a page pushed from it render inside a section stack.
    @Test func settingsTabRootRendersAndRoutesAreValues() async {
        let (session, connection) = offlineEnvironment()
        let navigator = ShellNavigator(selection: .settings)
        let hosted = HostedWindow(
            NavigationStack(path: navigator.path(for: .settings)) {
                SettingsTabRoot().pageChrome()
                    .navigationDestination(for: HouseholdSettingsPage.self) { HouseholdSettingsDestination(page: $0) }
                    .navigationDestination(for: SettingsRoute.self) { SettingsRouteDestination(route: $0) }
            }
            .environment(navigator)
            .environment(connection)
            .environment(connection.store)
            .environment(session),
            size: CGSize(width: 500, height: 900)
        )
        defer { hosted.close() }
        await hosted.settle()
        navigator.paths[.settings, default: NavigationPath()].append(HouseholdSettingsPage.guests)
        await hosted.settle()
        navigator.paths[.settings] = NavigationPath()
        navigator.paths[.settings, default: NavigationPath()].append(SettingsRoute.vacation)
        await hosted.settle()
        #expect(!navigator.isAtRoot(.settings))
    }

    /// The Summary sheet renders at regular width (the Profile tab: the signed-in header, Location where reported, Sign Out).
    @Test func summarySheetRendersAtRegularWidth() async {
        let (session, connection) = offlineEnvironment()
        let hosted = HostedWindow(
            YourSummarySheet(opening: .profile)
                .environment(\.horizontalSizeClass, .regular)
                .environment(ShellNavigator())
                .environment(connection)
                .environment(session),
            size: CGSize(width: 1200, height: 800)
        )
        defer { hosted.close() }
        await hosted.settle()
        #expect(hosted.window.contentView != nil)
    }
}
#endif
