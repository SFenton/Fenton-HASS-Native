import XCTest

/// The location permission screen in the debug gallery (`FENTON_GALLERY=location`): the pre-alert steps (one
/// Continue, no Close), the status stages (Close, Open Settings), names, values, targets, and the accessibility
/// audit at the default and AX5 text sizes for every stage, with screenshots, on iPhone, iPhone Duo and iPad
/// (`.agents/pages/settings/location.md`).
@MainActor
final class LocationJourneyTests: JourneyTestCase {
    private func launch(_ stage: String, arguments: [String] = []) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "location"
        app.launchEnvironment["FENTON_GALLERY_LOCATION"] = stage
        app.launchArguments += arguments
        app.launch()
        XCTAssertTrue(app.staticTexts["location.title"].waitForExistence(timeout: 15), "The location screen did not open")
        return app
    }

    private func lastAction(_ app: XCUIApplication) -> String {
        app.staticTexts["gallery.lastCall"].firstMatch.label
    }

    private func status(_ app: XCUIApplication) -> String {
        element("location.status", in: app).value as? String ?? ""
    }

    /// The first screen asks with one Continue and offers no other way out (HIG Privacy, Pre-alert screens).
    func testFirstStepIsAPreAlertScreen() {
        let app = launch("not-determined")
        XCTAssertEqual(app.staticTexts["location.title"].label, "Know When You're Home")
        let statusRow = element("location.status", in: app)
        XCTAssertEqual(statusRow.label, "Location Access")
        XCTAssertEqual(status(app), "Not Set")
        let primary = app.buttons["location.primary"]
        XCTAssertEqual(primary.label, "Continue")
        assertTarget(primary)
        XCTAssertFalse(app.buttons["location.close"].exists, "A pre-alert screen has no Close")
        for symbol in ["figure.walk.arrival", "lock.shield", "battery.75percent"] {
            let point = element("location.point.\(symbol)", in: app)
            XCTAssertTrue(point.exists, symbol)
            XCTAssertFalse(point.label.isEmpty, "\(symbol) reads its title and detail")
        }
        XCTAssertTrue(point(app, "figure.walk.arrival").label.hasPrefix("Arrivals and Departures"))
    }

    private func point(_ app: XCUIApplication, _ symbol: String) -> XCUIElement {
        element("location.point.\(symbol)", in: app)
    }

    /// Continue leads through While Using to Always; the finished screen gains Close and loses the button.
    func testContinueWalksToAlways() {
        let app = launch("not-determined")
        app.buttons["location.primary"].tap()
        XCTAssertEqual(lastAction(app), "Last action: request not-determined")
        XCTAssertTrue(app.staticTexts["Notice When You Leave"].waitForExistence(timeout: 5))
        XCTAssertEqual(status(app), "While Using the App")
        XCTAssertFalse(app.buttons["location.close"].exists)

        app.buttons["location.primary"].tap()
        XCTAssertEqual(lastAction(app), "Last action: request when-in-use")
        XCTAssertTrue(app.staticTexts["Home and Away Are On"].waitForExistence(timeout: 5))
        XCTAssertEqual(status(app), "Always")
        XCTAssertFalse(app.buttons["location.primary"].exists, "Nothing left to do")
        let close = app.buttons["location.close"]
        XCTAssertTrue(close.exists)
        XCTAssertEqual(close.label, "Close")
        close.tap()
        XCTAssertEqual(lastAction(app), "Last action: close")
    }

    /// Off and Approximate send the person to Settings, and say why.
    func testOffAndApproximateOpenSettings() {
        for (stage, title, value) in [("denied", "Location Is Off", "Off"),
                                      ("reduced-accuracy", "Precise Location Is Off", "Always, Approximate")] {
            let app = launch(stage)
            XCTAssertEqual(app.staticTexts["location.title"].label, title)
            XCTAssertEqual(status(app), value)
            let primary = app.buttons["location.primary"]
            XCTAssertEqual(primary.label, "Open Settings")
            assertTarget(primary)
            primary.tap()
            XCTAssertEqual(lastAction(app), "Last action: open settings")
            XCTAssertTrue(app.buttons["location.close"].exists)
            app.terminate()
        }
    }

    /// Every stage passes the audit at the default size and grows at AX5, with a screenshot of each.
    func testEveryStagePassesAccessibilityAudit() throws {
        for stage in ["not-determined", "when-in-use", "always", "denied", "reduced-accuracy"] {
            let app = launch(stage, arguments: [])
            keepScreenshot(app, "location-\(stage)-\(layout)")
            try FentonHomeApp.audit(app) { self.launch(stage, arguments: FentonHomeApp.ax5) }
            let large = launch(stage, arguments: FentonHomeApp.ax5)
            keepScreenshot(large, "location-\(stage)-ax5-\(layout)")
            let primary = large.buttons["location.primary"]
            if primary.exists {
                // Reachable at AX5: the action ends the scrolling content.
                for _ in 0..<12 where !primary.isHittable { large.swipeUp() }
                XCTAssertTrue(primary.isHittable, "\(stage): the action is out of reach at AX5")
            }
            large.terminate()
        }
    }
}
