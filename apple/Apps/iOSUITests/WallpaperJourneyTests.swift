import XCTest

/// The wallpaper covers the whole window (`.agents/patterns/page-backdrop.md` R7).
///
/// Owner, 2026-10-16 (iPhone 18 Pro, Release): "Blurred image does not take full phone space". The photo ended at the
/// bottom of the safe-area rect, so a band of the plain base color showed under the tab bar and the home indicator on
/// every tab root and pushed page. These journeys launch with `FENTON_BACKDROP_FIXTURE=1`, a bright synthetic photo
/// that stays several times brighter than the plain base color under every scrim stop, then sample the four corners
/// and four edge midpoints of a screenshot and fail on any that is as dark as the base: on each tab root and pushed
/// page, scrolled to the bottom, and after backgrounding the app and returning.
///
/// iPad runs portrait and (`TEST_RUNNER_FENTON_UITEST_ORIENTATION=landscape`) landscape; the folded iPhone Duo is
/// portrait like the iPhone. Skips without credentials.
@MainActor
final class WallpaperJourneyTests: JourneyTestCase {
    /// WCAG relative luminance below which a sample is the plain base (`#111723` under 0.44 black is 0.004; the
    /// fixture photo under the densest scrim, 0.64, is about 0.05).
    private static let wallpaperFloor = 0.02
    /// Points in from the window's edge, clear of the antialiased rim.
    private static let edgeInset: CGFloat = 4

    private func launch() throws -> XCUIApplication {
        // `nav.profile` is on every section root: the app reopens on the section the last run left (SceneStorage).
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_BACKDROP_FIXTURE": "1"], readyIdentifier: "nav.profile")
        openHome(in: app)
        return app
    }

    // MARK: - Sampling

    /// The window's corners and edge midpoints, in screen points.
    private func samplePoints(of window: CGRect) -> [(name: String, point: CGPoint)] {
        let inset = Self.edgeInset
        let (minX, maxX, minY, maxY) = (window.minX + inset, window.maxX - inset, window.minY + inset, window.maxY - inset)
        return [
            ("top-left", CGPoint(x: minX, y: minY)), ("top", CGPoint(x: window.midX, y: minY)),
            ("top-right", CGPoint(x: maxX, y: minY)), ("left", CGPoint(x: minX, y: window.midY)),
            ("right", CGPoint(x: maxX, y: window.midY)), ("bottom-left", CGPoint(x: minX, y: maxY)),
            ("bottom", CGPoint(x: window.midX, y: maxY)), ("bottom-right", CGPoint(x: maxX, y: maxY)),
        ]
    }

    /// The samples that show the plain base instead of the photo, with their luminance.
    private func uncovered(in app: XCUIApplication) -> [String] {
        let window = app.windows.firstMatch.frame
        guard let capture = RenderedContrast.Capture.screen() else { return ["no capture"] }
        return samplePoints(of: window).compactMap { name, point in
            guard let luminance = RenderedContrast.luminance(at: point, in: capture) else { return "\(name) off the capture" }
            return luminance < Self.wallpaperFloor ? "\(name) \(String(format: "%.4f", luminance))" : nil
        }
    }

    /// Asserts the wallpaper reaches every sampled edge of the window. Polls for a few seconds: the fixture photo is
    /// rendered once at launch and a pushed page is still sliding in for a moment.
    private func assertCovered(_ app: XCUIApplication, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        var missing = uncovered(in: app)
        let deadline = Date().addingTimeInterval(8)
        while !missing.isEmpty, Date() < deadline {
            usleep(500_000)
            missing = uncovered(in: app)
        }
        keepScreenshot(app, "wallpaper-\(name)-\(layout)")
        saveToCaptureFolder(name)
        XCTAssertTrue(missing.isEmpty, "\(name) (\(layout)): plain background at \(missing.joined(separator: ", "))", file: file, line: line)
    }

    /// With `FENTON_WALLPAPER_DIR` set, also writes the screenshot there (before and after comparisons).
    private func saveToCaptureFolder(_ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["FENTON_WALLPAPER_DIR"] else { return }
        let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name)-\(layout).png")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }

    // MARK: - Navigation

