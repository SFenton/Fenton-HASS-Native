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
    /// How far (0-255, per channel) a sample may sit from the plain base under the scrim and still count as plain.
    private static let plainTolerance = 3
    /// Points in from the window's edge, clear of the antialiased rim.
    private static let edgeInset: CGFloat = 4
    /// The base color's channels (`HouseBackdropStyle.base`, `#111723`).
    private static let base = [17.0, 23.0, 35.0]
    /// The scrim's black opacity by fraction of the window height (`HouseBackdropStyle.scrimStops`).
    private static let scrim: [(location: Double, opacity: Double)] = [(0, 0.44), (0.28, 0.45), (0.50, 0.46), (0.75, 0.52), (1, 0.64)]

    /// The plain base color under the scrim at `fraction` of the window's height: what shows where there is no photo.
    private static func plain(atFraction fraction: Double) -> [Double] {
        let f = min(max(fraction, 0), 1)
        var opacity = scrim[scrim.count - 1].opacity
        for (low, high) in zip(scrim, scrim.dropFirst()) where f <= high.location {
            opacity = low.opacity + (high.opacity - low.opacity) * (f - low.location) / (high.location - low.location)
            break
        }
        return base.map { $0 * (1 - opacity) }
    }

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

    /// The samples that show the plain base (the fixture photo is far brighter, so only a dark page element, such as a
    /// full-bleed recipe photo, could come close, and it would not match the base to within a few levels), with their
    /// color.
    private func uncovered(in app: XCUIApplication) -> [String] {
        let window = app.windows.firstMatch.frame
        guard let capture = RenderedContrast.Capture.screen() else { return ["no capture"] }
        return samplePoints(of: window).compactMap { name, point in
            let x = Int(point.x * capture.scale), y = Int(point.y * capture.scale)
            guard x >= 0, y >= 0, x < capture.width, y < capture.height else { return "\(name) off the capture" }
            let i = (y * capture.width + x) * 4
            let pixel = [Double(capture.pixels[i]), Double(capture.pixels[i + 1]), Double(capture.pixels[i + 2])]
            let expected = Self.plain(atFraction: (point.y - window.minY) / window.height)
            let isPlain = zip(pixel, expected).allSatisfy { abs($0 - $1) <= Double(Self.plainTolerance) }
            return isPlain ? "\(name) rgb \(pixel.map { Int($0) })" : nil
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

    /// Back: the bar's back button, which the folded iPhone Duo moves to its rail.
    private func goBack(in app: XCUIApplication) {
        let back = app.buttons["BackButton"].firstMatch
        if back.exists { back.tap() } else { app.navigationBars.buttons.element(boundBy: 0).tap() }
    }

    /// Backs out of a page pushed over Quick Links until its tiles show again.
    private func backToQuickLinks(in app: XCUIApplication) {
        let tiles = element("quickLinks.rooms", in: app)
        for _ in 0..<4 where !(tiles.exists && tiles.isHittable) {
            goBack(in: app)
            sleep(1)
        }
        XCTAssertTrue(tiles.waitForExistence(timeout: 10), "Back did not return to Quick Links")
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
        app.buttons["quickLinks.open"].tap()
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
        goBack(in: app) // A pushed page has no menu or tab to leave through on regular width.
        XCTAssertTrue(app.navigationBars["Chores"].waitForExistence(timeout: 10), "Back did not return to Chores")
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
        // Back out to the tiles rather than reopening Quick Links from the bar: the folded Duo's vertical bar was not
        // reachable from a pushed page that had been scrolled.
        for (page, scroll) in [("food", "food.scroll"), ("media", "media.scroll")] {
            backToQuickLinks(in: app)
            tap("quickLinks.\(page)", in: app)
            XCTAssertTrue(element(scroll, in: app).waitForExistence(timeout: 15), "\(page) did not open")
            assertCovered(app, page)
            scrollToBottom(app)
            assertCovered(app, "\(page)-bottom")
        }
        backToQuickLinks(in: app)
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

// MARK: - Push frames

/// The page a push opens, and the page it covers, draw the wallpaper through the whole slide (`page-backdrop.md` R2).
///
/// Owner, 2026-10-20 (screen recordings): opening a page flashed black. The page sliding out has a negative window
/// position, and the photo was shifted by it, which pulled the photo off the edge still showing. The journey taps a
/// Settings row and takes screenshots back to back through the push, sampling both side columns; with the bright
/// fixture photo, a sample as dark as the plain base is a frame with no wallpaper. A screenshot takes about 0.1 s and
/// the push lasts about 0.35 s, so this catches the flash only on some frames; the simulator recording in the pull
/// request shows every frame.
@MainActor
final class PushFlickerJourneyTests: JourneyTestCase {
    private static let base = [17.0, 23.0, 35.0]

    private func darkSamples(_ capture: RenderedContrast.Capture, window: CGRect) -> [String] {
        [window.minX + 3, window.maxX - 3].flatMap { x in
            (1..<8).compactMap { row -> String? in
                let point = CGPoint(x: x, y: window.minY + window.height * Double(row) / 8)
                guard let rgb = RenderedContrast.rgb(at: point, in: capture) else { return nil }
                let dark = zip([rgb.red, rgb.green, rgb.blue], Self.base).allSatisfy { Double($0) <= $1 + 6 }
                return dark ? "x \(Int(x)) row \(row) rgb [\(rgb.red), \(rgb.green), \(rgb.blue)]" : nil
            }
        }
    }

    func testSettingsTopicDrawsWallpaperThroughThePush() throws {
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_BACKDROP_FIXTURE": "1"], readyIdentifier: "nav.profile")
        openSection("settings", title: "Settings", in: app)
        let list = element("settings.list", in: app)
        XCTAssertTrue(list.waitForExistence(timeout: 15), "Settings did not appear")
        sleep(2)
        let target = element("settings.topic.guests", in: app)
        for _ in 0..<8 where !(target.exists && target.isHittable) { list.swipeUp(velocity: .slow) }
        XCTAssertTrue(target.isHittable, "Guest Controls never came into view")
        let window = app.windows.firstMatch.frame
        target.tap()
        var frames = 0
        var dark: [String] = []
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            guard let capture = RenderedContrast.Capture.screen() else { break }
            frames += 1
            let found = darkSamples(capture, window: window)
            if !found.isEmpty { dark.append("frame \(frames): \(found.joined(separator: "; "))") }
        }
        XCTAssertTrue(app.buttons["BackButton"].waitForExistence(timeout: 15), "Guest Controls did not open")
        XCTAssertGreaterThan(frames, 1, "no frames captured")
        XCTAssertTrue(dark.isEmpty, "dark frames during the push (\(layout), \(frames) frames): \(dark.joined(separator: " | "))")
    }
}
