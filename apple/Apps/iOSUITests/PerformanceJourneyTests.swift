import XCTest

/// The content gate and the Performance screen in the debug gallery: the spinner-then-content sequence, the
/// screen's semantics, and accessibility audits (default and AX5) on iPhone, iPhone Duo and iPad.
@MainActor
final class PerformanceJourneyTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ mode: String, arguments: [String] = []) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "performance"
        app.launchEnvironment["FENTON_GALLERY_PERF"] = mode
        app.launchArguments += arguments
        app.launch()
        return app
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(name)-\(FentonHomeApp.family)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Content gate

    /// Loading hides the content and shows a labeled spinner; once loaded the spinner goes and the content shows.
    /// Reload fades the content out and runs the sequence again.
    func testGateShowsSpinnerThenContent() {
        let app = launch("gate")
        let spinner = element("contentGate.spinner", in: app)
        let tile = app.buttons["Item 1"].firstMatch
        XCTAssertTrue(spinner.waitForExistence(timeout: 5), "No spinner while loading")
        XCTAssertEqual(spinner.label, "Loading")
        XCTAssertFalse(tile.exists, "Content is reachable while it is hidden")
        screenshot("gate-loading")

        XCTAssertTrue(tile.waitForExistence(timeout: 5), "Content never appeared")
        XCTAssertTrue(spinner.waitForNonExistence(timeout: 2), "Spinner stayed after the content appeared")
        XCTAssertTrue(app.staticTexts["Loaded 0"].firstMatch.exists)
        screenshot("gate-loaded")

        app.buttons["gate.reload"].tap()
        XCTAssertTrue(spinner.waitForExistence(timeout: 2), "Reload did not return to loading")
        XCTAssertTrue(app.staticTexts["Loaded 1"].firstMatch.waitForExistence(timeout: 5), "Reloaded content never appeared")
    }

    // MARK: - Performance screen

    /// Every section shows the seeded measurements; Reset clears scrolling.
    func testPerformanceScreenShowsMeasurements() {
        let app = launch("screen")
        XCTAssertTrue(element("performance.screen", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Recipes"].firstMatch.exists || app.otherElements["Recipes"].firstMatch.exists
            || element("Recipes", in: app).exists, "Recipes scroll row missing")
        XCTAssertTrue(app.switches["performance.recording"].exists)
        screenshot("performance-top")
        for _ in 0..<4 { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(app.buttons["performance.export"].waitForExistence(timeout: 5), "Export missing")
        screenshot("performance-bottom")
        app.buttons["performance.reset"].tap()
        for _ in 0..<4 { app.collectionViews.firstMatch.swipeDown() }
        XCTAssertTrue(app.staticTexts["Scroll a page to measure it."].waitForExistence(timeout: 5), "Reset kept scroll rows")
    }

    func testPerformanceScreenPassesAccessibilityAudit() throws {
        let app = launch("screen")
        XCTAssertTrue(element("performance.screen", in: app).waitForExistence(timeout: 10))
        sleep(1)
        try FentonHomeApp.audit(app, ax5Page: { [self] in
            let large = launch("screen", arguments: FentonHomeApp.ax5)
            XCTAssertTrue(element("performance.screen", in: large).waitForExistence(timeout: 10))
            return large
        })
    }

    func testPerformanceScreenAtAX5() throws {
        let app = launch("screen", arguments: FentonHomeApp.ax5)
        XCTAssertTrue(element("performance.screen", in: app).waitForExistence(timeout: 10))
        sleep(1)
        screenshot("performance-ax5")
        try FentonHomeApp.audit(app)
    }

    func testGatePassesAccessibilityAudit() throws {
        let app = launch("gate")
        XCTAssertTrue(app.buttons["Item 1"].firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        try FentonHomeApp.audit(app)
    }
}
