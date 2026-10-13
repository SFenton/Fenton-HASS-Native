import XCTest

/// Shared chrome on every device (`.agents/patterns/header-edge-fade.md`, `page-backdrop.md`, `modal-sheet.md`,
/// `.agents/design/apple/iphone.md`): section roots carry the menu (where Settings is not a tab), Quick Links and
/// the profile button; modals close with the circle X; screenshots of each page and modal for design review.
@MainActor
final class ChromeJourneyTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private var suffix: String {
        switch FentonHomeApp.family {
        case .iPhone: "iphone"
        case .iPhoneDuo: "duo"
        case .iPad: "ipad"
        }
    }

    /// A tab in the tab bar, or on the folded Duo in its vertical bar.
    private func tab(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let item = app.tabBars.buttons[title]
        return item.exists ? item : app.toolbars.buttons[title]
    }

    /// Goes to a section through its tab when the bar shows it, else through the menu.
    private func open(_ section: String, title: String, in app: XCUIApplication) {
        let item = tab(title, in: app)
        if item.exists, item.isHittable {
            item.tap()
        } else {
            app.buttons["nav.open"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["nav.flyout"].waitForExistence(timeout: 3), "Menu did not open")
            app.buttons["nav.\(section)"].tap()
        }
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "\(title) did not appear")
    }

    /// Closes the front modal with its circle-X Close (in the navigation bar, or the folded Duo's vertical bar).
    private func closeModal(_ app: XCUIApplication) {
        let inBar = app.navigationBars.buttons["Close"].firstMatch
        // The folded Duo moves bar items into its vertical bar, which XCUITest reports outside the navigation bar.
        let anywhere = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Close' OR identifier == 'sheet.close'")).firstMatch
        let close = inBar.waitForExistence(timeout: 3) ? inBar : anywhere
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Modal has no Close")
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5), "Modal did not close")
    }

    /// Every section root has the profile button, and the menu wherever Settings is not a visible tab.
    func testSectionRootsCarryShellItems() throws {
        let app = try FentonHomeApp.launchSignedIn()
        XCTAssertTrue(app.buttons["nav.profile"].waitForExistence(timeout: 5), "No profile button")
        XCTAssertGreaterThanOrEqual(app.buttons["nav.profile"].frame.height, 44, "Profile under 44 pt")
        let settingsTab = tab("Settings", in: app)
        if !(settingsTab.exists && settingsTab.isHittable) {
            XCTAssertTrue(app.buttons["nav.open"].isHittable, "Settings unreachable: no tab and no menu")
        }
        let quickLinksTab = tab("Quick Links", in: app)
        XCTAssertTrue(quickLinksTab.exists || app.buttons["quickLinks.open"].exists, "Quick Links unreachable")
    }

    /// Pages, the menu, Quick Links and the main modals on this device, kept for design review.
    func testCaptureChrome() throws {
        let app = try FentonHomeApp.launchSignedIn()
        sleep(2)
        keepScreenshot(app, "chrome-home-top-\(suffix)")
        // Scrolled a little: content fades out under the header, with no band behind it.
        let scroll = app.scrollViews["home.scroll"].firstMatch
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        sleep(1)
        keepScreenshot(app, "chrome-home-scrolled-\(suffix)")
        scroll.swipeDown()

        app.buttons["home.chip.security"].tap()
        sleep(2)
        keepScreenshot(app, "chrome-modal-security-\(suffix)")
        closeModal(app)

        let camera = app.buttons["home.camera.front_door"]
        if camera.waitForExistence(timeout: 5) {
            camera.tap()
            sleep(2)
            keepScreenshot(app, "chrome-modal-camera-\(suffix)")
            closeModal(app)
        }

        app.buttons["nav.profile"].tap()
        XCTAssertTrue(app.buttons["haSettings.done"].waitForExistence(timeout: 5), "Profile did not open settings")
        keepScreenshot(app, "chrome-modal-profile-\(suffix)")
        app.buttons["haSettings.done"].tap()

        let quickLinks = tab("Quick Links", in: app)
        if quickLinks.exists, quickLinks.isHittable {
            quickLinks.tap()
        } else {
            app.buttons["quickLinks.open"].tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["quickLinks.rooms"].waitForExistence(timeout: 5))
        sleep(1)
        keepScreenshot(app, "chrome-quick-links-\(suffix)")
        if app.buttons["quickLinks.close"].exists { closeModal(app) }

        for (section, title) in [("security", "Security"), ("climate", "Climate"), ("chores", "Chores")] {
            open(section, title: title, in: app)
            sleep(2)
            keepScreenshot(app, "chrome-\(section)-\(suffix)")
        }
        if app.buttons["nav.open"].exists {
            app.buttons["nav.open"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["nav.flyout"].waitForExistence(timeout: 3))
            sleep(1)
            keepScreenshot(app, "chrome-menu-\(suffix)")
            app.buttons["nav.settings"].tap()
        } else {
            open("settings", title: "Settings", in: app)
        }
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        sleep(1)
        keepScreenshot(app, "chrome-settings-\(suffix)")
    }

    /// Home with the new toolbar items and pill chips, and the Quick Links page, audit clean (AX5 included).
    func testChromePassesAccessibilityAudit() throws {
        let app = try FentonHomeApp.launchSignedIn()
        sleep(2)
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            sleep(2)
            return large
        }
        let relaunched = try FentonHomeApp.launchSignedIn()
        let quickLinks = tab("Quick Links", in: relaunched)
        guard quickLinks.exists, quickLinks.isHittable else { return }
        quickLinks.tap()
        XCTAssertTrue(relaunched.descendants(matching: .any)["quickLinks.rooms"].waitForExistence(timeout: 5))
        sleep(1)
        try FentonHomeApp.audit(relaunched) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            self.tab("Quick Links", in: large).tap()
            XCTAssertTrue(large.descendants(matching: .any)["quickLinks.rooms"].waitForExistence(timeout: 5))
            sleep(1)
            return large
        }
    }
}
