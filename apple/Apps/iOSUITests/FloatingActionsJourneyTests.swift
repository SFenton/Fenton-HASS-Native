import XCTest

/// The shared floating action bar and filter sheet in the debug gallery: actions, search, sort/filter
/// sheets, audits and screenshots on iPhone, iPhone Duo and iPad (`.agents/patterns/floating-actions.md`).
@MainActor
final class FloatingActionsJourneyTests: JourneyTestCase {
    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = FentonHomeApp.launchGallery("floating-actions", arguments: arguments)
        XCTAssertTrue(app.buttons["fab.add"].waitForExistence(timeout: 10))
        return app
    }

    private func lastAction(_ app: XCUIApplication) -> String {
        app.staticTexts["gallery.lastCall"].label
    }

    /// Every action is a named button at least 44 pt; icon-only actions keep their title for VoiceOver.
    func testActionsAreNamedAndLargeEnough() {
        let app = launch()
        for (id, label) in [("add", "Add Task"), ("sort", "Sort"), ("filter", "Filter"), ("search", "Search rows")] {
            let button = app.buttons["fab.\(id)"]
            XCTAssertTrue(button.exists, "\(id) missing")
            XCTAssertEqual(button.label, label)
            XCTAssertGreaterThanOrEqual(button.frame.height, 43, "\(id) too short")
            XCTAssertGreaterThanOrEqual(button.frame.width, 43, "\(id) too narrow")
            XCTAssertTrue(button.isHittable, "\(id) not hittable")
        }
        app.buttons["fab.add"].tap()
        XCTAssertEqual(lastAction(app), "Last action: add")
    }

    /// The search field expands over the other actions, filters, and closes back to the buttons.
    func testSearchExpandsAndCloses() {
        let app = launch()
        app.buttons["fab.search"].tap()
        let field = app.textFields["fab.search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["fab.add"].exists, "Actions stay visible while searching")
        field.typeText("Row 30")
        XCTAssertTrue(app.staticTexts["Row 30"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Row 2"].exists)
        app.buttons["fab.search.close"].tap()
        XCTAssertTrue(app.buttons["fab.add"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Row 2"].exists, "Closing search clears it")
    }

    /// Sort applies a draft; Cancel drops it; the applied sort shows the action as selected.
    func testSortSheetAppliesDraft() {
        let app = launch()
        app.buttons["fab.sort"].tap()
        let apply = app.buttons["filterSheet.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        XCTAssertFalse(apply.isEnabled, "Apply enabled without a change")
        app.buttons["gallery.sort.alphabetical"].tap()
        XCTAssertTrue(app.buttons["gallery.sort.alphabetical"].isSelected)
        XCTAssertTrue(apply.isEnabled)
        apply.tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 5))
        XCTAssertEqual(lastAction(app), "Last action: sort Alphabetical")
        XCTAssertTrue(app.buttons["fab.sort"].isSelected, "Active sort not shown")

        app.buttons["fab.sort"].tap()
        XCTAssertTrue(app.buttons["filterSheet.reset"].waitForExistence(timeout: 5))
        app.buttons["filterSheet.reset"].tap()
        app.buttons["filterSheet.cancel"].tap()
        XCTAssertTrue(app.buttons["fab.sort"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["fab.sort"].isSelected, "Cancel applied the draft")
    }

    func testPagePassesAccessibilityAudit() throws {
        let app = launch()
        keepScreenshot(app, "floating-actions-\(FentonHomeApp.family)")
        try FentonHomeApp.audit(app) { self.launch(arguments: FentonHomeApp.ax5) }
    }

    func testFilterSheetPassesAccessibilityAudit() throws {
        func open(_ app: XCUIApplication) -> XCUIApplication {
            app.buttons["fab.filter"].tap()
            XCTAssertTrue(app.buttons["filterSheet.apply"].waitForExistence(timeout: 5))
            sleep(1) // Let the sheet settle.
            return app
        }
        let app = open(launch())
        keepScreenshot(app, "filter-sheet-\(FentonHomeApp.family)")
        try FentonHomeApp.audit(app) { open(self.launch(arguments: FentonHomeApp.ax5)) }
    }
}
