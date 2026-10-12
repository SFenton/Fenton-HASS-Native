import XCTest

/// Settings tab → Home Assistant settings modal: audit, account details, the signed-in web pages
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

    /// The Settings tab: in the tab bar, or the tab rail the folded iPhone Duo shows instead.
    private func settingsTab(_ app: XCUIApplication) -> XCUIElement {
        // The tab bar can appear a moment after launch (unfolded iPhone Duo), and the folded Duo shows a
        // vertical bar that XCUITest reports as a toolbar. Poll every form until one shows up: waiting on
        // the tab bar alone used up the time before the folded Duo's bar was checked.
        let rail = app.buttons.matching(NSPredicate(format: "label == 'Settings' AND identifier == 'gearshape'")).firstMatch
        let candidates = [app.tabBars.buttons["Settings"], app.toolbars.buttons["Settings"], rail]
        let deadline = Date().addingTimeInterval(15)
        repeat {
            if let found = candidates.first(where: \.exists) { return found }
            usleep(500_000)
        } while Date() < deadline
        return rail
    }

    /// Goes to Settings: through the navigation flyout in regular width (iPad, unfolded Duo), else the tab.
    private func goToSettings(_ app: XCUIApplication) {
        let open = app.buttons["nav.open"]
        if open.waitForExistence(timeout: 3) {
            open.tap()
            let row = app.buttons["nav.settings"]
            XCTAssertTrue(row.waitForExistence(timeout: 5), "Flyout Settings row not found")
            row.tap()
        } else {
            let tab = settingsTab(app)
            XCTAssertTrue(tab.waitForExistence(timeout: 10), "Settings tab not found")
            tab.tap()
        }
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
        guard app.buttons["settings.topic.admin"].waitForExistence(timeout: 5) || row.exists else { return row }
        for _ in 0..<8 where !(row.exists && row.isHittable) {
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        }
        if !row.exists { _ = row.waitForExistence(timeout: 2) }
        return row
    }

    /// Scrolls the modal until `element` can be tapped (the folded iPhone Duo's form is taller than
    /// its screen, and a `Form` only exposes rows it has laid out).
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        for _ in 0..<6 where !(element.exists && element.isHittable) {
            app.collectionViews.firstMatch.swipeUp()
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
            let dismiss = app.otherElements["PopoverDismissRegion"].firstMatch
            if dismiss.exists {
                dismiss.tap()
            } else {
                // Just above the popover: outside it, and clear of the bar's Done button.
                let popover = app.popovers.firstMatch.exists ? app.popovers.firstMatch.frame : confirmButton(app).frame
                app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: popover.midX, dy: max(popover.minY - 40, 0))).tap()
            }
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
        let signedIn = web.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'Devices'")).firstMatch
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
