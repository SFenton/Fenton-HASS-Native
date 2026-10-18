import XCTest

/// Settings → App Icon: the row, the sheet of eight named choices (Navy + Sky is the default), choosing one and the
/// accessibility audits, with an AX5 relaunch. On the simulator `setAlternateIconName` works: the journey asserts the
/// selection and dismisses the system's own notice.
@MainActor
final class AppIconJourneyTests: JourneyTestCase {
    private static let choices = ["navySky", "tealMint", "plumLilac", "forestGreen", "burgundyRose",
                                  "indigoPeriwinkle", "espressoAmber", "midnightGold"]

    // MARK: - Helpers

    /// The App Icon row, scrolled into view: it sits near the end of the Settings list, below the fold on a phone.
    private func appIconRow(_ app: XCUIApplication) -> XCUIElement {
        let row = app.buttons["settings.appIcon"]
        _ = app.descendants(matching: .any)["settings.list"].waitForExistence(timeout: 10)
        for _ in 0..<12 where !(row.exists && row.isHittable) {
            app.settingsList.swipeUp(velocity: .slow)
        }
        return row
    }

    /// Opens Settings → App Icon and waits for the sheet's default choice.
    private func openSheet(_ app: XCUIApplication) {
        app.openAccountSettings()
        let row = appIconRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "No App Icon row in Settings")
        assertTarget(row)
        row.tap()
        XCTAssertTrue(choice(app, "navySky").waitForExistence(timeout: 5), "The App Icon sheet did not open")
        sleep(1) // Let the sheet finish presenting.
    }

    private func choice(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons["appIcon.choice.\(name)"]
    }

    /// Scrolls the sheet until `element` can be tapped (one column at AX5, taller than the screen).
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        for _ in 0..<10 where !(element.exists && element.isHittable) {
            app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        }
        return element
    }

    /// Dismisses the system's "You have changed the icon" notice. SpringBoard draws it, and the app's main thread is
    /// busy until it is answered, so only SpringBoard is asked (an app query would wait out its 30 s busy timeout).
    private func dismissSystemNotice() {
        let ok = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["OK"].firstMatch
        if ok.waitForExistence(timeout: 10) { ok.tap() }
    }

    /// Chooses `name` and waits for it to read Selected.
    private func pick(_ name: String, in app: XCUIApplication) {
        let button = reveal(choice(app, name), in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 5), name)
        assertTarget(button)
        button.tap()
        dismissSystemNotice()
        let selected = NSPredicate(format: "value == 'Selected'")
        expectation(for: selected, evaluatedWith: choice(app, name))
        waitForExpectations(timeout: 10)
    }

    // MARK: - Journeys

    /// The row names the installed icon; the sheet lists the eight choices, each a button named for VoiceOver with its
    /// state, the default marked, every target 44 pt or more.
    func testRowOpensSheetOfEightNamedChoicesWithDefaultMarked() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openSheet(app)
        XCTAssertTrue(app.navigationBars["App Icon"].exists || app.staticTexts["App Icon"].exists, "Sheet has no App Icon title")
        for name in Self.choices {
            let button = reveal(choice(app, name), in: app)
            XCTAssertTrue(button.exists, "No choice \(name)")
            assertTarget(button)
            XCTAssertTrue(["Selected", "Not selected"].contains(button.value as? String ?? ""), "\(name) has no state: \(String(describing: button.value))")
        }
        let navy = choice(app, "navySky")
        _ = reveal(navy, in: app)
        XCTAssertEqual(navy.label, "Navy and Sky, default")
        XCTAssertEqual(choice(app, "tealMint").label, "Teal and Mint")
        let selected = Self.choices.filter { choice(app, $0).value as? String == "Selected" }
        XCTAssertEqual(selected.count, 1, "Exactly one icon is selected, got \(selected)")
    }

    /// Choosing an icon moves the selection and the row's subtitle; choosing the default again restores it.
    func testChoosingAnIconChangesTheSelectionAndTheDefaultRestoresIt() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openSheet(app)
        // Whatever an earlier run left installed, start from the default.
        if choice(app, "navySky").value as? String != "Selected" { pick("navySky", in: app) }
        pick("tealMint", in: app)
        XCTAssertEqual(choice(app, "navySky").value as? String, "Not selected")
        XCTAssertEqual(choice(app, "tealMint").value as? String, "Selected")
        keepScreenshot(app, "app-icon-sheet-\(layout)")
        pick("navySky", in: app)
        XCTAssertEqual(choice(app, "tealMint").value as? String, "Not selected")
        app.buttons["appIcon.close"].tap()
        XCTAssertTrue(choice(app, "navySky").waitForNonExistence(timeout: 5), "The sheet did not close")
        let row = appIconRow(app)
        XCTAssertTrue(row.label.contains("Navy + Sky"), "The row reads: \(row.label)")
    }

    /// The Settings list with the row, and the sheet, pass the accessibility audit, with an AX5 relaunch.
    func testSettingsRowAndSheetPassAccessibilityAudit() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openSheet(app)
        try FentonHomeApp.audit(app, ax5Page: {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            self.openSheet(large)
            return large
        })
    }

    /// The sheet in the system's light appearance (pages stay dark; sheets follow it).
    func testSheetPassesAccessibilityAuditInLightAppearance() throws {
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_APPEARANCE": "light"])
        openSheet(app)
        try FentonHomeApp.audit(app)
    }
}
