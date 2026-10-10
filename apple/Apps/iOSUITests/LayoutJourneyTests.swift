import XCTest

/// Orientation and split rules per device family (owner, 2026-10-10;
/// `.agents/design/apple/split-view.md`).
final class LayoutJourneyTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    override func tearDown() { XCUIDevice.shared.orientation = .portrait }

    /// iPhone is locked to portrait.
    func testIPhoneStaysPortrait() throws {
        guard FentonHomeApp.family == .iPhone else { throw XCTSkip("iPhone only") }
        let app = FentonHomeApp.launchSignedOut()
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        let frame = app.windows.firstMatch.frame
        XCTAssertGreaterThan(frame.height, frame.width, "iPhone rotated to landscape")
    }

    /// iPad follows the device into landscape.
    func testIPadRotates() throws {
        guard FentonHomeApp.family == .iPad else { throw XCTSkip("iPad only") }
        let app = FentonHomeApp.launchSignedOut()
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        let frame = app.windows.firstMatch.frame
        XCTAssertGreaterThan(frame.width, frame.height, "iPad did not rotate")
    }

    /// Every family audits clean in each orientation it supports. iPhone Duo poses are set in Device Hub
    /// before the run (XCUIDevice cannot fold or rotate the Duo); the test audits whatever pose it is in.
    func testSignInAuditsInSupportedOrientations() throws {
        let app = FentonHomeApp.launchSignedOut()
        XCTAssertTrue(app.textFields["login.username"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit()
        guard FentonHomeApp.family == .iPad else { return }
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        try app.performAccessibilityAudit()
    }
}
