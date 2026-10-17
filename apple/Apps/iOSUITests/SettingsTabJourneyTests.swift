import XCTest

/// The Settings tab's root list on fixtures (`FENTON_GALLERY=settings`: the same `SettingsScreen` under the shell's page
/// chrome, no sign-in): every row is a named 44 pt control in the web's order, the list scrolls to its last row, and the
/// page passes the accessibility audit on iPhone, iPhone Duo and iPad. The signed-in Settings journeys
/// (`SettingsJourneyTests`) cover the Home Assistant modal.
final class SettingsTabJourneyTests: JourneyTestCase {
    /// The rows in order: Vacation and (for a viewer who sees it) To-Do, the household topics, Home Assistant, Performance,
    /// then the two feedback rows (`FeedbackKind` raw values).
    private static let rows = [
        "settings.vacation", "settings.topic.admin", "settings.topic.specialDeviceModes", "settings.topic.guests",
        "settings.topic.machE", "settings.homeAssistant", "settings.performance", "settings.feedback.bug", "settings.feedback.feature",
    ]

    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchArguments += arguments
        app.launchEnvironment["FENTON_GALLERY"] = "settings"
        app.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1"
        app.launch()
        XCTAssertTrue(element("settings.list", in: app).waitForExistence(timeout: 30), "The Settings list did not appear")
        return app
    }

    /// Scrolls until `row` can be tapped (a `List` only exposes rows it has laid out).
    private func reveal(_ row: XCUIElement, in app: XCUIApplication) {
        let list = element("settings.list", in: app)
        for _ in 0..<12 where !(row.exists && row.isHittable) { list.swipeUp(velocity: .slow) }
    }

    func testRowsAreNamedControlsWithTargets() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Household"].waitForExistence(timeout: 5), "The Household header is missing")
        for id in Self.rows.prefix(2) {
            let row = element(id, in: app)
            XCTAssertTrue(row.waitForExistence(timeout: 5), id)
            XCTAssertFalse(row.label.isEmpty, "\(id) has no label")
            assertTarget(row)
        }
        // Rows below the fold exist once scrolled to.
        for id in Self.rows.dropFirst(2) {
            let row = element(id, in: app)
            reveal(row, in: app)
            XCTAssertTrue(row.exists, "\(id) never came into view")
            XCTAssertFalse(row.label.isEmpty, "\(id) has no label")
            assertTarget(row)
        }
    }

    /// The list keeps its place and its rows through fast flicks both ways (the probe's drag, by hand).
    func testFlickingTheListKeepsItsRows() {
        let app = launch()
        let list = element("settings.list", in: app)
        for _ in 0..<3 {
            list.swipeUp(velocity: .fast)
            list.swipeDown(velocity: .fast)
        }
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(element("settings.vacation", in: app).waitForExistence(timeout: 5), "The first row vanished after flicking")
    }

    func testSettingsTabPassesAccessibilityAudit() throws {
        let app = launch()
        sleep(1) // Let the list settle before the audit reads it.
        try FentonHomeApp.audit(app) {
            let large = self.launch(arguments: FentonHomeApp.ax5)
            sleep(1)
            return large
        }
    }
}
