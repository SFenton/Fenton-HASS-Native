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
        // On phones the tab picker sits below the map and status, so the sheet's Done button proves it has presented.
        let settled = vacuum == nil ? anchor : app.navigationBars.buttons["Done"].firstMatch
        XCTAssertTrue(settled.wait(for: \.isHittable, toEqual: true, timeout: 10), "Still presenting")
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
        // The gallery's Last call bar floats over the bottom of the sheet; a control under it is not reachable yet.
        let bar = app.staticTexts["gallery.lastCall"].firstMatch
        func reachable() -> Bool {
            guard element.isHittable else { return false }
            // The bar's background starts 4 pt above its text; a control ending there is fully visible.
            return !bar.exists || element.frame.maxY <= bar.frame.minY + 1 || element.frame.minY >= bar.frame.maxY
        }
        for _ in 0..<24 where !reachable() {
            let above = element.exists ? element.frame.midY < window.midY : !down
            var x = element.exists && element.frame.midX > 0 ? element.frame.midX : window.midX
            if FentonHomeApp.family == .iPhoneDuo { x = min(x, window.maxX - 96) }
            let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: -window.minX, dy: -window.minY))
            // Start on the control itself when it is on screen (e.g. under the Last call bar), kept clear of the edges.
            var y = window.minY + window.height * (above ? 0.35 : 0.65)
            if element.exists, window.intersects(element.frame) {
                y = min(max(element.frame.midY, window.minY + 150), window.maxY - 150)
            } else if element.exists {
                // Off screen: drag near the leading edge of the narrowest scroll view over it (the sheet's column, not
                // the page behind), clear of the map in the middle and of the back-swipe edge.
                let id = element.identifier
                let holders = id.isEmpty ? [] : app.scrollViews.containing(.any, identifier: id).allElementsBoundByIndex
                let column = holders.map(\.frame).filter { $0.height > 200 }.min { $0.width < $1.width }
                if let column { x = max(column.minX, window.minX) + 24 }
            }
            let from = origin.withOffset(CGVector(dx: x, dy: y))
            let to = from.withOffset(CGVector(dx: 0, dy: above ? 220 : -220))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(reachable(), "\(element) never came into view")
        // Bring a control low on the screen up toward the middle, clear of anything floating at the bottom.
        if element.frame.maxY > window.maxY - window.height * 0.3 {
            let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: -window.minX, dy: -window.minY))
            var x = element.frame.midX
            if FentonHomeApp.family == .iPhoneDuo { x = min(x, window.maxX - 96) }
            let from = origin.withOffset(CGVector(dx: x, dy: window.minY + window.height * 0.6))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: window.midY - element.frame.midY)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
    }

    /// Drags the tab picker to the top of the sheet, as a reader would, so the tab's content is on screen.
    private func scrollToTabContent(in app: XCUIApplication) {
        let picker = element("vacuum.tabs", in: app)
        guard picker.exists, element("vacuum.layout.singleColumn", in: app).exists else { return }
        // Never start a drag at the bottom edge: that is the Home gesture and backgrounds the app.
        if !picker.isHittable { reveal(picker, in: app) }
        let window = app.windows.firstMatch.frame
        let top = window.minY + window.height * 0.18
        guard picker.frame.minY > top + 40 else { return }
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: -window.minX, dy: -window.minY))
        let x = FentonHomeApp.family == .iPhoneDuo ? min(picker.frame.midX, window.maxX - 96) : picker.frame.midX
        let from = origin.withOffset(CGVector(dx: x, dy: picker.frame.minY - 8))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: top - picker.frame.minY)),
                   withVelocity: .slow, thenHoldForDuration: 0.4)
        // Let the scroll settle: a frame captured mid-deceleration samples text at stale positions.
        var last = picker.frame
        for _ in 0..<10 {
            usleep(500_000)
            let now = picker.frame
            if now == last { break }
            last = now
        }
    }

    private func assertTarget(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(element.frame.width, 43, element.label, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 43, element.label, file: file, line: line)
    }

    /// Picks a tab from the segmented control, or from its menu at accessibility sizes.
    private func tab(_ title: String, in app: XCUIApplication) {
        let picker = element("vacuum.tabs", in: app)
        reveal(picker, in: app, down: picker.exists && picker.frame.minY > app.windows.firstMatch.frame.midY)
        // A picker scrolled up under the navigation bar is "hittable" but taps land on the bar: pull it below.
        let window = app.windows.firstMatch.frame
        let barBottom = app.navigationBars.allElementsBoundByIndex.map(\.frame).filter { $0.intersects(window) }.map(\.maxY).max()
            ?? window.minY
        if picker.frame.minY < barBottom + 8 {
            let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: -window.minX, dy: -window.minY))
            let from = origin.withOffset(CGVector(dx: picker.frame.midX, dy: window.midY))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: barBottom + 80 - picker.frame.minY)),
                       withVelocity: .slow, thenHoldForDuration: 0.4)
        }
        let segment = picker.buttons[title].firstMatch
        if segment.exists {
            segment.tap()
        } else {
            // The menu's rows read as buttons or as menu items depending on the layout; under load the first tap
            // can land while the picker is still settling, so open the menu again if nothing appeared.
            let button = app.buttons[title].firstMatch, menuItem = app.menuItems[title].firstMatch
            var shown = false
            for _ in 0..<2 where !shown {
                picker.tap()
                shown = button.waitForExistence(timeout: 5) || menuItem.waitForExistence(timeout: 2)
            }
            XCTAssertTrue(shown, "No \(title) menu item")
            (button.exists ? button : menuItem).tap()
        }
    }

    // MARK: - Page

    /// Tiles name each robot and its state; the pause tile is a switch; tapping a robot opens its sheet.
    func testPageTilesAndAutoClean() {
        let app = launch()
        let tile = element("vacuums.tile.\(Self.mainFloor)", in: app)
        XCTAssertTrue(tile.label.contains("Main Floor"), tile.label)
        assertTarget(tile)
        let pause = element("vacuums.autoClean.switch.main_floor_vacuum_coordinator_pause", in: app)
        reveal(pause, in: app)
        XCTAssertEqual(pause.value as? String, "On", "GlassTile toggles read On/Off (entity-tile pattern)")
        pause.tap()
        expectCall("switch.turn_on entity_id=switch.main_floor_vacuum_coordinator_pause", in: app)
        let paused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Off"), object: pause)
        XCTAssertEqual(XCTWaiter().wait(for: [paused], timeout: 10), .completed, "Pause tile value is \(pause.value ?? "nil")")

        reveal(tile, in: app, down: false)
        tile.tap()
        XCTAssertTrue(element("vacuum.tabs", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Main Floor Robot Vacuum"].exists)
    }

    /// Splits only where allowed: unfolded Duo landscape and iPad landscape. Named to sort last: on the Duo the
    /// runner has restarted during this test's tear-down (folded and unfolded landscape, 2026-10-11), and a restart
    /// returns the Duo to folded, which would put every later test in the wrong pose.
    func testSplitFollowsThePose() {
        if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .landscapeLeft }
        let app = launch()
        let split = element("vacuums.layout.split", in: app).exists
        let window = app.windows.firstMatch.frame
        switch FentonHomeApp.family {
        case .iPad: XCTAssertTrue(split, "iPad landscape splits")
        case .iPhone: XCTAssertFalse(split, "iPhone never splits")
        case .iPhoneDuo: XCTAssertEqual(split, window.width > window.height && window.width > 700, "Duo window \(window.size)")
        }
    }

    // MARK: - Sheet

    /// Rooms toggle with order badges, setting the mode; Clean sends the selected-segments script.
    func testRoomsAndClean() {
        let app = launch(Self.mainFloor)
        tab("Rooms", in: app)
        // Rooms are toggles (switch role), read as On/Off.
        let office = element("vacuum.room.input_boolean.roborock_office_toggle", in: app)
        XCTAssertTrue(office.waitForExistence(timeout: 10))
        reveal(office, in: app)
        assertTarget(office)
        XCTAssertEqual(office.value as? String, "Off")
        office.tap()
        let on = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "On"), object: office)
        XCTAssertEqual(XCTWaiter().wait(for: [on], timeout: 5), .completed, "Office is \(office.value ?? "nil")")
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
        // The fixture has rooms selected, so Area asks before clearing them.
        let confirm = app.buttons["Switch to Area"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "No Switch to Area confirmation")
        confirm.tap()
        // Area (after confirming away from the selected rooms) opens the editor directly.
        let draw = app.buttons["vacuum.area.draw"]
        XCTAssertTrue(draw.waitForExistence(timeout: 10), "Area did not open the editor")
        // Draw, then drag across the map; the map reads the new size back.
        if !draw.isSelected { draw.tap() }
        let map = element("vacuum.area.map", in: app)
        XCTAssertEqual(map.value as? String, "No area selected")
        let start = map.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35))
        start.press(forDuration: 0.1, thenDragTo: map.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)))
        let drawn = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "×"), object: map)
        XCTAssertEqual(XCTWaiter().wait(for: [drawn], timeout: 10), .completed, "Map value is \(map.value ?? "nil")")
        // Scroll from below the map: a drag on the map moves the area instead of the page.
        let use = app.buttons["vacuum.area.use"]
        let window = app.windows.firstMatch.frame
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: -window.minX, dy: -window.minY))
        for _ in 0..<8 where !use.isHittable {
            let y = max(map.frame.maxY + 24, window.minY + window.height * 0.6)
            guard y < window.maxY - 120 else { break } // No room below the map: let XCTest scroll it into view.
            let from = origin.withOffset(CGVector(dx: window.midX, dy: y))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -200)), withVelocity: .slow, thenHoldForDuration: 0.3)
        }
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
        let cancel = app.buttons["vacuum.action.cancelResume"]
        reveal(cancel, in: app)
        cancel.tap()
        expectCall("vacuum.stop entity_id=vacuum.valetudo_exaltedsneakydeer", in: app)
        app = launch(Self.musicRoom, scenario: "unavailable")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "last reported")).firstMatch.waitForExistence(timeout: 10))
    }

    /// The Main Floor dock: Clean Mop Dock and Dry Mops send their scripts; the report opens room details.
    func testDockAndReport() {
        let app = launch(Self.mainFloor, tab: "more")
        let dock = app.buttons["vacuum.action.cleanDock"]
        XCTAssertTrue(dock.waitForExistence(timeout: 10))
        reveal(dock, in: app)
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
            // Clean gallery: the debug Last call bar is not product UI, and text half under it can't be judged.
            let app = launch(vacuum, tab: tab, scenario: scenario, clean: true)
            if tab != "controls" { scrollToTabContent(in: app) }
            try FentonHomeApp.audit(app) { self.launch(vacuum, tab: tab, scenario: scenario, clean: true, arguments: FentonHomeApp.ax5) }
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
                let app = launch(vacuum, tab: tab, scenario: scenario, clean: true)
                if vacuum != nil && tab != "controls" { scrollToTabContent(in: app) }
                keepScreenshot(XCUIApplication(), "vacuums-\(name)-\(suffix)")
            }
        }
    }
}
