import XCTest

/// Root navigation and on-demand split (`.agents/design/apple/split-view.md`, `ipados.md`):
/// tab bar in compact width, overlay flyout in regular width, Settings beside its list only in landscape.
@MainActor
final class NavigationJourneyTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    /// Only the iPad journeys rotate (the Duo's pose comes from Device Hub). Setting the orientation on
    /// an unfolded Duo hung the runner waiting for SpringBoard, and the restart rebooted it folded.
    override func tearDown() {
        MainActor.assumeIsolated {
            if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
        }
    }

    // MARK: - Helpers

    /// The window uses the flyout (regular width) rather than the tab bar. Compact windows on iOS 26 also have
    /// the menu button (Settings left the bar for it), so the test is the tab bar itself.
    private func usesFlyout(_ app: XCUIApplication) -> Bool {
        _ = app.buttons["nav.open"].waitForExistence(timeout: 3)
        let home = tab("Home", in: app)
        return !(home.exists && home.isHittable)
    }

    /// A tab item: in the tab bar, or on the folded iPhone Duo in the vertical bar, which XCUITest
    /// reports as a toolbar.
    private func tab(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let item = app.tabBars.buttons[title]
        return item.exists ? item : app.toolbars.buttons[title]
    }

    /// Goes back one page: the system Back button wherever the bar puts it (the folded iPhone Duo moves
    /// bar items into its vertical bar), else the system leading-edge back swipe.
    private func goBack(in app: XCUIApplication) {
        let back = app.buttons["BackButton"]
        if back.exists, back.isHittable {
            back.tap()
            return
        }
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: window.frame.height / 2))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: window.frame.width * 0.7, dy: 0)))
    }

    /// The flyout panel (SwiftUI puts its identifier on the panel's scroll view).
    private func flyout(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["nav.flyout"]
    }

    private func isLandscape(_ app: XCUIApplication) -> Bool {
        let frame = app.windows.firstMatch.frame
        return frame.width > frame.height
    }

    /// Goes to a section through whichever navigation the window shows.
    private func open(_ section: String, title: String, in app: XCUIApplication) {
        let item = tab(title, in: app)
        if !(item.exists && item.isHittable) {
            app.buttons["nav.open"].tap()
            XCTAssertTrue(flyout(app).waitForExistence(timeout: 3), "Flyout did not open")
            app.buttons["nav.\(section)"].tap()
            XCTAssertTrue(flyout(app).waitForNonExistence(timeout: 3), "Flyout stayed open")
        } else {
            tab(title, in: app).tap()
        }
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "\(title) did not appear")
    }

    // MARK: - Compact width

    /// iPhone (and folded Duo) navigate with the tab bar: the primary four and the trailing Quick Links tab, with
    /// Settings in the menu (iOS 26); a Settings topic pushes full screen with Back.
    func testCompactWidthUsesTabBarAndPushes() throws {
        let app = try FentonHomeApp.launchSignedIn()
        guard !usesFlyout(app) else { throw XCTSkip("Regular-width window") }
        for title in ["Security", "Climate", "Chores", "Home", "Quick Links"] {
            XCTAssertTrue(tab(title, in: app).exists, "\(title) tab missing")
        }
        XCTAssertFalse(tab("Settings", in: app).isHittable, "Settings is in the menu, not the bar")
        XCTAssertTrue(app.buttons["nav.open"].isHittable, "No menu button on the section root")
        XCTAssertTrue(app.buttons["nav.profile"].isHittable, "No profile button on the section root")
        // Quick Links is its own page and returns to Home unchanged.
        tab("Quick Links", in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["quickLinks.rooms"].waitForExistence(timeout: 5), "Quick Links did not open")
        keepScreenshot(app, "quick-links-tab")
        tab("Home", in: app).tap()
        XCTAssertTrue(app.buttons["home.chip.lights"].waitForExistence(timeout: 5))
        open("settings", title: "Settings", in: app)
        app.buttons["settings.topic.specialDeviceModes"].tap()
        XCTAssertTrue(app.navigationBars["Special Device Modes"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["split.close"].exists, "Compact width split")
        goBack(in: app)
        XCTAssertTrue(app.buttons["settings.topic.specialDeviceModes"].waitForExistence(timeout: 5))
    }

    /// The Settings list audits clean in compact width, AX5 included.
    func testCompactSettingsPassesAccessibilityAudit() throws {
        var app = try FentonHomeApp.launchSignedIn()
        guard !usesFlyout(app) else { throw XCTSkip("Regular-width window") }
        open("settings", title: "Settings", in: app)
        sleep(1)
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            self.open("settings", title: "Settings", in: large)
            sleep(1)
            return large
        }
        // The pushed topic page too.
        app = try FentonHomeApp.launchSignedIn()
        open("settings", title: "Settings", in: app)
        app.buttons["settings.topic.specialDeviceModes"].tap()
        XCTAssertTrue(app.navigationBars["Special Device Modes"].waitForExistence(timeout: 5))
        sleep(1)
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            self.open("settings", title: "Settings", in: large)
            let modes = large.buttons["settings.topic.specialDeviceModes"]
            for _ in 0..<8 where !(modes.exists && modes.isHittable) { large.collectionViews.firstMatch.swipeUp() }
            modes.tap()
            XCTAssertTrue(large.navigationBars["Special Device Modes"].waitForExistence(timeout: 5))
            sleep(1)
            return large
        }
        app = try FentonHomeApp.launchSignedIn()
        open("settings", title: "Settings", in: app)
        app.buttons["settings.topic.specialDeviceModes"].tap()
        XCTAssertTrue(app.navigationBars["Special Device Modes"].waitForExistence(timeout: 5))
        goBack(in: app)
        XCTAssertTrue(app.buttons["settings.topic.specialDeviceModes"].waitForExistence(timeout: 5))
    }

    // MARK: - Regular width

    /// iPad and unfolded Duo hide the tab bar and navigate with the overlay flyout.
    func testFlyoutOpensSelectsAndDismisses() throws {
        let app = try FentonHomeApp.launchSignedIn()
        guard usesFlyout(app) else { throw XCTSkip("Compact window") }
        XCTAssertFalse(tab("Security", in: app).isHittable, "Tab bar visible beside the flyout")
        app.buttons["nav.open"].tap()
        let flyout = flyout(app)
        XCTAssertTrue(flyout.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["home.chip.lights"].exists, "Content under the scrim still reachable by VoiceOver")
        for section in ["home", "security", "climate", "chores", "settings"] {
            let row = app.buttons["nav.\(section)"]
            XCTAssertTrue(row.isHittable, "\(section) row unreachable")
            XCTAssertGreaterThanOrEqual(row.frame.height, 44, "\(section) row under 44 pt")
        }
        XCTAssertTrue(app.buttons["nav.home"].isSelected, "Current section not marked selected")
        // Settings sits below the primary four.
        XCTAssertGreaterThan(app.buttons["nav.settings"].frame.minY, app.buttons["nav.chores"].frame.maxY)
        // The scrim closes it without navigating.
        app.buttons["nav.flyout.scrim"].tap()
        XCTAssertTrue(flyout.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["home.chip.lights"].exists)
        open("security", title: "Security", in: app)
        open("home", title: "Home", in: app)
    }

    /// A drag from the leading edge opens the flyout, and the edge does not swallow taps: Open Navigation
    /// works when tapped inside the edge-swipe width.
    func testEdgeSwipeOpensFlyoutWithoutBlockingEdgeTaps() throws {
        let app = try FentonHomeApp.launchSignedIn()
        guard usesFlyout(app) else { throw XCTSkip("Compact window") }
        // Start on a control at the leading edge (the first camera tile's row): the swipe must open only
        // the flyout, never the control under it (the landscape Duo opened the camera too).
        let window = app.windows.firstMatch
        let camera = app.buttons["home.camera.front_door"]
        let y = camera.exists && camera.frame.minX < 40 ? camera.frame.midY : window.frame.height / 2
        let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: y))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 200, dy: 0)))
        XCTAssertTrue(flyout(app).waitForExistence(timeout: 3), "Edge swipe did not open the flyout")
        XCTAssertFalse(app.navigationBars.buttons["Close"].exists, "The edge swipe also activated the control under it")
        app.buttons["nav.flyout.scrim"].tap()
        XCTAssertTrue(flyout(app).waitForNonExistence(timeout: 3))

        // Taps inside the leading 18 pt still reach the controls there.
        var tappedAtEdge = 0
        let open = app.buttons["nav.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 3))
        // On the unfolded Duo the system moves Open Navigation into its trailing vertical bar.
        if open.frame.minX < 18 {
            open.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 18 - open.frame.minX - 1, dy: open.frame.height / 2)).tap()
            XCTAssertTrue(flyout(app).waitForExistence(timeout: 3), "A tap on Open Navigation inside the leading edge was swallowed")
            app.buttons["nav.flyout.scrim"].tap()
            XCTAssertTrue(flyout(app).waitForNonExistence(timeout: 3))
            tappedAtEdge += 1
        }
        if camera.exists, camera.frame.minX < 18 {
            camera.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 18 - camera.frame.minX - 1, dy: camera.frame.height / 2)).tap()
            let done = app.navigationBars.buttons["Close"]
            XCTAssertTrue(done.waitForExistence(timeout: 5), "A tap on a camera tile inside the leading edge was swallowed")
            done.tap()
            tappedAtEdge += 1
        }
        XCTAssertGreaterThan(tappedAtEdge, 0, "No control inside the leading edge to tap")
    }

    /// The open flyout audits clean (names, roles, contrast, targets, Dynamic Type).
    func testFlyoutPassesAccessibilityAudit() throws {
        let app = try FentonHomeApp.launchSignedIn()
        guard usesFlyout(app) else { throw XCTSkip("Compact window") }
        app.buttons["nav.open"].tap()
        XCTAssertTrue(flyout(app).waitForExistence(timeout: 3))
        sleep(1)
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            large.buttons["nav.open"].tap()
            XCTAssertTrue(self.flyout(large).waitForExistence(timeout: 3))
            sleep(1)
            return large
        }
    }

    /// Landscape regular width: Settings keeps its list on the leading half and opens topics beside it,
    /// with a placeholder while nothing is selected. Portrait pushes the same topic full screen.
    func testSettingsSplitsInLandscapeAndPushesInPortrait() throws {
        var app = try FentonHomeApp.launchSignedIn()
        guard usesFlyout(app) else { throw XCTSkip("Compact window") }
        if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .landscapeLeft; sleep(1) }
        guard isLandscape(app) else { throw XCTSkip("Set the iPhone Duo to unfolded landscape in Device Hub") }
        open("settings", title: "Settings", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["settings.placeholder"].waitForExistence(timeout: 3), "No placeholder pane")

        let topic = app.buttons["settings.topic.guests"]
        topic.tap()
        XCTAssertTrue(app.buttons["split.close"].waitForExistence(timeout: 3), "Topic did not open beside the list")
        XCTAssertTrue(topic.isHittable, "List hidden while the topic is open")
        XCTAssertTrue(topic.isSelected, "Open topic not marked selected")
        let window = app.windows.firstMatch.frame
        XCTAssertLessThan(topic.frame.maxX, window.midX + 1, "List pane wider than half")
        // The trailing pane starts at the midpoint (iPad: the 1 pt band) or just after the hinge (Duo).
        let trailing = app.descendants(matching: .any)["split.trailing"].frame
        print("split: window \(window), trailing \(trailing)")
        XCTAssertEqual(trailing.maxX, window.maxX, accuracy: 1, "Trailing pane does not reach the window edge")
        if FentonHomeApp.family == .iPad {
            XCTAssertEqual(trailing.minX, window.midX + 0.5, accuracy: 0.5, "Divider is not at the midpoint")
        } else {
            // Duo: on the hinge in book pose; flat, at the midpoint of the space beside the system's
            // vertical bar (owner #361), e.g. 434 pt of 951 pt with an 83 pt bar. Both sit within a
            // hinge's width of the window centre; exact pane widths are unit-tested (SplitGeometryTests,
            // OnDemandSplitHostedTests).
            XCTAssertEqual(trailing.minX, window.midX, accuracy: window.width * 0.06, "Divider far from the fold")
        }
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            self.open("settings", title: "Settings", in: large)
            // At AX5 the row starts below the fold.
            let guests = large.buttons["settings.topic.guests"]
            for _ in 0..<8 where !(guests.exists && guests.isHittable) {
                large.buttons["settings.topic.admin"].exists
                    ? large.buttons["settings.topic.admin"].swipeUp() : large.collectionViews.firstMatch.swipeUp()
            }
            guests.tap()
            XCTAssertTrue(large.buttons["split.close"].waitForExistence(timeout: 3))
            // Back to the top, so the list shows the same rows the audited page did.
            let first = large.buttons["settings.topic.admin"]
            for _ in 0..<8 where !(first.exists && first.isHittable) { large.collectionViews.firstMatch.swipeDown() }
            // All the way up: a partly scrolled list collapses the large title to the inline one.
            for _ in 0..<2 { large.collectionViews.firstMatch.swipeDown() }
            sleep(1)
            sleep(1)
            return large
        }
        // The AX5 page replaced the running app; continue at the default size.
        app = try FentonHomeApp.launchSignedIn()
        open("settings", title: "Settings", in: app)
        app.buttons["settings.topic.guests"].tap()
        XCTAssertTrue(app.buttons["split.close"].waitForExistence(timeout: 3))

        app.buttons["settings.topic.specialDeviceModes"].tap()
        XCTAssertTrue(app.navigationBars["Special Device Modes"].waitForExistence(timeout: 3), "Selecting another topic did not replace the pane")
        app.buttons["split.close"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.placeholder"].waitForExistence(timeout: 3))

        guard FentonHomeApp.family == .iPad else { return }
        // Rotating moves the open topic between the pane and a push, keeping it.
        app.buttons["settings.topic.machE"].tap()
        XCTAssertTrue(app.buttons["split.close"].waitForExistence(timeout: 3))
        XCUIDevice.shared.orientation = .portrait
        sleep(1)
        XCTAssertTrue(app.navigationBars["Mach-E"].waitForExistence(timeout: 3), "Topic lost on rotation")
        XCTAssertFalse(app.buttons["split.close"].exists, "Portrait split")
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        XCTAssertTrue(app.buttons["split.close"].waitForExistence(timeout: 3), "Topic did not return to the pane")
    }

    /// iPad portrait (and unfolded Duo portrait) is single page: a topic pushes with Back.
    func testRegularPortraitNeverSplits() throws {
        let app = try FentonHomeApp.launchSignedIn()
        guard usesFlyout(app), !isLandscape(app) else { throw XCTSkip("Needs a regular-width portrait window") }
        open("settings", title: "Settings", in: app)
        XCTAssertFalse(app.descendants(matching: .any)["settings.placeholder"].exists, "Portrait placeholder pane")
        app.buttons["settings.topic.admin"].tap()
        XCTAssertTrue(app.navigationBars["Admin"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["split.close"].exists)
    }

    // MARK: - Screenshots

    /// Keeps `home-*`, `nav-*` and `settings-*` screenshots of the navigation and Settings split in each orientation for review.
    func testCaptureNavigationScreens() throws {
        let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]
        for orientation in orientations {
            if orientation != .unknown { XCUIDevice.shared.orientation = orientation }
            let suffix = orientation == .landscapeLeft ? "landscape" : orientation == .portrait ? "portrait" : "current"
            let app = try FentonHomeApp.launchSignedIn()
            // Set again after launch: set only before it, iPad captures came out portrait.
            if orientation != .unknown { XCUIDevice.shared.orientation = orientation }
            sleep(1)
            keep(app, "home-\(suffix)")
            if usesFlyout(app) {
                app.buttons["nav.open"].tap()
                XCTAssertTrue(flyout(app).waitForExistence(timeout: 3))
                sleep(1)
                keep(app, "nav-flyout-\(suffix)")
                app.buttons["nav.settings"].tap()
            } else {
                keep(app, "nav-tabbar-\(suffix)")
                open("settings", title: "Settings", in: app)
            }
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
            // Show the end of the list: it closes with the Home Assistant row (below the fold on
            // phones and in the split's leading pane).
            let list = app.collectionViews.firstMatch
            let homeAssistant = app.buttons["settings.homeAssistant"]
            for _ in 0..<6 where !(homeAssistant.exists && homeAssistant.isHittable) { list.swipeUp() }
            sleep(1)
            keep(app, "settings-\(suffix)")
            let guests = app.buttons["settings.topic.guests"]
            for _ in 0..<6 where !(guests.exists && guests.isHittable) { list.swipeDown() }
            guests.tap()
            sleep(1)
            keep(app, "settings-topic-\(suffix)")
            // Close it: the open topic is scene-restored on the next launch, which would hide the
            // placeholder in the next orientation's capture.
            if app.buttons["split.close"].exists { app.buttons["split.close"].tap() } else { goBack(in: app) }
            sleep(1)
        }
        if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
    }

    private func keep(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let folder = ProcessInfo.processInfo.environment["FENTON_CAPTURE_DIR"], !folder.isEmpty else { return }
        let ready = URL(fileURLWithPath: folder).appendingPathComponent("\(name).ready")
        let done = URL(fileURLWithPath: folder).appendingPathComponent("\(name).done")
        FileManager.default.createFile(atPath: ready.path, contents: nil)
        // Generous: under load from other lanes' simulators a host screenshot took over 30 s.
        let deadline = Date().addingTimeInterval(120)
        while !FileManager.default.fileExists(atPath: done.path), Date() < deadline { usleep(200_000) }
    }
}
