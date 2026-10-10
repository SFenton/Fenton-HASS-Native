import XCTest

/// Sign-in screen: accessibility audit and target sizes on every device family.
final class LoginJourneyTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testLoginScreenPassesAccessibilityAudit() throws {
        let app = FentonHomeApp.launchSignedOut()
        XCTAssertTrue(app.textFields["login.username"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit()
    }

    func testLoginFieldsAreLabelledAndReachable() {
        let app = FentonHomeApp.launchSignedOut()
        for id in ["login.server", "login.username"] {
            let field = app.textFields[id]
            XCTAssertTrue(field.waitForExistence(timeout: 10), id)
            XCTAssertGreaterThanOrEqual(field.frame.height, 43, "\(id) is below the 44 pt target")
        }
        XCTAssertTrue(app.secureTextFields["login.password"].exists)
        XCTAssertFalse(app.buttons["login.submit"].isEnabled, "Sign In must stay disabled until fields are filled")
    }
}