    private func openHome(in app: XCUIApplication) {
        openSection("home", title: "Home", in: app)
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15), "Home did not appear")
    }

    private func openRoot(_ section: String, _ title: String, in app: XCUIApplication) {
        openSection(section, title: title, in: app)
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 15), "\(title) did not appear")
    }

    /// Drags the page up repeatedly so its end (and the bounce past it) is under the tab bar.
    private func scrollToBottom(_ app: XCUIApplication) {
        let window = app.windows.firstMatch
        for _ in 0..<10 {
            // Short of the trailing edge on the folded Duo, where the vertical tab bar sits.
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.8))
            from.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.15)),
                       withVelocity: .fast, thenHoldForDuration: 0)
        }
        sleep(1)
    }

    /// Drags the page down repeatedly so its top is showing.
    private func scrollToTop(_ app: XCUIApplication) {
        let window = app.windows.firstMatch
        for _ in 0..<10 {
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.2))
            from.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.85)),
                       withVelocity: .fast, thenHoldForDuration: 0)
        }
        sleep(1)
    }

    /// Scrolls until `target` can be tapped, then taps it.
    private func tap(_ id: String, in app: XCUIApplication) {
        let target = element(id, in: app)
        XCTAssertTrue(target.waitForExistence(timeout: 15), "\(id) missing")
        let window = app.windows.firstMatch
        for _ in 0..<24 where !(target.exists && target.isHittable) {
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.65))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -220)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(target.isHittable, "\(id) never came into view")
        target.tap()
    }

    private func openQuickLinks(in app: XCUIApplication) {
        openSection("quickLinks", title: "Quick Links", in: app)
        XCTAssertTrue(element("quickLinks.rooms", in: app).waitForExistence(timeout: 10), "Quick Links did not open")
    }

    // MARK: - Journeys

    /// Every tab root, at the top and scrolled to the bottom.
    func testTabRootsCoverTheWindow() throws {
        let app = try launch()
        assertCovered(app, "home")
        scrollToBottom(app)
        assertCovered(app, "home-bottom")
        for (section, title) in [("security", "Security"), ("climate", "Climate"), ("chores", "Chores")] {
            openRoot(section, title, in: app)
            assertCovered(app, section)
            scrollToBottom(app)
            assertCovered(app, "\(section)-bottom")
        }
        openHome(in: app) // The next launch reopens here.
    }

    /// A to-do list pushed over Chores in the section stack, then (where Quick Links is a tab, not a sheet) a room, Food
    /// and Media pushed over Quick Links; each at the top and scrolled to the bottom. Regular width presents Quick
    /// Links as a sheet, which draws no wallpaper (R3), so its pages are skipped there.
    func testPushedPagesCoverTheWindow() throws {
        let app = try launch()
        openRoot("chores", "Chores", in: app)
        tap("chores.link.groceries", in: app)
        XCTAssertTrue(app.navigationBars["Groceries"].waitForExistence(timeout: 15), "Groceries did not open")
        assertCovered(app, "todo-list")
        scrollToBottom(app)
        assertCovered(app, "todo-list-bottom")
        openHome(in: app)

        openQuickLinks(in: app)
        if app.buttons["quickLinks.close"].exists {
            app.buttons["quickLinks.close"].tap()
            return
        }
        assertCovered(app, "quick-links")
        tap("quickLinks.rooms", in: app)
        tap("rooms.master-bedroom", in: app)
        XCTAssertTrue(element("room.scroll.master-bedroom", in: app).waitForExistence(timeout: 15), "Master Bedroom did not open")
        assertCovered(app, "room")
        scrollToBottom(app)
        assertCovered(app, "room-bottom")
        for (page, scroll) in [("food", "food.scroll"), ("media", "media.scroll")] {
            // A tab bar that tucked away while the page scrolled comes back at the top.
            scrollToTop(app)
            openQuickLinks(in: app)
            tap("quickLinks.\(page)", in: app)
            XCTAssertTrue(element(scroll, in: app).waitForExistence(timeout: 15), "\(page) did not open")
            assertCovered(app, page)
            scrollToBottom(app)
            assertCovered(app, "\(page)-bottom")
        }
        scrollToTop(app)
        openHome(in: app)
    }

    /// Sending the app to the background and returning keeps the wallpaper: Home, then a pushed page.
    func testBackgroundAndForegroundKeepTheWindowCovered() throws {
        let app = try launch()
        assertCovered(app, "before-background")
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15), "Home did not return")
        assertCovered(app, "after-foreground")
        scrollToBottom(app)
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        sleep(1)
        assertCovered(app, "after-foreground-scrolled")
    }
}
