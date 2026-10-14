import XCTest

/// Settings → Feedback: Report an Issue and Request a Feature against the in-app fixture
/// (`FENTON_FEEDBACK_FIXTURE`), so no journey reaches Home Assistant's relay or files a real GitHub issue. Audits
/// run on every form and the setup notice, with an AX5 relaunch.
@MainActor
final class FeedbackJourneyTests: JourneyTestCase {
    // MARK: - Helpers

    /// Signs in with the feedback fixture: `1` with the relay set up, `unavailable` without it.
    private func launch(fixture: String = "1", arguments: [String] = []) throws -> XCUIApplication {
        try FentonHomeApp.launchSignedIn(arguments: arguments, environment: ["FENTON_FEEDBACK_FIXTURE": fixture])
    }

    /// Goes to Settings: the profile avatar's Account sheet (direction G).
    private func goToSettings(_ app: XCUIApplication) {
        app.openAccountSettings()
    }

    /// The feedback row for `kind`, scrolled into view: it ends the Settings list, below the fold.
    private func feedbackRow(_ app: XCUIApplication, _ kind: String) -> XCUIElement {
        let row = app.buttons["settings.feedback.\(kind)"]
        _ = app.buttons["settings.homeAssistant"].waitForExistence(timeout: 10)
        for _ in 0..<10 where !(row.exists && row.isHittable) {
            app.settingsList.swipeUp(velocity: .slow)
        }
        return row
    }

    /// Opens the form for `kind` from Settings and waits for its Submit button.
    private func openForm(_ app: XCUIApplication, _ kind: String) {
        goToSettings(app)
        let row = feedbackRow(app, kind)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Feedback row \(kind) not found")
        assertTarget(row)
        row.tap()
        XCTAssertTrue(app.buttons["feedback.submit"].waitForExistence(timeout: 5), "Feedback form did not open")
        sleep(1) // Let the sheet finish presenting.
    }

