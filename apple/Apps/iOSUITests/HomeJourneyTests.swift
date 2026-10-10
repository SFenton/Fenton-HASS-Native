import XCTest

/// Home after a real sign-in: audit, chips, sheets and reopening without a reload.
final class HomeJourneyTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testHomePassesAccessibilityAudit() throws {
        let app = try FentonHomeApp.launchSignedIn()
        try app.performAccessibilityAudit()
    }

    func testStatusChipsHaveValueLabels() throws {
        let app = try FentonHomeApp.launchSignedIn()
        for sheet in ["lights", "security", "climate", "occupancy", "contacts"] {
            let chip = app.buttons["home.chip.\(sheet)"]
            XCTAssertTrue(chip.exists, sheet)
            XCTAssertTrue(chip.label.contains(","), "\(sheet) chip label lacks its summary: \(chip.label)")
            XCTAssertGreaterThanOrEqual(chip.frame.height, 43)
        }
    }

    func testLightsSheetOpensAndAudits() throws {
        let app = try FentonHomeApp.launchSignedIn()
        app.buttons["home.chip.lights"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()
        app.buttons["Done"].tap()
    }

    /// Reopening keeps Home on screen: no sign-in screen, no blank page.
    func testReopeningDoesNotReload() throws {
        let app = try FentonHomeApp.launchSignedIn()
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(app.buttons["home.chip.lights"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.textFields["login.username"].exists)
    }
}
