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

    /// While Using after iOS showed its one Always alert: Settings instead of Continue, and Close is back.
    func testWhileUsingAfterTheAlwaysAlertOffersSettings() {
        let app = launch("when-in-use-asked")
        XCTAssertEqual(app.staticTexts["location.title"].label, "Notice When You Leave")
        XCTAssertEqual(status(app), "While Using the App")
        let primary = app.buttons["location.primary"]
        XCTAssertEqual(primary.label, "Open Settings")
        assertTarget(primary)
        let close = app.buttons["location.close"]
        // The system's toolbar Close (`SheetCloseItem`); the bar sizes its hit region, as on every sheet.
        XCTAssertTrue(close.exists, "No longer a pre-alert screen")
        primary.tap()
        XCTAssertEqual(lastAction(app), "Last action: open settings")
    }

    /// Every stage passes the audit at the default size and grows at AX5, with a screenshot of each.
    func testEveryStagePassesAccessibilityAudit() throws {
        for stage in ["not-determined", "when-in-use", "when-in-use-asked", "always", "denied", "reduced-accuracy"] {
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

/// Shadow-mode location after a real sign-in (`.agents/platforms/apple/location.md`): phones offer the permission
/// screen once and walk the real system alerts to Always; iPad never shows it ("This phone"). The launch never
/// registers (a test token keeps `mobile_app` registration off), so nothing reaches Home Assistant.
@MainActor
final class LocationShadowJourneyTests: JourneyTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    private func launchSignedIn() throws -> XCUIApplication {
        XCUIApplication().resetAuthorizationStatus(for: .location)
        let ready = FentonHomeApp.family == .iPad ? nil : "location.title"
        return try FentonHomeApp.launchSignedIn(environment: ["FENTON_LOCATION": "1"], readyIdentifier: ready)
    }

    /// Taps the system alert button whose label contains `text`.
    private func answerAlert(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = springboard.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 15), "No system alert offering \(text)", file: file, line: line)
        button.tap()
    }

    func testPhonesOfferLocationAfterSignInAndIPadNever() throws {
        let app = try launchSignedIn()
        guard FentonHomeApp.family != .iPad else {
            XCTAssertTrue(app.buttons["home.chip.lights"].waitForExistence(timeout: 30))
            // Long enough for the profile load that offers the screen on a phone.
            XCTAssertFalse(app.staticTexts["location.title"].waitForExistence(timeout: 8), "iPad never asks for location")
            keepScreenshot(app, "location-shadow-ipad-\(layout)")
            return
        }
        XCTAssertEqual(app.staticTexts["location.title"].label, "Know When You're Home")
        XCTAssertFalse(app.buttons["location.close"].exists, "A pre-alert screen has no Close")
        keepScreenshot(app, "location-shadow-1-ask-\(layout)")

        app.buttons["location.primary"].tap()
        answerAlert("While Using")
        XCTAssertTrue(app.staticTexts["Notice When You Leave"].waitForExistence(timeout: 10))
        XCTAssertEqual(element("location.status", in: app).value as? String, "While Using the App")
        keepScreenshot(app, "location-shadow-2-while-using-\(layout)")

        app.buttons["location.primary"].tap()
        answerAlert("Always")
        XCTAssertTrue(app.staticTexts["Home and Away Are On"].waitForExistence(timeout: 10))
        keepScreenshot(app, "location-shadow-3-always-\(layout)")
        let close = app.buttons["location.close"]
        XCTAssertTrue(close.exists)
        close.tap()
        XCTAssertTrue(app.buttons["home.chip.lights"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["location.title"].exists)
        keepScreenshot(app, "location-shadow-4-home-\(layout)")
    }
}

