import XCTest

/// Home after a real sign-in: audit, chips, sheets and reopening without a reload.
@MainActor
final class HomeJourneyTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testHomePassesAccessibilityAudit() throws {
        let app = try FentonHomeApp.launchSignedIn()
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            sleep(2)
            return large
        }
    }

    func testStatusChipsHaveValueLabels() throws {
        let app = try FentonHomeApp.launchSignedIn()
        for sheet in ["lights", "security", "climate", "occupancy", "contacts", "airQuality"] {
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
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            large.buttons["home.chip.lights"].tap()
            XCTAssertTrue(large.buttons["Done"].waitForExistence(timeout: 5))
            sleep(1)
            return large
        }
    }

    /// Opens the Lights sheet and pushes the Guest Room's lights.
    private func openGuestRoomLights(_ app: XCUIApplication) {
        app.buttons["home.chip.lights"].tap()
        let room = app.buttons["overview.lights.room.Guest Room"]
        XCTAssertTrue(room.waitForExistence(timeout: 5))
        XCTAssertTrue(room.wait(for: \.isHittable, toEqual: true, timeout: 5), "Sheet still presenting")
        room.tap()
        XCTAssertTrue(app.navigationBars["Guest Room Lights"].waitForExistence(timeout: 5))
    }

    /// A room in the Lights sheet pushes its lights (web room detail), and Back returns to the rooms.
    func testLightsRoomPushesItsLights() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openGuestRoomLights(app)
        XCTAssertTrue(app.descendants(matching: .any)["room.light.light.guest_room_tv_light"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["room.light.light.guest_room_bed_light"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["room.lightGroup.light.guest_room"].exists)
        goBack(in: app)
        XCTAssertTrue(app.buttons["overview.lights.room.Guest Room"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
    }

    /// Every room card in the Lights sheet has the height of the tallest one (a wrapping room name lifts them all).
    func testLightsRoomCardsShareOneHeight() throws {
        let app = try FentonHomeApp.launchSignedIn()
        app.buttons["home.chip.lights"].tap()
        let rooms = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'overview.lights.room.'"))
        XCTAssertTrue(rooms.firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        let heights = rooms.allElementsBoundByIndex.filter(\.isHittable).map(\.frame.height)
        XCTAssertGreaterThan(heights.count, 1)
        let tallest = heights.max() ?? 0
        for height in heights { XCTAssertEqual(height, tallest, accuracy: 1, "Room cards differ in height: \(heights)") }
        app.buttons["Done"].tap()
    }

    /// Each chip opens its overview, a room pushes its detail, and both pages pass the audit at default and AX5 size.
    func testChipSheetsAndRoomDetailsPassAccessibilityAudit() throws {
        let rooms = ["lights": "Kitchen", "climate": "Office", "occupancy": "Office", "contacts": "Office"]
        for chip in ["lights", "climate", "occupancy", "contacts", "airQuality", "security"] {
            let app = try FentonHomeApp.launchSignedIn()
            openChip(chip, in: app)
            try FentonHomeApp.audit(app) {
                let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
                self.openChip(chip, in: large)
                return large
            }
            guard let room = rooms[chip] else { continue }
            let detail = try FentonHomeApp.launchSignedIn()
            openRoom(room, chip: chip, in: detail)
            try FentonHomeApp.audit(detail) {
                let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
                self.openRoom(room, chip: chip, in: large)
                return large
            }
        }
    }

    /// Scrolls the status rail sideways until the chip is on screen (later chips start past the iPhone's edge).
    private func revealChip(_ chip: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch
        for _ in 0..<4 where !chip.isHittable {
            let y = chip.frame.midY
            let direction: CGFloat = chip.frame.minX > window.frame.midX ? -1 : 1
            let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: window.frame.midX, dy: y))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: direction * window.frame.width * 0.4, dy: 0)))
        }
    }

    /// Goes back one page: the system Back button wherever the bar puts it (the folded iPhone Duo moves bar items into
    /// its vertical bar), else the leading-edge back swipe (devices.md).
    private func goBack(in app: XCUIApplication) {
        let back = app.buttons["BackButton"]
        if back.exists, back.isHittable {
            back.tap()
            return
        }
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: window.frame.height / 2))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: window.frame.width * 0.7, dy: 0)))
    }

    private func openChip(_ chip: String, in app: XCUIApplication) {
        let button = app.buttons["home.chip.\(chip)"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), chip)
        revealChip(button, in: app)
        button.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5), chip)
        sleep(1) // Let the sheet finish presenting; mid-animation frames fail contrast and clipping.
    }

    private func openRoom(_ room: String, chip: String, in app: XCUIApplication) {
        openChip(chip, in: app)
        let tile = app.buttons["overview.\(chip).room.\(room)"]
        if !tile.isHittable { app.swipeUp() }
        tile.tap()
        XCTAssertTrue(app.staticTexts["overview.detail.subtitle"].waitForExistence(timeout: 5), "\(chip) \(room)")
        sleep(1)
    }

    /// Turning the Guest Room's group light on or off flips its live state, then the test restores it.
    func testLightsSheetTogglesAGroup() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openGuestRoomLights(app)
        let tile = app.descendants(matching: .any)["room.lightGroup.light.guest_room"]
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

    /// Dragging across a dimmable group sets its brightness live, then the test restores the old state.
    func testLightsSheetDragSetsBrightness() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openGuestRoomLights(app)
        let tile = app.descendants(matching: .any)["room.lightGroup.light.guest_room"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        XCTAssertTrue(tile.wait(for: \.isHittable, toEqual: true, timeout: 5), "Sheet still presenting")
        let before = try XCTUnwrap(tile.value as? String)
        XCTAssertNotEqual(before, "Unavailable")
        XCTAssertTrue(before == "Off" || before.hasSuffix("%"), "Not a brightness tile: \(before)")
        let target = before == "30%" ? 0.7 : 0.3
        drag(tile, to: target)
        let set = NSPredicate(format: "value != %@ AND value != 'Off'", before)
        wait(for: [XCTNSPredicateExpectation(predicate: set, object: tile)], timeout: 10)
        let level = Int((tile.value as? String ?? "").dropLast()) ?? -1
        XCTAssertEqual(Double(level), target * 100, accuracy: 6, "Drag landed at \(level)%")
        // Restore: off by tapping, else drag back to the old level.
        if before == "Off" { tile.tap() } else { drag(tile, to: (Double(before.dropLast()) ?? 100) / 100) }
        let moved = NSPredicate(format: "value != %@", "\(level)%")
        wait(for: [XCTNSPredicateExpectation(predicate: moved, object: tile)], timeout: 10)
        let after = tile.value as? String ?? ""
        if before == "Off" { XCTAssertEqual(after, "Off") } else {
            // brightness_pct round-trips through 0...255, so allow a few percent.
            XCTAssertEqual(Double(after.dropLast()) ?? -1, Double(before.dropLast()) ?? 0, accuracy: 3)
        }
        app.buttons["Done"].tap()
    }

    /// Drags horizontally from the leading edge to `fraction` of the tile's width.
    private func drag(_ tile: XCUIElement, to fraction: Double) {
        let start = tile.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        let end = tile.coordinate(withNormalizedOffset: CGVector(dx: fraction, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
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
            keepScreenshot(signedOut, "signin-\(suffix)")
            let app = try FentonHomeApp.launchSignedIn()
            sleep(2)
            keepScreenshot(app, "home-\(suffix)")
            app.buttons["home.chip.lights"].tap()
            XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
            sleep(1)
            keepScreenshot(app, "lights-\(suffix)")
            app.buttons["Done"].tap()
            captureChipSheets(app, suffix: suffix)
        }
        // Only iPad rotates here; setting the orientation on an unfolded Duo hangs the runner (devices.md).
        if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
    }

    /// Keeps each chip's overview and one room's detail page, named `<chip>-<page>-<orientation>`.
    private func captureChipSheets(_ app: XCUIApplication, suffix: String) {
        let rooms = ["lights": "Master Bedroom", "climate": "Living Room", "occupancy": "Living Room", "contacts": "Office"]
        for chip in ["lights", "climate", "occupancy", "contacts", "airQuality", "security"] {
            openChip(chip, in: app)
            keepScreenshot(app, "\(chip)-overview-\(suffix)")
            if let room = rooms[chip] {
                let tile = app.buttons["overview.\(chip).room.\(room)"]
                if !tile.isHittable { app.swipeUp() }
                tile.tap()
                XCTAssertTrue(app.staticTexts["overview.detail.subtitle"].waitForExistence(timeout: 5))
                sleep(1)
                keepScreenshot(app, "\(chip)-detail-\(suffix)")
            }
            app.buttons["Done"].firstMatch.tap()
            sleep(1)
        }
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
