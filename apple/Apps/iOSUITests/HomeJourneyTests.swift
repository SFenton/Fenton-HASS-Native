import XCTest

/// Home after a real sign-in: audit, chips, sheets and reopening without a reload.
@MainActor
final class HomeJourneyTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testHomePassesAccessibilityAudit() throws {
        let app = try FentonHomeApp.launchSignedIn()
        try FentonHomeApp.audit(app)
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
        sleep(1) // Let the sheet finish presenting; mid-animation frames fail contrast and clipping.
        try FentonHomeApp.audit(app)
        app.buttons["Done"].tap()
    }

    /// Toggling a light group in the Lights sheet flips its live state, then the test restores it.
    func testLightsSheetTogglesAGroup() throws {
        let app = try FentonHomeApp.launchSignedIn()
        app.buttons["home.chip.lights"].tap()
        let tile = app.descendants(matching: .any)["lights.group.light.gym_light"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        XCTAssertTrue(tile.wait(for: \.isHittable, toEqual: true, timeout: 5), "Sheet still presenting")
        let before = try XCTUnwrap(tile.value as? String)
        XCTAssertNotEqual(before, "Unavailable")
        tile.tap()
        let changed = NSPredicate(format: "value != %@", before)
        wait(for: [XCTNSPredicateExpectation(predicate: changed, object: tile)], timeout: 10)
        tile.tap()
        let restored = NSPredicate(format: "value == %@", before)
        wait(for: [XCTNSPredicateExpectation(predicate: restored, object: tile)], timeout: 10)
        app.buttons["Done"].tap()
    }

    /// Keeps screenshots of sign-in, Home and the Lights sheet in the pose the device is in (iPad: also
    /// landscape), named `<screen>-<orientation>`, for design review on every layout.
    func testCaptureScreens() throws {
        let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]
        for orientation in orientations {
            if orientation != .unknown { XCUIDevice.shared.orientation = orientation }
            let suffix = orientation == .landscapeLeft ? "landscape" : orientation == .portrait ? "portrait" : "current"
            let signedOut = FentonHomeApp.launchSignedOut()
            XCTAssertTrue(signedOut.textFields["login.username"].waitForExistence(timeout: 10))
            keep(signedOut, "signin-\(suffix)")
            let app = try FentonHomeApp.launchSignedIn()
            sleep(2)
            keep(app, "home-\(suffix)")
            app.buttons["home.chip.lights"].tap()
            XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
            sleep(1)
            keep(app, "lights-\(suffix)")
            app.buttons["Done"].tap()
        }
        XCUIDevice.shared.orientation = .portrait
    }

    private func keep(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        // XCUIScreen captures only the outer panel, which is dark on an unfolded iPhone Duo. With
        // FENTON_CAPTURE_DIR set, the host captures the lit panel: `<name>.ready` asks, `<name>.done` answers.
        guard let folder = ProcessInfo.processInfo.environment["FENTON_CAPTURE_DIR"], !folder.isEmpty else { return }
        let ready = URL(fileURLWithPath: folder).appendingPathComponent("\(name).ready")
        let done = URL(fileURLWithPath: folder).appendingPathComponent("\(name).done")
        FileManager.default.createFile(atPath: ready.path, contents: nil)
        let deadline = Date().addingTimeInterval(30)
        while !FileManager.default.fileExists(atPath: done.path), Date() < deadline { usleep(200_000) }
    }

    /// Keeps a screenshot of live Home in the result bundle.
    func testHomeScreenshot() throws {
        let app = try FentonHomeApp.launchSignedIn()
        sleep(2)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Home"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A password sign-in keeps its refresh token in the Keychain, so a cold relaunch opens on Home.
    func testRelaunchSkipsSignIn() throws {
        let app = try FentonHomeApp.launchSignedIn(passwordOnly: true)
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launch()
        XCTAssertTrue(relaunched.buttons["home.chip.lights"].waitForExistence(timeout: 10), "Relaunch did not open on Home")
        XCTAssertFalse(relaunched.textFields["login.username"].exists)
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
