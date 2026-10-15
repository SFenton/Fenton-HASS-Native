import XCTest

/// Profile → Account → Settings → Home Assistant settings modal: audit, account details, the signed-in web pages
/// and Sign Out, on every device family.
@MainActor
final class SettingsJourneyTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        // `FENTON_UITEST_ORIENTATION=landscape` runs the journeys in iPad landscape (XCUIDevice can't
        // rotate the iPhone Duo; set its pose in Device Hub instead).
        if FentonHomeApp.family == .iPad, ProcessInfo.processInfo.environment["FENTON_UITEST_ORIENTATION"] == "landscape" {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
    }

    override func tearDown() {
        if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
    }

    /// Goes to Settings: the profile avatar's Account sheet (direction G).
    private func goToSettings(_ app: XCUIApplication) {
        app.openAccountSettings()
    }

    /// Selects Settings and waits for its Home Assistant row, scrolled into view: it ends the topic list,
    /// below the fold on iPhone, and a `List` only exposes rows it has laid out.
    private func showSettingsTab(_ app: XCUIApplication) {
        goToSettings(app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(homeAssistantRow(app).exists)
    }

    /// The Home Assistant row, scrolled into view: it sits below the household topics, which push it off
    /// screen at AX5, and a `List` only exposes rows it has laid out.
    private func homeAssistantRow(_ app: XCUIApplication) -> XCUIElement {
        let row = app.buttons["settings.homeAssistant"]
        // Wait for the list, not a topic: at AX5 the first rows fill the sheet, so the admin topic isn't laid out yet
        // and waiting on it skipped the scroll (folded Duo, 2026-10-14).
        guard app.descendants(matching: .any)["settings.list"].waitForExistence(timeout: 5) || row.exists else { return row }
        for _ in 0..<12 where !(row.exists && row.isHittable) {
            app.settingsList.swipeUp(velocity: .slow)
        }
        if !row.exists { _ = row.waitForExistence(timeout: 2) }
        return row
    }

    /// Scrolls the modal until `element` can be tapped (the folded iPhone Duo's form is taller than
    /// its screen, and a `Form` only exposes rows it has laid out).
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        for _ in 0..<6 where !(element.exists && element.isHittable) {
            app.settingsList.swipeUp()
        }
        return element
    }

    /// Done, scrolled back into view (the folded iPhone Duo hides the bar while the form is scrolled).
    private func doneButton(_ app: XCUIApplication) -> XCUIElement {
        let done = app.buttons["haSettings.done"]
        for _ in 0..<6 where !(done.exists && done.isHittable) { app.collectionViews.firstMatch.swipeDown() }
        return done
    }

    /// The Sign Out row, scrolled into view.
    private func signOutRow(_ app: XCUIApplication) -> XCUIElement {
        reveal(app.buttons["haSettings.signOut"], in: app)
    }

    /// Back from a web page: the bar's back button, which the folded iPhone Duo moves to its rail.
    private func goBack(_ app: XCUIApplication) {
        let back = app.buttons["BackButton"].firstMatch
        if back.exists { back.tap() } else { app.navigationBars.buttons.element(boundBy: 0).tap() }
    }

    /// Opens the modal from a signed-in launch.
    private func openSettings(_ app: XCUIApplication) {
        showSettingsTab(app)
        let row = app.buttons["settings.homeAssistant"]
        XCTAssertTrue(row.exists)
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
            // An outside tap, just above the popover (below it when it sits near the top), clear of the bar's Done.
            // Not the dismiss region's own tap: inside the Account sheet there are several, and the first is the
            // sheet's, oversized around the window, so its centre fell on the popover and kept it open (iPad and
            // folded Duo, 2026-10-14).
            let popover = app.popovers.firstMatch.exists ? app.popovers.firstMatch.frame : confirmButton(app).frame
            let window = app.windows.firstMatch.frame
            let y = popover.minY > 80 ? popover.minY - 40 : min(popover.maxY + 40, window.maxY - 20)
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: popover.midX, dy: y)).tap()
        }
        XCTAssertTrue(confirmButton(app).waitForNonExistence(timeout: 5), "Sign-out confirmation did not close")
    }

    func testSettingsTabPassesAccessibilityAudit() throws {
        let app = try FentonHomeApp.launchSignedIn()
        showSettingsTab(app)
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            self.showSettingsTab(large)
            return large
        }
    }

    func testModalShowsServerAccountAndPassesAudit() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openSettings(app)
        XCTAssertTrue(row(app, "haSettings.status", showing: "Connected").waitForExistence(timeout: 15), "Connection row not live")
        XCTAssertTrue(app.descendants(matching: .any)["haSettings.role"].waitForExistence(timeout: 10), "Account did not load")
        XCTAssertTrue(signOutRow(app).exists)
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            self.openSettings(large)
            return large
        }
        doneButton(app).tap()
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
        // Any element: WebKit exposes the entry as a link labelled "Devices & services …" (iPad, 2026-10-14), and
        // `containing` only matched a text with a matching child.
        let signedIn = web.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'Devices'")).firstMatch
        XCTAssertTrue(signedIn.waitForExistence(timeout: 30), "Home Assistant Settings did not open signed in")
        XCTAssertFalse(web.secureTextFields.firstMatch.exists, "Web login form shown")
        goBack(app)
        XCTAssertTrue(app.buttons["haSettings.done"].waitForExistence(timeout: 5))
    }

    /// Cancel keeps the session; confirming returns to sign-in.
    func testSignOutConfirmsThenReturnsToSignIn() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openSettings(app)
        signOutRow(app).tap()
        XCTAssertTrue(confirmButton(app).waitForExistence(timeout: 5))
        cancelSignOut(app)
        XCTAssertTrue(app.buttons["haSettings.signOut"].waitForExistence(timeout: 5), "Cancel left the modal")
        signOutRow(app).tap()
        XCTAssertTrue(confirmButton(app).waitForExistence(timeout: 5))
        sleep(1) // Let the confirmation finish presenting.
        try FentonHomeApp.audit(app)
        // The audit can dismiss the popover; reopen it to confirm.
        if !confirmButton(app).exists { signOutRow(app).tap() }
        XCTAssertTrue(confirmButton(app).waitForExistence(timeout: 5))
        confirmButton(app).tap()
        XCTAssertTrue(app.textFields["login.username"].waitForExistence(timeout: 10), "Sign-in did not appear")
    }

    /// Screenshots of the Settings tab, the modal and the web page in the current pose (iPad: also landscape).
    func testCaptureSettingsScreens() throws {
        let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]
        for orientation in orientations {
            // Rotating with the web page up crashed the iPad simulator's backboardd; rotate from a fresh launch.
            if orientation != .unknown { XCUIApplication().terminate(); XCUIDevice.shared.orientation = orientation }
            let suffix = orientation == .landscapeLeft ? "landscape" : orientation == .portrait ? "portrait" : "current"
            let app = try FentonHomeApp.launchSignedIn()
            showSettingsTab(app)
            keepScreenshot(app, "settings-\(suffix)")
            openSettings(app)
            _ = app.descendants(matching: .any)["haSettings.role"].waitForExistence(timeout: 10)
            keepScreenshot(app, "ha-settings-\(suffix)")
            signOutRow(app).tap()
            XCTAssertTrue(confirmButton(app).waitForExistence(timeout: 5))
            sleep(1)
            keepScreenshot(app, "ha-signout-\(suffix)")
            cancelSignOut(app)
            reveal(app.buttons["haSettings.open.settings"], in: app).tap()
            _ = app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'Devices'")).firstMatch
                .waitForExistence(timeout: 30)
            sleep(1)
            keepScreenshot(app, "ha-web-config-\(suffix)")
        }
        // Only iPad rotates here; setting the orientation on an unfolded Duo hangs the runner (devices.md).
        if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
    }
}
