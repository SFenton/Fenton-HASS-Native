import XCTest

/// The sign-in screen on every device family (owner design, 2026-10-17): layout, labels, targets, the plain-words errors, the
/// welcome back for an ended session, AX5 and Reduce Motion. Errors come from canned answers (`FENTON_SIGNIN_STUB`), so
/// no journey fails a sign-in on the real server.
@MainActor
final class LoginJourneyTests: JourneyTestCase {
    // MARK: - Helpers

    /// A launch signed out with a canned sign-in answer, the intro skipped unless asked for.
    private func launch(stub: String? = nil, expired: String? = nil, arguments: [String] = [], intro: Bool = false,
                        settings: [FentonHomeApp.SystemSetting] = []) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_UITEST_RESET"] = "1"
        app.launchEnvironment["FENTON_SKIP_INTRO"] = intro ? "0" : "1"
        app.launchEnvironment.merge(FentonHomeApp.SystemSetting.environment(settings)) { $1 }
        if let stub { app.launchEnvironment["FENTON_SIGNIN_STUB"] = stub }
        if let expired { app.launchEnvironment["FENTON_EXPIRED_ACCOUNT"] = expired }
        app.launchArguments += arguments
        app.launch()
        return app
    }

    /// Types a username and password the way a person does: tap, type, Return moves on, type, and the keyboard stays.
    private func fill(_ app: XCUIApplication, username: String = "stephen", password: String = "secret") {
        let user = app.textFields["login.username"]
        XCTAssertTrue(user.waitForExistence(timeout: 10), "username field")
        user.tap()
        user.typeText(username)
        // Return on the username moves to the password (submitLabel .next, focus chaining).
        app.typeText("\n")
        let pass = app.secureTextFields["login.password"]
        XCTAssertTrue(pass.waitForExistence(timeout: 5), "password field")
        pass.typeText(password)
    }

    private func submit(_ app: XCUIApplication) {
        let button = app.buttons["login.submit"]
        for _ in 0..<6 where !(button.exists && button.isHittable) {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    // MARK: - Layout and labels

    func testLoginScreenPassesAccessibilityAudit() throws {
        let app = launch()
        XCTAssertTrue(app.textFields["login.username"].waitForExistence(timeout: 10))
        try FentonHomeApp.audit(app)
    }

    /// Two rows, no address field, and a name, a line and the footnote; the title reads as "S and H".
    func testTheScreenHasOnlyTheTwoFieldsAndItsWords() {
        let app = launch()
        XCTAssertTrue(app.textFields["login.username"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.secureTextFields["login.password"].exists)
        XCTAssertFalse(app.textFields["login.server"].exists, "the server is fixed; there is no address field")
        XCTAssertFalse(app.textFields["login.code"].exists, "there is no second step")
        XCTAssertEqual(element("login.title", in: app).label, "S and H", "VoiceOver says the spoken name")
        XCTAssertTrue(app.staticTexts["Sign in to your Home Assistant"].exists)
        XCTAssertTrue(element("login.footnote", in: app).exists)
        XCTAssertFalse(app.buttons["login.submit"].isEnabled, "Sign In waits for both fields")
        XCTAssertTrue(app.buttons["login.submit"].label.contains("Sign In"))
    }

    /// Each row is a 52 pt target, tapping its empty space focuses the field, and Return moves from username to password.
    func testRowsAreTargetsAndReturnMovesOnToThePassword() {
        let app = launch()
        let user = app.textFields["login.username"]
        XCTAssertTrue(user.waitForExistence(timeout: 10))
        for field in [user, app.secureTextFields["login.password"]] {
            assertTarget(field)
            XCTAssertGreaterThanOrEqual(field.frame.height, 51, "rows are 52 pt")
        }
        // The whole row is the target: its trailing space focuses it.
        app.textFields["login.username"].coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        app.typeText("ab")
        XCTAssertEqual(user.value as? String, "ab", "the row's space focused the username")
        app.typeText("\n")
        app.typeText("secret")
        XCTAssertTrue(app.buttons["login.submit"].isEnabled, "both fields are filled")
        assertTarget(app.buttons["login.submit"])
    }

    /// iPad and the unfolded Duo: the form is a centred column no wider than 460 pt; iPhone fills its width.
    func testTheFormIsACentredColumnOnWideScreens() {
        let app = launch()
        let user = app.textFields["login.username"]
        XCTAssertTrue(user.waitForExistence(timeout: 10))
        let window = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(user.frame.width, 460, "the column is at most 460 pt wide")
        XCTAssertEqual(user.frame.midX, window.midX, accuracy: 2, "and centred")
        if FentonHomeApp.family == .iPhone {
            XCTAssertGreaterThan(user.frame.width, window.width - 80, "on a phone it fills the width")
        }
    }

    // MARK: - Errors

    func testAWrongPasswordIsSaidPlainlyAndKeepsTheUsername() {
        let app = launch(stub: "wrong")
        fill(app)
        submit(app)
        let message = element("login.error", in: app)
        XCTAssertTrue(message.waitForExistence(timeout: 10), "the red line appears under the fields")
        XCTAssertTrue(message.label.contains("That username and password don't match"), message.label)
        XCTAssertEqual(app.textFields["login.username"].value as? String, "stephen", "the username stays")
        let pass = app.secureTextFields["login.password"]
        XCTAssertTrue((pass.value as? String ?? "").isEmpty || pass.value as? String == "Password", "the password clears")
        XCTAssertFalse(app.buttons["login.submit"].isEnabled, "Sign In waits for a new password")
        XCTAssertFalse(element("login.error.card", in: app).exists, "a refused password is a line, not a card")
        pass.typeText("again")
        XCTAssertTrue(app.buttons["login.submit"].isEnabled, "the password field had the keyboard")
    }

    func testAnUnreachableServerGetsACardWithDetailsAndTryAgain() {
        let app = launch(stub: "unreachable")
        fill(app)
        submit(app)
        XCTAssertTrue(element("login.error.card", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Can't reach Home right now"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Check that this phone is online")).firstMatch.exists)
        XCTAssertFalse(element("login.error.detail", in: app).exists, "the raw reason is behind Details")
        let details = element("login.error.details", in: app)
        XCTAssertTrue(details.exists)
        details.tap()
        XCTAssertTrue(element("login.error.detail", in: app).waitForExistence(timeout: 5), "Details shows the raw reason")
        XCTAssertTrue(app.buttons["login.submit"].label.contains("Try Again"))
        XCTAssertEqual(app.textFields["login.username"].value as? String, "stephen", "the fields keep their values")
    }

    func testAnotherFailureGetsTheSignInDidntWorkCard() {
        let app = launch(stub: "failed")
        fill(app)
        submit(app)
        XCTAssertTrue(app.staticTexts["Sign-in didn't work"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("login.error.details", in: app).exists)
    }

    func testTwoStepSignInIsExplainedNotOffered() {
        let app = launch(stub: "twostep")
        fill(app)
        submit(app)
        let message = element("login.error", in: app)
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        XCTAssertTrue(message.label.contains("Two-step sign-in isn't supported"), message.label)
        XCTAssertFalse(app.textFields["login.code"].exists, "no code field")
    }

    /// While the request is out the button reads "Signing In…" and says it is busy; the fields are off.
    func testTheBusyStateShowsInTheButton() {
        let app = launch(stub: "slow")
        fill(app)
        submit(app)
        let button = app.buttons["login.submit"]
        let busy = NSPredicate(format: "label CONTAINS %@", "Signing In")
        expectation(for: busy, evaluatedWith: button)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(button.value as? String, "Signing In", "the arc is silent; the button says it is busy")
        XCTAssertFalse(app.textFields["login.username"].isEnabled, "the fields are off while it works")
    }

    // MARK: - Session ended

    func testAnEndedSessionWelcomesTheAccountBackAndAsksForThePasswordAlone() {
        let app = launch(expired: "stephen|Stephen Fenton")
        XCTAssertTrue(element("login.title", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element("login.title", in: app).label.contains("Welcome back, Stephen"))
        XCTAssertFalse(app.textFields["login.username"].exists, "the account is shown, not asked for")
        let readonly = element("login.username.readonly", in: app)
        XCTAssertTrue(readonly.exists)
        XCTAssertTrue(readonly.label.contains("stephen"))
        XCTAssertTrue(app.secureTextFields["login.password"].exists)
        let different = app.buttons["login.differentAccount"]
        XCTAssertTrue(different.exists)
        assertTarget(different)
        different.tap()
        XCTAssertTrue(app.textFields["login.username"].waitForExistence(timeout: 5), "Use a Different Account asks for the username")
        XCTAssertEqual(element("login.title", in: app).label, "S and H")
    }

    func testTheWelcomeBackScreenPassesTheAudit() throws {
        let app = launch(expired: "stephen|Stephen Fenton")
        XCTAssertTrue(app.secureTextFields["login.password"].waitForExistence(timeout: 10))
        try FentonHomeApp.audit(app)
    }

    // MARK: - Large text and motion

    /// At AX5 the labels sit above the fields, the form scrolls, and Sign In stays reachable.
    func testAtTheLargestTextTheFormScrollsAndSignInStaysReachable() throws {
        let app = launch(stub: "wrong", arguments: FentonHomeApp.ax5)
        XCTAssertTrue(app.textFields["login.username"].waitForExistence(timeout: 10))
        fill(app)
        let button = app.buttons["login.submit"]
        for _ in 0..<6 where !(button.exists && button.isHittable) {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(button.isHittable, "Sign In is reachable by scrolling")
        try FentonHomeApp.audit(app)
    }

    /// The intro ends on the form, and with Reduce Motion it is a cross-fade that ends there too.
    func testTheIntroEndsOnTheFormWithAndWithoutMotion() {
        for settings in [[], [FentonHomeApp.SystemSetting.reduceMotion]] {
            let app = launch(intro: true, settings: settings)
            XCTAssertTrue(app.textFields["login.username"].waitForExistence(timeout: 10), "\(settings)")
            let deadline = Date().addingTimeInterval(4)
            while !app.buttons["login.submit"].isHittable, Date() < deadline { usleep(200_000) }
            XCTAssertTrue(element("login.footnote", in: app).exists)
            XCTAssertFalse(app.keyboards.firstMatch.exists, "no keyboard comes up by itself")
            app.terminate()
        }
    }
}
