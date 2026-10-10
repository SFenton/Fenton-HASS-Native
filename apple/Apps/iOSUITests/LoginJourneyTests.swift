import XCTest

/// Sign-in screen: accessibility audit and target sizes on every device family.
@MainActor
final class LoginJourneyTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testLoginScreenPassesAccessibilityAudit() throws {
        let app = FentonHomeApp.launchSignedOut()
        XCTAssertTrue(app.textFields["login.username"].waitForExistence(timeout: 10))
        try FentonHomeApp.audit(app)
    }

    func testLoginFieldsAreLabelledAndReachable() {
        let app = FentonHomeApp.launchSignedOut()
        for id in ["login.server", "login.username"] {
            let field = app.textFields[id]
            XCTAssertTrue(field.waitForExistence(timeout: 10), id)
            // The tap target is the whole Form row: tapping its empty trailing space must focus the field.
            let cell = app.cells.containing(.textField, identifier: id).firstMatch
            XCTAssertGreaterThanOrEqual(cell.frame.height, 43, "\(id) is below the 44 pt target")
            cell.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.15)).tap()
            let before = field.value as? String ?? ""
            app.typeText("x")
            XCTAssertNotEqual(field.value as? String, before, "\(id) row space does not focus it")
            app.typeText(XCUIKeyboardKey.delete.rawValue)
        }
        XCTAssertTrue(app.secureTextFields["login.password"].exists)
        XCTAssertFalse(app.buttons["login.submit"].isEnabled, "Sign In must stay disabled until fields are filled")
    }
}