/// The Account sheet's Location section after a real sign-in (`.agents/pages/settings/location.md`, Entry points):
/// on phones Share Location shows the permission and opens the permission screen, and Report to Home Assistant
/// starts off, arms, warns while access is off, and stays armed after a relaunch; iPad has no Location section. The
/// launch never registers (a test token and the simulator keep `mobile_app` registration off), so arming sends
/// nothing to Home Assistant.
@MainActor
final class LocationAccountJourneyTests: JourneyTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    /// Signs in with location on and the toggle reset off; phones wait for the after-sign-in offer.
    private func launchSignedIn(arguments: [String] = [], offer: Bool) throws -> XCUIApplication {
        try FentonHomeApp.launchSignedIn(arguments: arguments,
                                         environment: ["FENTON_LOCATION": "1", "FENTON_LOCATION_REPORT": "0"],
                                         readyIdentifier: offer ? "location.title" : nil)
    }

    /// Signs in again (location already declined, so no offer) and opens the Account sheet.
    private func relaunchToAccount(arguments: [String] = []) throws -> XCUIApplication {
        let app = try launchSignedIn(arguments: arguments, offer: false)
        app.openAccountSheet()
        return app
    }

    func testShareLocationAndTheReportToggleOnPhonesOnly() throws {
        XCUIApplication().resetAuthorizationStatus(for: .location)
        guard FentonHomeApp.family != .iPad else {
            let app = try relaunchToAccount()
            XCTAssertTrue(app.buttons["account.settings"].exists)
            XCTAssertFalse(app.buttons["account.location"].exists, "iPad has no Share Location row")
            XCTAssertFalse(app.switches["account.location.report"].exists, "iPad has no Report toggle")
            keepScreenshot(app, "location-account-ipad-\(layout)")
            return
        }

        // The after-sign-in offer still comes first in the four-tab shell; decline it.
        var app = try launchSignedIn(offer: true)
        keepScreenshot(app, "location-account-0-offer-\(layout)")
        app.buttons["location.primary"].tap()
        let decline = springboard.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Don'")).firstMatch
        XCTAssertTrue(decline.waitForExistence(timeout: 15), "No system location alert")
        decline.tap()
        XCTAssertTrue(app.staticTexts["Location Is Off"].waitForExistence(timeout: 10))
        app.buttons["location.close"].tap()

        app.openAccountSheet()
        let row = app.buttons["account.location"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "No Share Location row")
        XCTAssertEqual(row.label, "Share Location")
        XCTAssertEqual(row.value as? String, "Off")
        XCTAssertGreaterThanOrEqual(row.frame.height, 44)
        let toggle = app.switches["account.location.report"]
        XCTAssertTrue(toggle.exists, "No Report toggle")
        XCTAssertEqual(toggle.value as? String, "0", "Reporting is off by default")
        XCTAssertGreaterThanOrEqual(toggle.frame.height, 44)
        let warning = app.descendants(matching: .any)["account.location.warning"]
        XCTAssertFalse(warning.exists, "No warning while off")
        keepScreenshot(app, "location-account-1-off-\(layout)")

        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertTrue(warning.waitForExistence(timeout: 5), "Armed with access off warns")
        XCTAssertTrue(warning.label.hasPrefix("Warning: Location access is off"), warning.label)
        keepScreenshot(app, "location-account-2-armed-\(layout)")
        try FentonHomeApp.audit(app) { try self.relaunchToAccount(arguments: FentonHomeApp.ax5) }
        let large = try relaunchToAccount(arguments: FentonHomeApp.ax5)
        keepScreenshot(large, "location-account-2-armed-ax5-\(layout)")
        large.terminate()

        // Armed survives a relaunch without the debug override.
        app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_LOCATION": "1"])
        app.openAccountSheet()
        let armed = app.switches["account.location.report"]
        XCTAssertTrue(armed.waitForExistence(timeout: 5))
        XCTAssertEqual(armed.value as? String, "1", "The toggle persists per install")

        // Share Location opens the permission screen at its current stage; Close comes back to Account.
        app.buttons["account.location"].tap()
        XCTAssertTrue(app.staticTexts["location.title"].waitForExistence(timeout: 5), "Share Location did not open")
        XCTAssertEqual(app.staticTexts["location.title"].label, "Location Is Off")
        keepScreenshot(app, "location-account-3-screen-\(layout)")
        app.buttons["location.close"].tap()
        XCTAssertTrue(app.buttons["account.location"].waitForExistence(timeout: 5))

        armed.switches.firstMatch.tap()
        XCTAssertEqual(armed.value as? String, "0")
        XCTAssertFalse(app.descendants(matching: .any)["account.location.warning"].waitForExistence(timeout: 2))
    }
}
