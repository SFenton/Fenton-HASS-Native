import XCTest

/// Settings → Feedback: Report an Issue and Request a Feature against the in-app fixture
/// (`FENTON_FEEDBACK_FIXTURE`), so no journey files a real GitHub issue. Audits run on every form and the
/// GitHub Access page, with an AX5 relaunch.
@MainActor
final class FeedbackJourneyTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        if FentonHomeApp.family == .iPad, ProcessInfo.processInfo.environment["FENTON_UITEST_ORIENTATION"] == "landscape" {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
    }

    override func tearDown() {
        if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
    }

    // MARK: - Helpers

    /// Signs in with the feedback fixture: `1` starts with a token, `connect` without one.
    private func launch(fixture: String = "1", arguments: [String] = []) throws -> XCUIApplication {
        try FentonHomeApp.launchSignedIn(arguments: arguments, environment: ["FENTON_FEEDBACK_FIXTURE": fixture])
    }

    /// Goes to Settings: through the navigation flyout in regular width (iPad, unfolded Duo), else the tab
    /// bar or the folded Duo's rail.
    private func goToSettings(_ app: XCUIApplication) {
        let open = app.buttons["nav.open"]
        if open.waitForExistence(timeout: 3) {
            open.tap()
            let row = app.buttons["nav.settings"]
            XCTAssertTrue(row.waitForExistence(timeout: 5), "Flyout Settings row not found")
            row.tap()
            return
        }
        let rail = app.buttons.matching(NSPredicate(format: "label == 'Settings' AND (identifier == 'gearshape' OR identifier == '')")).firstMatch
        let candidates = [app.tabBars.buttons["Settings"], app.toolbars.buttons["Settings"], rail]
        let deadline = Date().addingTimeInterval(15)
        repeat {
            if let found = candidates.first(where: \.exists) { found.tap(); return }
            usleep(500_000)
        } while Date() < deadline
        XCTFail("Settings tab not found")
    }

    /// The feedback row for `kind`, scrolled into view: it ends the Settings list, below the fold.
    private func feedbackRow(_ app: XCUIApplication, _ kind: String) -> XCUIElement {
        let row = app.buttons["settings.feedback.\(kind)"]
        _ = app.buttons["settings.homeAssistant"].waitForExistence(timeout: 10)
        for _ in 0..<10 where !(row.exists && row.isHittable) {
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        }
        return row
    }

    /// Opens the form for `kind` from Settings and waits for its Submit button.
    private func openForm(_ app: XCUIApplication, _ kind: String) {
        goToSettings(app)
        let row = feedbackRow(app, kind)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Feedback row \(kind) not found")
        XCTAssertGreaterThanOrEqual(row.frame.height, 43.5, "Feedback row below 44 pt")
        row.tap()
        XCTAssertTrue(app.buttons["feedback.submit"].waitForExistence(timeout: 5), "Feedback form did not open")
        sleep(1) // Let the sheet finish presenting.
    }

    /// Scrolls the form until `element` can be tapped (a `Form` only exposes rows it has laid out).
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, up: Bool = true) -> XCUIElement {
        for _ in 0..<8 where !(element.exists && element.isHittable) {
            if up { app.collectionViews.firstMatch.swipeUp(velocity: .slow) } else { app.collectionViews.firstMatch.swipeDown(velocity: .slow) }
        }
        return element
    }

    /// Types after the title's prefix: the tap lands at the field's trailing end, after the prefix.
    private func typeTitle(_ app: XCUIApplication, _ text: String) {
        let field = reveal(app.textFields["feedback.field.title"], in: app, up: false)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(text)
    }

    private func typeDescription(_ app: XCUIApplication, _ text: String) {
        let box = reveal(app.textViews["feedback.field.description"], in: app)
        box.tap()
        box.typeText(text)
    }

    /// Fills a valid report: title and description.
    private func fill(_ app: XCUIApplication, title: String) {
        typeTitle(app, title)
        typeDescription(app, "The garage tile stays on Opening.")
        if app.keyboards.firstMatch.exists { app.navigationBars.firstMatch.tap() }
    }

    private func submit(_ app: XCUIApplication) -> XCUIElement {
        let submit = app.buttons["feedback.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: submit)
        waitForExpectations(timeout: 5)
        submit.tap()
        return submit
    }

    // MARK: - Journeys

    /// Both rows open their form; an empty form closes without asking; the forms and rows pass the audit.
    func testRowsOpenFormsAndPassAudit() throws {
        let app = try launch()
        goToSettings(app)
        XCTAssertTrue(feedbackRow(app, "feature").exists)
        try FentonHomeApp.audit(app) {
            let large = try self.launch(arguments: FentonHomeApp.ax5)
            self.goToSettings(large)
            _ = self.feedbackRow(large, "bug")
            return large
        }
        feedbackRow(app, "bug").tap()
        XCTAssertTrue(app.buttons["feedback.submit"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["feedback.submit"].isEnabled, "Submit enabled on an empty form")
        XCTAssertTrue(app.textViews["feedback.field.repro"].exists || reveal(app.textViews["feedback.field.repro"], in: app).exists)
        sleep(1)
        try FentonHomeApp.audit(app, ax5Page: {
            let large = try self.launch(arguments: FentonHomeApp.ax5)
            self.openForm(large, "bug")
            return large
        }, presenter: app.buttons["settings.feedback.bug"])
        reveal(app.buttons["feedback.close"], in: app, up: false).tap()
        XCTAssertTrue(app.buttons["feedback.submit"].waitForNonExistence(timeout: 5), "Empty form asked before closing")
        feedbackRow(app, "feature").tap()
        XCTAssertTrue(app.buttons["feedback.submit"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews["feedback.field.repro"].exists, "Feature form shows Steps to Reproduce")
        XCTAssertTrue(reveal(app.buttons["feedback.github"], in: app).exists, "Sending-as row missing")
        try FentonHomeApp.audit(app, presenter: app.buttons["settings.feedback.feature"])
    }

    /// Typed input asks before closing; Keep Editing keeps it; Submit files issue #1.
    func testBugReportConfirmsDiscardThenFiles() throws {
        let app = try launch()
        openForm(app, "bug")
        fill(app, title: "Garage tile stuck")
        let cancel = reveal(app.buttons["feedback.close"], in: app, up: false)
        cancel.tap()
        let discard = app.buttons["feedback.discard.confirm"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5), "Discard confirmation missing")
        try FentonHomeApp.audit(app)
        let keep = app.buttons["feedback.discard.cancel"].firstMatch
        if keep.exists && keep.isHittable {
            keep.tap()
        } else {
            // iOS 27 anchors the dialog as a popover without Keep Editing; an outside tap keeps editing.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap()
        }
        XCTAssertTrue(discard.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["feedback.submit"].exists, "Keep Editing closed the form")
        _ = submit(app)
        let done = app.buttons["feedback.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "Sent alert missing")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'issue #1'")).firstMatch.exists)
        try FentonHomeApp.audit(app)
        done.tap()
        XCTAssertTrue(app.buttons["feedback.submit"].waitForNonExistence(timeout: 5), "Done did not close the form")
    }

    /// Without a token the form leads with Add GitHub Access; a wrong token is refused on the page; the
    /// fixture token is saved and Submit becomes available.
    func testAddingATokenEnablesSubmit() throws {
        let app = try launch(fixture: "connect")
        openForm(app, "feature")
        let access = app.buttons["feedback.github"]
        XCTAssertTrue(access.waitForExistence(timeout: 5))
        XCTAssertTrue(access.label.contains("Add GitHub Access"))
        fill(app, title: "Arrival lights")
        XCTAssertTrue(reveal(app.staticTexts["feedback.validation"], in: app).label.contains("GitHub access token"))
        XCTAssertFalse(app.buttons["feedback.submit"].isEnabled)
        reveal(access, in: app, up: false).tap()
        let field = app.secureTextFields["feedback.github.token"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "GitHub Access page did not open")
        XCTAssertTrue(app.links["feedback.github.create"].exists || app.buttons["feedback.github.create"].exists)
        try FentonHomeApp.audit(app) {
            let large = try self.launch(fixture: "connect", arguments: FentonHomeApp.ax5)
            self.openForm(large, "feature")
            self.reveal(large.buttons["feedback.github"], in: large, up: false).tap()
            XCTAssertTrue(large.secureTextFields["feedback.github.token"].waitForExistence(timeout: 5))
            return large
        }
        field.tap()
        field.typeText("x")
        app.buttons["feedback.github.save"].tap()
        XCTAssertTrue(app.staticTexts["feedback.github.error"].waitForExistence(timeout: 5), "Wrong token accepted")
        field.tap()
        field.typeText(XCUIKeyboardKey.delete.rawValue + "fixture-token")
        app.buttons["feedback.github.save"].tap()
        XCTAssertTrue(app.buttons["feedback.submit"].waitForExistence(timeout: 10), "Saving did not return to the form")
        XCTAssertTrue(reveal(app.buttons["feedback.github"], in: app).label.contains("fixture-user"), "Sending-as row missing")
        _ = submit(app)
        XCTAssertTrue(app.buttons["feedback.done"].waitForExistence(timeout: 10), "Sent alert missing")
    }

    /// A failed filing keeps everything typed and offers no token change.
    func testFailedFilingKeepsTheForm() throws {
        let app = try launch()
        openForm(app, "bug")
        fill(app, title: "fixture-failed check")
        _ = submit(app)
        let alert = app.alerts["Couldn't Send"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "Failure alert missing")
        XCTAssertFalse(alert.buttons["Update Token"].exists)
        alert.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["feedback.submit"].waitForExistence(timeout: 5))
        let title = reveal(app.textFields["feedback.field.title"], in: app, up: false)
        XCTAssertTrue((title.value as? String)?.contains("fixture-failed") == true, "Typed title lost")
    }

    /// Screenshots of the rows, both forms, the GitHub Access page and the sent alert (iPad: also landscape).
    func testCaptureFeedbackScreens() throws {
        let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]
        for orientation in orientations {
            if orientation != .unknown { XCUIApplication().terminate(); XCUIDevice.shared.orientation = orientation }
            let suffix = orientation == .landscapeLeft ? "landscape" : orientation == .portrait ? "portrait" : "current"
            let app = try launch(fixture: "connect")
            goToSettings(app)
            _ = feedbackRow(app, "feature")
            keepScreenshot(app, "feedback-rows-\(suffix)")
            feedbackRow(app, "bug").tap()
            XCTAssertTrue(app.buttons["feedback.submit"].waitForExistence(timeout: 5))
            sleep(1)
            keepScreenshot(app, "feedback-bug-empty-\(suffix)")
            app.buttons["feedback.github"].tap()
            XCTAssertTrue(app.secureTextFields["feedback.github.token"].waitForExistence(timeout: 5))
            keepScreenshot(app, "feedback-github-access-\(suffix)")
            let field = app.secureTextFields["feedback.github.token"]
            field.tap()
            field.typeText("fixture-token")
            app.buttons["feedback.github.save"].tap()
            XCTAssertTrue(app.buttons["feedback.submit"].waitForExistence(timeout: 10))
            fill(app, title: "Garage tile stuck")
            reveal(app.textViews["feedback.field.description"], in: app, up: false)
            keepScreenshot(app, "feedback-bug-filled-\(suffix)")
            _ = submit(app)
            XCTAssertTrue(app.buttons["feedback.done"].waitForExistence(timeout: 10))
            keepScreenshot(app, "feedback-sent-\(suffix)")
            app.buttons["feedback.done"].tap()
            XCTAssertTrue(app.buttons["feedback.submit"].waitForNonExistence(timeout: 5))
            feedbackRow(app, "feature").tap()
            XCTAssertTrue(app.buttons["feedback.submit"].waitForExistence(timeout: 5))
            sleep(1)
            keepScreenshot(app, "feedback-feature-\(suffix)")
        }
        if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
    }
}
