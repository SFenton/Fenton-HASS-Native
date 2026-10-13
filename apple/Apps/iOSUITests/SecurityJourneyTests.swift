import XCTest

/// The Security page in the debug gallery (fixture state, recording service caller; nothing reaches the house):
/// tile semantics, lock and garage door commands, the alarm mode sheet with its disarm confirmation, audits and
/// screenshots on iPhone, iPhone Duo and iPad. One signed-in journey opens the real tab read-only
/// (`.agents/pages/security/ios.md`).
@MainActor
final class SecurityJourneyTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        if FentonHomeApp.family == .iPad, ProcessInfo.processInfo.environment["FENTON_UITEST_ORIENTATION"] == "landscape" {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
        }
    }

    private enum Tile {
        static let alarm = "security.tile.alarm_control_panel.aqara_hub_m3_0056_security_system_2"
        static let frontDoor = "security.tile.lock.aqara_smart_lock_u400"
        static let left = "security.tile.cover.garage_left_door"
        static let right = "security.tile.cover.garage_right_door"
        static let vehicle = "security.tile.lock.fordpass_3fmtk3su5mma09266_doorlock"
    }

    // MARK: - Helpers

    private func launch(arguments: [String] = [], environment: [String: String] = [:]) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "security"
        app.launchEnvironment.merge(environment) { _, new in new }
        app.launchArguments += arguments
        app.launch()
        XCTAssertTrue(tile(Tile.alarm, in: app).waitForExistence(timeout: 30), "Security page did not appear")
        return app
    }

    private func tile(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons[id].firstMatch
    }

    private func expectCall(_ expected: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let label = app.staticTexts["gallery.lastCall"].firstMatch
        let matched = label.wait(for: \.label, toEqual: "Last call: \(expected)", timeout: 10)
        XCTAssertTrue(matched, "Last call was '\(label.label)'", file: file, line: line)
    }

    private func expectValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value == %@", value)
        let matched = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
        XCTAssertTrue(matched, "\(element.label) value is '\(element.value ?? "nil")', expected '\(value)'", file: file, line: line)
    }

    /// Scrolls the page until `element` can be tapped (AX5 and the folded Duo push tiles below the fold).
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews["security.scroll"].firstMatch
        for _ in 0..<8 where !(element.exists && element.isHittable) {
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.75))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -200)))
        }
        XCTAssertTrue(element.isHittable, "\(element) never came into view")
    }

    private func assertTarget(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(element.frame.width, 43, element.label, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 43, element.label, file: file, line: line)
    }

    private func openSystemSheet(_ app: XCUIApplication) {
        tile(Tile.alarm, in: app).tap()
        let home = app.buttons["security.mode.armed_home"]
        XCTAssertTrue(home.waitForExistence(timeout: 10), "Security system sheet did not open")
        XCTAssertTrue(home.wait(for: \.isHittable, toEqual: true, timeout: 10))
        sleep(1) // Mid-animation frames fail contrast and clipping.
    }

    // MARK: - Tiles

    /// Every tile is a named 44 pt+ button whose value is its state.
    func testTilesNameTheirState() {
        let app = launch()
        let expected = [
            (Tile.alarm, "Security System", "Armed Home"),
            (Tile.frontDoor, "Front Door", "Locked"),
            (Tile.left, "Left Door", "Closed"),
            (Tile.right, "Right Door", "Open"),
            (Tile.vehicle, "Doors", "Locked"),
        ]
        for (id, label, value) in expected {
            let element = tile(id, in: app)
            reveal(element, in: app)
            XCTAssertEqual(element.label, label)
            XCTAssertEqual(element.value as? String, value, label)
            assertTarget(element)
        }
        XCTAssertTrue(app.staticTexts["Security"].exists && app.staticTexts["Vehicle"].exists, "Section headers")
        XCTAssertTrue(app.buttons["security.chip.security"].exists)
        XCTAssertTrue(app.buttons["security.chip.contacts"].exists)
    }

    /// The front door unlocks then locks with explicit services, never `toggle`.
    func testFrontDoorLockSendsExplicitServices() {
        let app = launch()
        let door = tile(Tile.frontDoor, in: app)
        door.tap()
        expectCall("lock.unlock entity_id=lock.aqara_smart_lock_u400", in: app)
        expectValue(door, "Unlocked")
        door.tap()
        expectCall("lock.lock entity_id=lock.aqara_smart_lock_u400", in: app)
        expectValue(door, "Locked")
    }

    /// The open right door: "Sending Close…" at once, then the door's own Closing and Closed.
    func testGarageDoorShowsSendingThenFollowsTheDoor() {
        let app = launch()
        let door = tile(Tile.right, in: app)
        reveal(door, in: app)
        door.tap()
        expectValue(door, "Sending Close…", timeout: 3)
        expectCall("cover.close_cover entity_id=cover.garage_right_door", in: app)
        expectValue(door, "Closing")
        expectValue(door, "Closed")
    }

    /// A failed call shows Error on the tile.
    func testGarageDoorShowsErrorWhenTheCallFails() {
        let app = launch(environment: ["FENTON_GALLERY_FAIL": "1"])
        let door = tile(Tile.left, in: app)
        reveal(door, in: app)
        door.tap()
        expectValue(door, "Error")
    }

    // MARK: - Security system sheet

    /// Modes show the current one as selected; arming sends at once, disarming asks first and Cancel sends nothing.
    func testModesArmAtOnceAndDisarmConfirms() {
        let app = launch()
        openSystemSheet(app)
        let home = app.buttons["security.mode.armed_home"]
        XCTAssertTrue(home.isSelected, "The current mode is selected")
        for mode in ["armed_home", "armed_away", "armed_night", "disarmed"] { assertTarget(app.buttons["security.mode.\(mode)"]) }

        let night = app.buttons["security.mode.armed_night"]
        night.tap()
        expectCall("alarm_control_panel.alarm_arm_night entity_id=alarm_control_panel.aqara_hub_m3_0056_security_system_2", in: app)
        XCTAssertTrue(night.wait(for: \.isSelected, toEqual: true, timeout: 5))

        let disarm = app.buttons["security.mode.disarmed"]
        disarm.tap()
        let alert = app.alerts["Disarm the security system?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Disarming asks first")
        alert.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        expectCall("alarm_control_panel.alarm_arm_night entity_id=alarm_control_panel.aqara_hub_m3_0056_security_system_2", in: app)

        disarm.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Disarm"].firstMatch.tap()
        expectCall("alarm_control_panel.alarm_disarm entity_id=alarm_control_panel.aqara_hub_m3_0056_security_system_2", in: app)
        XCTAssertTrue(disarm.wait(for: \.isSelected, toEqual: true, timeout: 5))

        app.buttons["Done"].firstMatch.tap()
        expectValue(tile(Tile.alarm, in: app), "Disarmed")
    }

    /// The Contact Sensors chip opens the rooms (web `ContactSheet`), and a room pushes its doors and windows.
    func testContactChipOpensTheList() {
        let app = launch()
        app.buttons["security.chip.contacts"].tap()
        let entryway = app.buttons["overview.contacts.room.Entryway"]
        XCTAssertTrue(entryway.waitForExistence(timeout: 10))
        entryway.tap()
        XCTAssertTrue(app.navigationBars["Entryway Contact Sensors"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["room.entity.binary_sensor.front_door_contact_sensor_contact"].exists)
        app.buttons["Done"].firstMatch.tap()
    }

    // MARK: - Audits

    func testPagePassesAccessibilityAudit() throws {
        let app = launch()
        try FentonHomeApp.audit(app) { self.launch(arguments: FentonHomeApp.ax5) }
    }

    func testSystemSheetPassesAccessibilityAudit() throws {
        let app = launch()
        openSystemSheet(app)
        try FentonHomeApp.audit(app) {
            let large = self.launch(arguments: FentonHomeApp.ax5)
            self.openSystemSheet(large)
            return large
        }
    }

    func testDisarmAlertPassesAccessibilityAudit() throws {
        let app = launch()
        openSystemSheet(app)
        app.buttons["security.mode.disarmed"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        // The system alert's labels report "partially unsupported"; the AX5 relaunch proves they grow.
        try FentonHomeApp.audit(app) {
            let large = self.launch(arguments: FentonHomeApp.ax5)
            self.openSystemSheet(large)
            large.buttons["security.mode.disarmed"].tap()
            XCTAssertTrue(large.alerts.firstMatch.waitForExistence(timeout: 5))
            sleep(1)
            return large
        }
    }

    // MARK: - Signed in

    /// The real Security tab, read-only (no control is pressed against the house): tiles exist and the page passes
    /// the audit. Skips without credentials.
    func testSecurityTabSignedIn() throws {
        let app = try FentonHomeApp.launchSignedIn()
        showSecurityTab(app)
        for id in [Tile.alarm, Tile.frontDoor, Tile.left, Tile.right] {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 10), id)
        }
        XCTAssertFalse(app.buttons[Tile.vehicle].exists, "Vehicle stays hidden like the web")
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            self.showSecurityTab(large)
            return large
        }
        keepScreenshot(app, "security-live-\(FentonHomeApp.family)")
    }

    private func showSecurityTab(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["Security"].exists
            ? app.tabBars.buttons["Security"]
            : app.buttons.matching(NSPredicate(format: "label == 'Security' AND identifier == 'shield'")).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "Security tab not found")
        tab.tap()
        XCTAssertTrue(app.buttons[Tile.alarm].waitForExistence(timeout: 10), "Security page did not appear")
    }

    // MARK: - Screenshots

    /// The page, the mode sheet, the disarm confirmation and a garage door error, in the current pose
    /// (iPad: also landscape).
    func testCaptureSecurityScreens() {
        let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]
        for orientation in orientations {
            if orientation != .unknown { XCUIApplication().terminate(); XCUIDevice.shared.orientation = orientation }
            let suffix = orientation == .landscapeLeft ? "landscape" : orientation == .portrait ? "portrait" : "current"
            let app = launch(environment: ["FENTON_GALLERY_CLEAN": "1"])
            sleep(1)
            keepScreenshot(app, "security-\(suffix)")
            openSystemSheet(app)
            keepScreenshot(app, "security-system-\(suffix)")
            app.buttons["security.mode.disarmed"].tap()
            XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
            sleep(1)
            keepScreenshot(app, "security-disarm-\(suffix)")

            let failing = launch(environment: ["FENTON_GALLERY_CLEAN": "1", "FENTON_GALLERY_FAIL": "1"])
            let door = tile(Tile.left, in: failing)
            reveal(door, in: failing)
            door.tap()
            expectValue(door, "Error")
            keepScreenshot(failing, "security-garage-error-\(suffix)")
        }
        XCUIDevice.shared.orientation = .portrait
    }
}
