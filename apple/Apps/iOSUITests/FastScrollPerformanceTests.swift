import XCTest

/// Flicks every page as fast as a person can and measures the result (`.agents/testing/apple/performance.md`).
///
/// **Run these on a physical device.** Simulators render on the Mac's GPU with a different compositor and report
/// hitch numbers that mean nothing for an iPhone, so the measured tests skip on a simulator unless
/// `TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1`. ``testEveryPageFlicksWithoutLosingContent`` runs everywhere: it proves each
/// page opens, scrolls fast in both directions and still shows its content (a smoke test for the measured runs).
///
/// Metrics per page (Xcode's test report shows each with its baseline):
/// - `scrollDecelerationMetric` / `scrollDraggingMetric`: the system's hitch time ratio while flinging and dragging.
/// - App signposts (`com.sfenton.home` / `Performance`): `EntityUpdate` (live updates applied during the scroll) and
///   `ImageDecode`.
/// - `XCTClockMetric` and `XCTCPUMetric` for the whole flick sequence.
///
/// Pages come from the debug gallery's fixtures by default, so the numbers compare across runs. With
/// `TEST_RUNNER_FENTON_PERF_LIVE=1` and sign-in credentials, the tab pages run against the live server instead
/// (real entity counts and live updates arriving mid-scroll). Run with `tools/ios_perf.sh`.
@MainActor
final class FastScrollPerformanceTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    // MARK: - Pages

    /// One page to flick: how to open it and the identifier of its scroll view.
    struct Page {
        var name: String
        var scrollId: String
        var gallery: String
        var environment: [String: String] = [:]
    }

    static let pages: [Page] = [
        Page(name: "Grid workload", scrollId: "perf.grid", gallery: "performance", environment: ["FENTON_GALLERY_PERF": "grid"]),
        Page(name: "Living Room", scrollId: "room.scroll.living-room", gallery: "rooms",
             environment: ["FENTON_GALLERY_ROOM": "living-room", "FENTON_GALLERY_OFFLINE": "1"]),
        Page(name: "Music Room", scrollId: "room.scroll.music-room", gallery: "rooms",
             environment: ["FENTON_GALLERY_ROOM": "music-room", "FENTON_GALLERY_OFFLINE": "1"]),
        Page(name: "Climate", scrollId: "climate.scroll", gallery: "climate"),
        Page(name: "Security", scrollId: "security.scroll", gallery: "security"),
        Page(name: "Groceries", scrollId: "todo.page.groceries", gallery: "chores", environment: ["FENTON_GALLERY_TODO_PAGE": "groceries"]),
        Page(name: "Food", scrollId: "food.scroll", gallery: "food", environment: ["FENTON_GALLERY_ROUTE": "hub"]),
        Page(name: "Recipes", scrollId: "recipes.grid", gallery: "food", environment: ["FENTON_GALLERY_ROUTE": "recipes"]),
        Page(name: "Pantry", scrollId: "inventory.pantry", gallery: "inventory", environment: ["FENTON_GALLERY_SPACE": "pantry"]),
        Page(name: "Media", scrollId: "media.scroll", gallery: "media-page"),
        Page(name: "Custom Lights", scrollId: "customLights.scroll", gallery: "custom-lights"),
        Page(name: "Sprinklers", scrollId: "sprinklers.scroll", gallery: "sprinklers"),
        Page(name: "Admin settings", scrollId: "household.admin", gallery: "household-settings",
             environment: ["FENTON_GALLERY_HOUSEHOLD": "admin"]),
    ]

    private func page(_ name: String) throws -> Page {
        try XCTUnwrap(Self.pages.first { $0.name == name })
    }

    // MARK: - Running

    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    /// Skips measured runs on a simulator (they report false data) unless explicitly asked.
    private func requireMeasurableDevice() throws {
        if Self.isSimulator, Self.environment["FENTON_PERF_ON_SIMULATOR"] != "1" {
            throw XCTSkip("Scroll performance is measured on a physical device; simulators report false hitch data. "
                + "Set TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1 to run anyway.")
        }
    }

    private func launch(_ page: Page) -> (XCUIApplication, XCUIElement) {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = page.gallery
        app.launchEnvironment["FENTON_TELEMETRY"] = "1"
        app.launchEnvironment.merge(page.environment) { $1 }
        app.launch()
        let scroll = app.descendants(matching: .any)[page.scrollId].firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 30), "\(page.name) did not open")
        return (app, scroll)
    }

    /// Fast flicks down the page and back up, the way a person hunts for something.
    private func flick(_ scroll: XCUIElement, times: Int = 4) {
        for _ in 0..<times { scroll.swipeUp(velocity: .fast) }
        for _ in 0..<times { scroll.swipeDown(velocity: .fast) }
    }

    private var metrics: [any XCTMetric] {
        [
            XCTOSSignpostMetric.scrollDecelerationMetric,
            XCTOSSignpostMetric.scrollDraggingMetric,
            XCTOSSignpostMetric(subsystem: "com.sfenton.home", category: "Performance", name: "EntityUpdate"),
            XCTOSSignpostMetric(subsystem: "com.sfenton.home", category: "Performance", name: "ImageDecode"),
            XCTClockMetric(),
            XCTCPUMetric(),
        ]
    }

    private func measureFlicks(_ name: String) throws {
        try requireMeasurableDevice()
        let (_, scroll) = launch(try page(name))
        // One unmeasured pass warms caches (images, fonts), so every measured iteration sees the same state.
        flick(scroll, times: 2)
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: metrics, options: options) { flick(scroll) }
    }

    // MARK: - Smoke (every device, simulators included)

    /// Every page opens, survives fast flicks in both directions, and still shows its scroll view at the end.
    func testEveryPageFlicksWithoutLosingContent() throws {
        for page in Self.pages {
            let (app, scroll) = launch(page)
            flick(scroll, times: 2)
            XCTAssertTrue(scroll.exists, "\(page.name) lost its content after flicking")
            XCTAssertEqual(app.state, .runningForeground, "\(page.name) crashed while flicking")
            app.terminate()
        }
    }

    // MARK: - Measured (physical device)

    func testFlickGridWorkload() throws { try measureFlicks("Grid workload") }
    func testFlickLivingRoom() throws { try measureFlicks("Living Room") }
    func testFlickMusicRoom() throws { try measureFlicks("Music Room") }
    func testFlickClimate() throws { try measureFlicks("Climate") }
    func testFlickSecurity() throws { try measureFlicks("Security") }
    func testFlickGroceries() throws { try measureFlicks("Groceries") }
    func testFlickFood() throws { try measureFlicks("Food") }
    func testFlickRecipes() throws { try measureFlicks("Recipes") }
    func testFlickPantry() throws { try measureFlicks("Pantry") }
    func testFlickMedia() throws { try measureFlicks("Media") }
    func testFlickCustomLights() throws { try measureFlicks("Custom Lights") }
    func testFlickSprinklers() throws { try measureFlicks("Sprinklers") }
    func testFlickAdminSettings() throws { try measureFlicks("Admin settings") }

    // MARK: - Chip rail (sideways)

    private static let chipRailPage = Page(name: "Chip rail", scrollId: "perf.chips", gallery: "performance",
                                           environment: ["FENTON_GALLERY_PERF": "chips"])

    /// Fast swipes along the rail and back, the way a person looks for the chip they want.
    private func swipeRail(_ rail: XCUIElement, times: Int = 4) {
        for _ in 0..<times {
            rail.swipeLeft(velocity: .fast)
            rail.swipeRight(velocity: .fast)
        }
    }

    /// The rail scrolls sideways (the first chip moves off its start) and swipes in both directions leave the page standing.
    /// Compact width only (iPhone, folded Duo): a regular-width rail wraps, so there is nothing to scroll and no `chipRail.scroll`.
    func testChipRailSwipesWithoutLosingContent() throws {
        let (app, _) = launch(Self.chipRailPage)
        let rail = app.descendants(matching: .any)["chipRail.scroll"].firstMatch
        XCTAssertTrue(rail.waitForExistence(timeout: 10), "The chip rail did not open")
        let first = app.buttons["home.chip.lights"]
        let startX = first.frame.minX
        rail.swipeLeft(velocity: .fast)
        XCTAssertLessThan(first.frame.minX, startX, "The rail did not scroll sideways")
        swipeRail(rail, times: 2)
        XCTAssertEqual(app.state, .runningForeground, "The app crashed while swiping the rail")
        XCTAssertTrue(first.exists, "The chips vanished after swiping")
    }

    /// Hitch ratio, deceleration and CPU for fast sideways swipes of Home's six-chip rail over a page of 120 tiles
    /// (owner, 2026-10-16: "horizontal scrolling on status chips in pages is stutter[y]"). Set a baseline per device in
    /// Xcode's report; `.agents/testing/apple/performance.md` has the simulator profile that finds the cause.
    func testSwipeChipRail() throws {
        try requireMeasurableDevice()
        let (app, _) = launch(Self.chipRailPage)
        let rail = app.descendants(matching: .any)["chipRail.scroll"].firstMatch
        XCTAssertTrue(rail.waitForExistence(timeout: 10), "The chip rail did not open")
        swipeRail(rail, times: 2)
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        var railMetrics = metrics
        // The app-wide hitch time ratio over the whole swipe sequence (iOS 26 and later).
        if #available(iOS 26, *) { railMetrics.append(XCTHitchMetric(application: app)) }
        measure(metrics: railMetrics, options: options) { swipeRail(rail) }
    }

    // MARK: - Live server (physical device)

    /// Tab pages on the live server: real entity counts, with live updates arriving while the page scrolls.
    func testFlickLiveTabs() throws {
        try requireMeasurableDevice()
        guard Self.environment["FENTON_PERF_LIVE"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_FENTON_PERF_LIVE=1 (with sign-in credentials) to flick the live pages.")
        }
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_TELEMETRY": "1"])
        let tabs: [(section: String, title: String, scrollId: String)] = [
            ("home", "Home", "home.scroll"), ("security", "Security", "security.scroll"), ("climate", "Climate", "climate.scroll"),
        ]
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: metrics, options: options) {
            for tab in tabs {
                open(tab.section, title: tab.title, in: app)
                let scroll = app.descendants(matching: .any)[tab.scrollId].firstMatch
                guard scroll.waitForExistence(timeout: 10) else { continue }
                flick(scroll, times: 3)
            }
        }
    }

    /// Opens a section through the tab bar or, in regular width, the flyout.
    private func open(_ section: String, title: String, in app: XCUIApplication) {
        let flyoutButton = app.buttons["nav.open"]
        if flyoutButton.exists {
            flyoutButton.tap()
            app.buttons["nav.\(section)"].tap()
        } else {
            let item = app.tabBars.buttons[title]
            (item.exists ? item : app.toolbars.buttons[title]).tap()
        }
    }
}