    /// Scrolls the form until `element` can be tapped (a `Form` only exposes rows it has laid out).
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, up: Bool = true) -> XCUIElement {
        for _ in 0..<8 where !(element.exists && element.isHittable) {
            if up { app.settingsList.swipeUp(velocity: .slow) } else { app.settingsList.swipeDown(velocity: .slow) }
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
        dismissKeyboard(app)
    }

    /// The form dismisses the keyboard interactively: drag the list down from its middle.
    private func dismissKeyboard(_ app: XCUIApplication) {
        for _ in 0..<3 where app.keyboards.firstMatch.exists {
            let list = app.settingsList
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
                .press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
            _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 2)
        }
    }

    /// Submit, scrolled back into view: the folded iPhone Duo hides its bar while the form is scrolled down.
    private func submitButton(_ app: XCUIApplication) -> XCUIElement {
        let submit = app.buttons["feedback.submit"]
        for _ in 0..<6 where !(submit.exists && submit.isHittable) { app.collectionViews.firstMatch.swipeDown(velocity: .slow) }
        return submit
    }

    private func submit(_ app: XCUIApplication) -> XCUIElement {
        let submit = submitButton(app)
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: submit)
        waitForExpectations(timeout: 15)
        submit.tap()
        return submit
    }

    // MARK: - Journeys

    /// Both rows open their form and an empty form closes without asking; the Settings list passes the audit.
    func testRowsOpenFormsAndPassAudit() throws {
        let app = try launch()
        openForm(app, "bug")
        XCTAssertFalse(app.buttons["feedback.submit"].isEnabled, "Submit enabled on an empty form")
        reveal(app.buttons["feedback.close"], in: app, up: false).tap()
        XCTAssertTrue(app.buttons["feedback.submit"].waitForNonExistence(timeout: 5), "Empty form asked before closing")
        sleep(1) // Let the sheet finish dismissing before opening the next one.
        for _ in 0..<2 where !app.buttons["feedback.submit"].exists {
            feedbackRow(app, "feature").tap()
            _ = app.buttons["feedback.submit"].waitForExistence(timeout: 5)
        }
        XCTAssertTrue(app.buttons["feedback.submit"].exists, "Feature form did not open")
        reveal(app.buttons["feedback.close"], in: app, up: false).tap()
        XCTAssertTrue(app.buttons["feedback.submit"].waitForNonExistence(timeout: 5))
        // Audited last (the AX5 relaunch replaces this app instance), from the top of the list like
        // SettingsJourneyTests: scrolled to the end on the short folded Duo, the topics fade under the header and
        // the audit reports that faded text as element-less contrast issues it can't attribute.
        XCTAssertTrue(feedbackRow(app, "feature").exists)
        for _ in 0..<4 { app.settingsList.swipeDown(velocity: .fast) }
        try FentonHomeApp.audit(app) {
            let large = try self.launch(arguments: FentonHomeApp.ax5)
            // Same position as the audited page: the AX5 page is only compared with it (an element-less Dynamic
            // Type issue is waived when the same on-screen texts grow 1.35x), so scrolling one of them breaks the
            // comparison (folded Duo, 2026-10-14: 2 of 12 texts matched). The rows themselves are SettingsLinkRow,
            // audited at their position on iPhone and iPad.
            self.goToSettings(large)
            _ = large.buttons["settings.homeAssistant"].waitForExistence(timeout: 10)
            return large
        }
    }

    /// The bug form: reproduction boxes, Submit disabled while empty, and the audit with its AX5 relaunch.
    func testBugFormPassesAudit() throws {
        let app = try launch()
        openForm(app, "bug")
        XCTAssertTrue(reveal(app.textViews["feedback.field.repro"], in: app).exists, "Steps to Reproduce missing")
        reveal(app.buttons["feedback.close"], in: app, up: false)
        try FentonHomeApp.audit(app, ax5Page: {
            let large = try self.launch(arguments: FentonHomeApp.ax5)
            self.openForm(large, "bug")
            return large
        }, presenter: app.buttons["settings.feedback.bug"])
    }

    /// The feature form: no reproduction boxes, the Sending-as row, and the audit with its AX5 relaunch (its own
    /// launch, so the AX5 comparison measures two separate app instances).
    func testFeatureFormPassesAudit() throws {
        let app = try launch()
        openForm(app, "feature")
        XCTAssertFalse(app.textViews["feedback.field.repro"].exists, "Feature form shows Steps to Reproduce")
        try FentonHomeApp.audit(app, ax5Page: {
            let large = try self.launch(arguments: FentonHomeApp.ax5)
            self.openForm(large, "feature")
            return large
        }, presenter: app.buttons["settings.feedback.feature"])
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
        let done = app.buttons["feedback.done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10), "Sent alert missing")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'issue #1'")).firstMatch.exists)
        done.tap()
        XCTAssertTrue(app.buttons["feedback.submit"].waitForNonExistence(timeout: 5), "Done did not close the form")
    }

    /// Without the relay in Home Assistant the form leads with the setup notice and Submit stays off; the
    /// notice passes the audit.
    func testUnavailableRelayShowsSetupNotice() throws {
        let app = try launch(fixture: "unavailable")
        openForm(app, "bug")
        let notice = app.descendants(matching: .any)["feedback.setup"].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "Setup notice missing")
        XCTAssertTrue(notice.label.contains("Fenton Home Feedback"))
        fill(app, title: "Arrival lights")
        XCTAssertTrue(reveal(app.staticTexts["feedback.validation"], in: app).label.contains("isn't set up"))
        XCTAssertFalse(submitButton(app).isEnabled)
        reveal(notice, in: app, up: false)
        try FentonHomeApp.audit(app, ax5Page: {
            let large = try self.launch(fixture: "unavailable", arguments: FentonHomeApp.ax5)
            self.openForm(large, "bug")
            XCTAssertTrue(large.descendants(matching: .any)["feedback.setup"].firstMatch.waitForExistence(timeout: 5))
            return large
        }, presenter: app.buttons["settings.feedback.bug"])
    }

    /// A failed filing keeps everything typed.
    func testFailedFilingKeepsTheForm() throws {
        let app = try launch()
        openForm(app, "bug")
        fill(app, title: "fixture-failed check")
        _ = submit(app)
        let alert = app.alerts["Couldn't Send"]
        if !alert.waitForExistence(timeout: 10), app.buttons["feedback.submit"].isEnabled {
            app.buttons["feedback.submit"].tap() // The first tap can land while the keyboard is closing.
        }
        XCTAssertTrue(alert.waitForExistence(timeout: 15), "Failure alert missing")
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
            let app = try launch()
            goToSettings(app)
            _ = feedbackRow(app, "feature")
            keepScreenshot(app, "feedback-rows-\(suffix)")
            feedbackRow(app, "bug").tap()
            XCTAssertTrue(app.buttons["feedback.submit"].waitForExistence(timeout: 5))
            sleep(1)
            keepScreenshot(app, "feedback-bug-empty-\(suffix)")
            fill(app, title: "Garage tile stuck")
            reveal(app.textViews["feedback.field.description"], in: app, up: false)
            keepScreenshot(app, "feedback-bug-filled-\(suffix)")
            _ = submit(app)
            XCTAssertTrue(app.buttons["feedback.done"].firstMatch.waitForExistence(timeout: 10))
            keepScreenshot(app, "feedback-sent-\(suffix)")
            app.buttons["feedback.done"].firstMatch.tap()
            XCTAssertTrue(app.buttons["feedback.submit"].waitForNonExistence(timeout: 5))
            feedbackRow(app, "feature").tap()
            XCTAssertTrue(app.buttons["feedback.submit"].waitForExistence(timeout: 5))
            sleep(1)
            keepScreenshot(app, "feedback-feature-\(suffix)")
            let unset = try launch(fixture: "unavailable")
            openForm(unset, "bug")
            _ = unset.descendants(matching: .any)["feedback.setup"].firstMatch.waitForExistence(timeout: 5)
            keepScreenshot(unset, "feedback-setup-notice-\(suffix)")
        }
        if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
    }
}
