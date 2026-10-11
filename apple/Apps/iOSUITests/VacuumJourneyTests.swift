import XCTest

/// The vacuums page and sheets in the debug gallery (fixture state, mock maps, recording service caller; nothing
/// reaches a real robot): semantics, service calls, layout per pose, accessibility audits and screenshots on iPhone,
/// iPhone Duo and iPad (`.agents/patterns/vacuum-sheet.md`).
@MainActor
final class VacuumJourneyTests: XCTestCase {
    static let mainFloor = "valetudo_exaltedsneakydeer"
    static let musicRoom = "valetudo_elatedusedram"

    override func setUp() { continueAfterFailure = false }
    override func tearDown() {
        MainActor.assumeIsolated {
            if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
        }
    }

    // MARK: - Helpers

    /// Opens the gallery page, or a vacuum's sheet on `tab`.
    private func launch(_ vacuum: String? = nil, tab: String = "controls", scenario: String = "docked",
                        clean: Bool = false, arguments: [String] = []) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "vacuums"
        if let vacuum { app.launchEnvironment["FENTON_GALLERY_VACUUM"] = vacuum }
        app.launchEnvironment["FENTON_GALLERY_TAB"] = tab
        app.launchEnvironment["FENTON_GALLERY_SCENARIO"] = scenario
        if clean { app.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1" }
        app.launchArguments += arguments
        app.launch()
        let anchor = vacuum == nil ? element("vacuums.tile.\(Self.mainFloor)", in: app) : element("vacuum.tabs", in: app)
        XCTAssertTrue(anchor.waitForExistence(timeout: 30), "Vacuums did not open")
        XCTAssertTrue(anchor.wait(for: \.isHittable, toEqual: true, timeout: 10), "Still presenting")
        sleep(1) // Mid-animation frames fail contrast and clipping.
        return app
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func expectCall(_ expected: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let label = app.staticTexts["gallery.lastCall"].firstMatch
        let matched = label.wait(for: \.label, toEqual: "Last call: \(expected)", timeout: 10)
        XCTAssertTrue(matched, "Last call was '\(label.label)'", file: file, line: line)
    }

    /// Drags toward `element` in short steps until it is hittable (see MediaRemoteJourneyTests.reveal).
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, down: Bool = true) {
        let window = app.windows.firstMatch.frame
        for _ in 0..<24 where !element.isHittable {
            let above = element.exists ? element.frame.midY < window.midY : !down
            var x = element.exists && element.frame.midX > 0 ? element.frame.midX : window.midX
            if FentonHomeApp.family == .iPhoneDuo { x = min(x, window.maxX - 96) }
            let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: -window.minX, dy: -window.minY))
            let from = origin.withOffset(CGVector(dx: x, dy: window.minY + window.height * (above ? 0.35 : 0.65)))
            let to = from.withOffset(CGVector(dx: 0, dy: above ? 220 : -220))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(element.isHittable, "\(element) never came into view")
    }

    private func assertTarget(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(element.frame.width, 43, element.label, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 43, element.label, file: file, line: line)
    }

    private func tab(_ title: String, in app: XCUIApplication) {
        let picker = element("vacuum.tabs", in: app)
        picker.buttons[title].firstMatch.tap()
    }

    // MARK: - Page

    /// Tiles name each robot and its state; the pause tile is a switch; tapping a robot opens its sheet.
    func testPageTilesAndAutoClean() {
        let app = launch()
        let tile = app.buttons["vacuums.tile.\(Self.mainFloor)"]
        XCTAssertTrue(tile.label.contains("Main Floor"), tile.label)
        assertTarget(tile)
        let pause = element("vacuums.autoClean.switch.main_floor_vacuum_coordinator_pause", in: app)
        reveal(pause, in: app)
        XCTAssertEqual(pause.value as? String, "Enabled")
        pause.tap()
        expectCall("switch.turn_on entity_id=switch.main_floor_vacuum_coordinator_pause", in: app)
        let paused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Paused"), object: pause)
        XCTAssertEqual(XCTWaiter().wait(for: [paused], timeout: 10), .completed, "Pause tile value is \(pause.value ?? "nil")")

        reveal(tile, in: app, down: false)
        tile.tap()
        XCTAssertTrue(element("vacuum.tabs", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Main Floor Robot Vacuum"].exists)
    }

    /// Splits only where allowed: unfolded Duo landscape and iPad landscape.
    func testPageLayoutFollowsThePose() {
        if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .landscapeLeft }
        let app = launch()
        let split = element("vacuums.layout.split", in: app).exists
        switch FentonHomeApp.family {
        case .iPad: XCTAssertTrue(split, "iPad landscape splits")
        case .iPhone: XCTAssertFalse(split, "iPhone never splits")
        default: XCTAssertEqual(split, app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height && app.windows.firstMatch.frame.width > 700)
        }
    }

    // MARK: - Sheet

    /// Rooms toggle with order badges, setting the mode; Clean sends the selected-segments script.
    func testRoomsAndClean() {
        let app = launch(Self.mainFloor)
        tab("Rooms", in: app)
        let office = app.buttons["vacuum.room.input_boolean.main_floor_vacuum_office"]
        XCTAssertTrue(office.waitForExistence(timeout: 10))
        assertTarget(office)
        XCTAssertFalse(office.isSelected)
        office.tap()
        XCTAssertTrue(office.wait(for: \.isSelected, toEqual: true, timeout: 5))
        XCTAssertTrue(office.label.contains("3"), "Order badge in the label: \(office.label)")

        tab("Controls", in: app)
        let clean = app.buttons["vacuum.action.clean"]
        reveal(clean, in: app)
        assertTarget(clean)
        clean.tap()
        expectCall("script.main_floor_vacuum_clean_selected_segments", in: app)
        XCTAssertTrue(app.buttons["vacuum.action.pause"].waitForExistence(timeout: 10), "Cleaning shows Pause")
        app.buttons["vacuum.action.pause"].tap()
        expectCall("vacuum.pause entity_id=vacuum.valetudo_exaltedsneakydeer", in: app)
    }

    /// Settings are menus with values; picking one sends select_option.
    func testPowerSettings() {
        let app = launch(Self.musicRoom)
        let mode = element("vacuum.setting.Mode", in: app)
        reveal(mode, in: app)
        XCTAssertTrue((mode.value as? String ?? mode.label).contains("Vacuum & Mop"))
        mode.tap()
        app.buttons["Vacuum"].firstMatch.tap()
        expectCall("select.select_option entity_id=select.\(Self.musicRoom)_mode option=vacuum", in: app)
    }

    /// The area editor draws a default area for VoiceOver users and Use This Area returns to Controls.
    func testAreaEditor() {
        let app = launch(Self.mainFloor)
        let area = app.buttons["vacuum.target.area"]
        reveal(area, in: app, down: true)
        area.tap()
        if app.alerts.firstMatch.waitForExistence(timeout: 2) || app.sheets.firstMatch.exists {
            app.buttons["Switch to Area"].firstMatch.tap()
        }
        let edit = app.buttons["vacuum.area.edit"]
        reveal(edit, in: app)
        edit.tap()
        let draw = app.buttons["vacuum.area.draw"]
        XCTAssertTrue(draw.waitForExistence(timeout: 10))
        // Drag across the map to draw.
        let map = element("vacuum.area.map", in: app)
        let start = map.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35))
        start.press(forDuration: 0.1, thenDragTo: map.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)))
        XCTAssertTrue(element("vacuum.area.dimensions", in: app).waitForExistence(timeout: 5))
        let use = app.buttons["vacuum.area.use"]
        reveal(use, in: app)
        use.tap()
        let startArea = app.buttons["vacuum.action.cleanArea"]
        reveal(startArea, in: app)
        XCTAssertTrue(startArea.isEnabled)
        startArea.tap()
        let label = app.staticTexts["gallery.lastCall"].firstMatch
        let zone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "Last call: script.main_floor_vacuum_clean_zone x_max_cm="), object: label)
        XCTAssertEqual(XCTWaiter().wait(for: [zone], timeout: 10), .completed, label.label)
    }

    /// Errors show Stop and Dock; resumable shows Resume and Cancel; unavailable shows the reported map.
    func testScenarios() {
        var app = launch(Self.mainFloor, scenario: "error")
        XCTAssertTrue(app.buttons["vacuum.action.stop"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["vacuum.action.dock"].exists)
        app = launch(Self.mainFloor, scenario: "resumable")
        XCTAssertTrue(app.buttons["vacuum.action.resume"].waitForExistence(timeout: 10))
        app.buttons["vacuum.action.cancelResume"].tap()
        expectCall("vacuum.stop entity_id=vacuum.valetudo_exaltedsneakydeer", in: app)
        app = launch(Self.musicRoom, scenario: "unavailable")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "last reported")).firstMatch.waitForExistence(timeout: 10))
    }

    /// The Main Floor dock: Clean Mop Dock and Dry Mops send their scripts; the report opens room details.
    func testDockAndReport() {
        let app = launch(Self.mainFloor, tab: "more")
        let dock = app.buttons["vacuum.action.cleanDock"]
        XCTAssertTrue(dock.waitForExistence(timeout: 10))
        dock.tap()
        if app.alerts.firstMatch.waitForExistence(timeout: 2) { app.alerts.firstMatch.buttons.element(boundBy: 1).tap() }
        expectCall("script.main_floor_vacuum_mop_dock_clean", in: app)

        tab("Controls", in: app)
        let report = element("vacuum.report", in: app)
        reveal(report, in: app)
        report.tap()
        XCTAssertTrue(element("vacuum.outcome.living_room", in: app).waitForExistence(timeout: 10))
    }

    /// At AX5 every control stays reachable by scrolling.
    func testLargestTextKeepsControlsReachable() {
        let app = launch(Self.mainFloor, arguments: FentonHomeApp.ax5)
        reveal(app.buttons["vacuum.action.clean"], in: app)
        tab("Info", in: app)
        reveal(app.staticTexts["Main Filter"].firstMatch, in: app)
    }

    // MARK: - Audits

    private func audit(_ vacuum: String?, tab: String = "controls", scenario: String = "docked") throws {
        let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]
        for orientation in orientations {
            if orientation != .unknown { XCUIDevice.shared.orientation = orientation }
            let app = launch(vacuum, tab: tab, scenario: scenario)
            try FentonHomeApp.audit(app) { self.launch(vacuum, tab: tab, scenario: scenario, arguments: FentonHomeApp.ax5) }
        }
    }

    func testPagePassesAudit() throws { try audit(nil) }
    func testControlsPassAudit() throws { try audit(Self.mainFloor) }
    func testRoomsPassAudit() throws { try audit(Self.mainFloor, tab: "zones") }
    func testAutoCleanPassesAudit() throws { try audit(Self.mainFloor, tab: "autoClean") }
    func testMorePassesAudit() throws { try audit(Self.mainFloor, tab: "more") }
    func testInfoPassesAudit() throws { try audit(Self.musicRoom, tab: "info") }
    func testErrorPassesAudit() throws { try audit(Self.mainFloor, scenario: "error") }

    // MARK: - Screenshots

    /// The page and every tab in the current pose (iPad: both orientations), named `vacuums-<screen>-<orientation>`.
    func testCaptureVacuumScreens() {
        let shots: [(String?, String, String, String)] = [
            (nil, "controls", "docked", "page"),
            (Self.mainFloor, "controls", "docked", "controls"),
            (Self.mainFloor, "zones", "docked", "rooms"),
            (Self.mainFloor, "autoClean", "docked", "autoclean"),
            (Self.mainFloor, "more", "docked", "dock"),
            (Self.mainFloor, "info", "docked", "info"),
            (Self.mainFloor, "controls", "cleaning", "cleaning"),
            (Self.mainFloor, "controls", "error", "error"),
            (Self.musicRoom, "controls", "unavailable", "reported"),
        ]
        let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]
        for orientation in orientations {
            if orientation != .unknown { XCUIDevice.shared.orientation = orientation }
            let suffix = orientation == .landscapeLeft ? "landscape" : orientation == .portrait ? "portrait" : "current"
            for (vacuum, tab, scenario, name) in shots {
                _ = launch(vacuum, tab: tab, scenario: scenario, clean: true)
                keepScreenshot(XCUIApplication(), "vacuums-\(name)-\(suffix)")
            }
        }
    }
}
