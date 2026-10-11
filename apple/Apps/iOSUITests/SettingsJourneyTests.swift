import XCTest

/// Settings tab → Home Assistant settings modal: audit, account details, the signed-in web pages
/// and Sign Out, on every device family.
@MainActor
final class SettingsJourneyTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// Opens the modal from a signed-in launch.
    private func openSettings(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["Settings"].exists ? app.tabBars.buttons["Settings"] : app.buttons["tab.settings"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        let row = app.buttons["settings.homeAssistant"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(row.frame.height, 43)
        row.tap()
        XCTAssertTrue(app.buttons["haSettings.done"].waitForExistence(timeout: 5))
        sleep(1) // Let the full-screen modal finish presenting.
    }

    /// A `LabeledContent` row by identifier once its label or value shows `text` (the row merges both).
    private func row(_ app: XCUIApplication, _ identifier: String, showing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier)
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)).firstMatch
    }

    /// The sign-out confirmation's destructive button (the system nests a duplicate inside it).
    private func confirmButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: "haSettings.signOut.confirm").firstMatch
    }

    /// Cancels the confirmation: its Cancel button where the system draws one (iPad action sheets
    /// drop it, and iOS 27 anchors it as a popover that cancels on an outside tap).
    private func cancelSignOut(_ app: XCUIApplication) {
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists && cancel.isHittable {
            cancel.tap()
        } else {
            let dismiss = app.otherElements["PopoverDismissRegion"].firstMatch
            if dismiss.exists { dismiss.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap() }
        }
        XCTAssertTrue(confirmButton(app).waitForNonExistence(timeout: 5), "Sign-out confirmation did not close")
    }

    func testSettingsTabPassesAccessibilityAudit() throws {
        let app = try FentonHomeApp.launchSignedIn()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["settings.homeAssistant"].waitForExistence(timeout: 5))
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            large.tabBars.buttons["Settings"].tap()
            XCTAssertTrue(large.buttons["settings.homeAssistant"].waitForExistence(timeout: 5))
            return large
        }
    }

    func testModalShowsServerAccountAndPassesAudit() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openSettings(app)
        XCTAssertTrue(row(app, "haSettings.status", showing: "Connected").waitForExistence(timeout: 15), "Connection row not live")
        XCTAssertTrue(app.descendants(matching: .any)["haSettings.role"].waitForExistence(timeout: 10), "Account did not load")
        XCTAssertTrue(app.buttons["haSettings.signOut"].exists)
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            self.openSettings(large)
            return large
        }
        app.buttons["haSettings.done"].tap()
        XCTAssertTrue(app.buttons["settings.homeAssistant"].waitForExistence(timeout: 5))
    }

    /// Home Assistant's own Settings page opens signed in (no web login form) and Back returns.
    func testHomeAssistantSettingsOpensSignedIn() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openSettings(app)
        let open = app.buttons["haSettings.open.settings"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 15))
        // The frontend's Settings dashboard lists Devices & services once signed in.
        let signedIn = web.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'Devices'")).firstMatch
        XCTAssertTrue(signedIn.waitForExistence(timeout: 30), "Home Assistant Settings did not open signed in")
        XCTAssertFalse(web.secureTextFields.firstMatch.exists, "Web login form shown")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["haSettings.signOut"].waitForExistence(timeout: 5))
    }

    /// Cancel keeps the session; confirming returns to sign-in.
    func testSignOutConfirmsThenReturnsToSignIn() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openSettings(app)
        app.buttons["haSettings.signOut"].tap()
        XCTAssertTrue(confirmButton(app).waitForExistence(timeout: 5))
        cancelSignOut(app)
        XCTAssertTrue(app.buttons["haSettings.done"].exists, "Cancel left the modal")
        app.buttons["haSettings.signOut"].tap()
        XCTAssertTrue(confirmButton(app).waitForExistence(timeout: 5))
        sleep(1) // Let the confirmation finish presenting.
        try FentonHomeApp.audit(app)
        confirmButton(app).tap()
        XCTAssertTrue(app.textFields["login.username"].waitForExistence(timeout: 10), "Sign-in did not appear")
    }

    /// Screenshots of the Settings tab, the modal and the web page in the current pose (iPad: also landscape).
    func testCaptureSettingsScreens() throws {
        let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]
        for orientation in orientations {
            if orientation != .unknown { XCUIDevice.shared.orientation = orientation }
            let suffix = orientation == .landscapeLeft ? "landscape" : orientation == .portrait ? "portrait" : "current"
            let app = try FentonHomeApp.launchSignedIn()
            app.tabBars.buttons["Settings"].tap()
            XCTAssertTrue(app.buttons["settings.homeAssistant"].waitForExistence(timeout: 5))
            keep(app, "settings-\(suffix)")
            openSettings(app)
            _ = app.descendants(matching: .any)["haSettings.role"].waitForExistence(timeout: 10)
            keep(app, "ha-settings-\(suffix)")
            app.buttons["haSettings.signOut"].tap()
            XCTAssertTrue(confirmButton(app).waitForExistence(timeout: 5))
            sleep(1)
            keep(app, "ha-signout-\(suffix)")
            cancelSignOut(app)
            app.buttons["haSettings.open.settings"].tap()
            _ = app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'Devices'")).firstMatch
                .waitForExistence(timeout: 30)
            sleep(1)
            keep(app, "ha-web-config-\(suffix)")
        }
        XCUIDevice.shared.orientation = .portrait
    }

    private func keep(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        // Same host hand-off as HomeJourneyTests: the lit panel of an unfolded Duo is captured by the host.
        guard let folder = ProcessInfo.processInfo.environment["FENTON_CAPTURE_DIR"], !folder.isEmpty else { return }
        let ready = URL(fileURLWithPath: folder).appendingPathComponent("\(name).ready")
        let done = URL(fileURLWithPath: folder).appendingPathComponent("\(name).done")
        FileManager.default.createFile(atPath: ready.path, contents: nil)
        let deadline = Date().addingTimeInterval(30)
        while !FileManager.default.fileExists(atPath: done.path), Date() < deadline { usleep(200_000) }
    }
}
