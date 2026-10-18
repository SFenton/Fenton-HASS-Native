import XCTest

/// Motion (`.agents/design/motion.md`, `.agents/design/motion-components.md`): the Motion gallery toggles every component's state
/// and checks that its accessibility value changes, its targets stay 44 pt and its frame does not move (only colour animates);
/// the shell's tabs, pages and sheets behave as the rules say, with Reduce Motion off and on.
///
/// The gallery tests need no sign-in. The shell tests are signed in against the house but only navigate and read.
@MainActor
final class MotionJourneyTests: JourneyTestCase {
    /// The gallery's component ids (`MotionGallery.cases`); a case missing from the page fails `testGalleryListsEveryComponent`.
    static let componentIDs = [
        "glassTile", "glassTileLight", "glassTileError", "brightnessTile", "statusPill", "statusChip", "primaryButton",
        "selectableOptionRow", "filterOptionRow", "floatingActionBar", "choiceGrid", "weekdayPicker", "cameraControl", "dueLabel",
        "climateNotice", "lightingMode", "deviceStatusPill", "alarmMode", "dayPicker", "sprinklerRow", "sprinklerControllerRow",
        "vacationChecklistRow", "vacuumStatusChip",
    ]

    // MARK: - Helpers

    private func launch(reduceMotion: Bool) -> XCUIApplication {
        let app = FentonHomeApp.launchGallery(
            "motion", environment: FentonHomeApp.SystemSetting.environment(reduceMotion ? [.reduceMotion] : []))
        XCTAssertTrue(app.descendants(matching: .any)["motion.toggleAll"].waitForExistence(timeout: 20), "The motion gallery did not open")
        return app
    }

    /// Scrolls until `element` can be hit, down first and then back up (the page is as long as the gallery).
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<30 where !element.isHittable { scroll.swipeUp(velocity: .slow) }
        for _ in 0..<60 where !element.isHittable { scroll.swipeDown(velocity: .slow) }
        XCTAssertTrue(element.isHittable, "\(element) is not reachable")
    }

    private func waitForValue(_ element: XCUIElement, _ value: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value == %@", value)
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5)
        XCTAssertEqual(result, .completed, "\(element.identifier) is '\(String(describing: element.value))', expected '\(value)'", file: file, line: line)
    }

    private func assertSameFrame(_ before: CGRect, _ after: CGRect, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(before.origin.x, after.origin.x, accuracy: 0.5, "\(name) moved sideways", file: file, line: line)
        XCTAssertEqual(before.origin.y, after.origin.y, accuracy: 0.5, "\(name) moved", file: file, line: line)
        XCTAssertEqual(before.width, after.width, accuracy: 0.5, "\(name) changed width", file: file, line: line)
        XCTAssertEqual(before.height, after.height, accuracy: 0.5, "\(name) changed height", file: file, line: line)
    }

    /// Toggles one component: the value and the state text change, the frame does not, and every button in it is a 44 pt target.
    private func toggle(_ id: String, in app: XCUIApplication) {
        let component = app.descendants(matching: .any)["motion.component.\(id)"].firstMatch
        let button = app.buttons["motion.toggle.\(id)"]
        reveal(button, in: app)
        XCTAssertTrue(component.exists, id)
        waitForValue(component, "Off")
        let before = component.frame
        button.tap()
        waitForValue(component, "On")
        XCTAssertEqual(app.staticTexts["motion.state.\(id)"].label, "State: On", id)
        // The colour fades for up to 0.6 s; the frame must not move at any point, and certainly not at the end.
        assertSameFrame(before, component.frame, id)
        usleep(800_000)
        assertSameFrame(before, component.frame, id)
        assertTarget(button)
        for inner in component.buttons.allElementsBoundByIndex where inner.exists && inner.isHittable {
            // Pickers inside a component are system controls; their segments are not our targets.
            XCTAssertGreaterThanOrEqual(inner.frame.height, 43, "\(id): \(inner.label) is under 44 pt")
        }
        button.tap()
        waitForValue(component, "Off")
        assertSameFrame(before, component.frame, id)
    }

    // MARK: - Gallery

    func testGalleryListsEveryComponent() {
        let app = launch(reduceMotion: false)
        for id in Self.componentIDs {
            let toggle = app.buttons["motion.toggle.\(id)"]
            reveal(toggle, in: app)
            XCTAssertTrue(app.descendants(matching: .any)["motion.component.\(id)"].exists, "\(id) has no component")
        }
    }

    func testEveryComponentTogglesItsState() {
        let app = launch(reduceMotion: false)
        for id in Self.componentIDs { toggle(id, in: app) }
    }

    func testEveryComponentTogglesItsStateWithReduceMotion() {
        let app = launch(reduceMotion: true)
        for id in Self.componentIDs { toggle(id, in: app) }
    }

    func testToggleAllFlipsEveryComponentAndMovesNothing() {
        for reduceMotion in [false, true] {
            let app = launch(reduceMotion: reduceMotion)
            func component(_ id: String) -> XCUIElement { app.descendants(matching: .any)["motion.component.\(id)"].firstMatch }
            // Off-screen components are not in the accessibility tree, so each is scrolled to before it is read, down the page, up
            // it, and down again. Scrolling moves positions, so the sizes are what must hold still.
            var sizes: [String: CGSize] = [:]
            for id in Self.componentIDs {
                reveal(app.buttons["motion.toggle.\(id)"], in: app)
                sizes[id] = component(id).frame.size
            }
            let all = app.buttons["motion.toggleAll"]
            XCTAssertTrue(all.isHittable, "Toggle all is not always in reach")
            all.tap()
            for id in Self.componentIDs.reversed() {
                reveal(app.buttons["motion.toggle.\(id)"], in: app)
                waitForValue(component(id), "On")
                XCTAssertEqual(component(id).frame.size.width, sizes[id]?.width ?? 0, accuracy: 0.5, "\(id) changed width")
                XCTAssertEqual(component(id).frame.size.height, sizes[id]?.height ?? 0, accuracy: 0.5, "\(id) changed height")
            }
            all.tap()
            for id in Self.componentIDs {
                reveal(app.buttons["motion.toggle.\(id)"], in: app)
                waitForValue(component(id), "Off")
            }
        }
    }

    func testGalleryPassesTheAccessibilityAudit() throws {
        let app = launch(reduceMotion: false)
        app.buttons["motion.toggleAll"].tap()
        sleep(1)
        try FentonHomeApp.audit(app)
    }

    // MARK: - Shell (signed in; navigation only)

    /// Switching tabs is a cut: the destination's content is there as soon as the tap settles, and each tab keeps its own place.
    func testTabSwitchIsACutAndKeepsEachTabsPlace() throws {
        let app = try FentonHomeApp.launchSignedIn()
        guard app.tabBars.buttons["Climate"].exists || app.toolbars.buttons["Climate"].exists else {
            throw XCTSkip("This window navigates with the flyout, not tabs")
        }
        for (section, title, scroll) in [("climate", "Climate", "climate.scroll"), ("home", "Home", "home.scroll")] {
            openSection(section, title: title, in: app)
            XCTAssertTrue(element(scroll, in: app).exists, "\(title) content was not there as soon as the switch settled")
        }
    }

    /// The second tap on the selected tab pops to the root; at the root the next tap scrolls to the top.
    func testSelectedTabPopsThenScrollsToTop() throws {
        let app = try FentonHomeApp.launchSignedIn()
        let settings = app.tabBars.buttons["Settings"].exists ? app.tabBars.buttons["Settings"] : app.toolbars.buttons["Settings"]
        guard settings.exists else { throw XCTSkip("This window navigates with the flyout, not tabs") }
        settings.tap()
        let list = element("settings.list", in: app)
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        let performance = app.buttons["settings.performance"]
        for _ in 0..<8 where !performance.isHittable { app.swipeUp() }
        XCTAssertTrue(performance.exists, "The Performance row is not in the list")
        performance.tap()
        XCTAssertTrue(element("performance.screen", in: app).waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(list.waitForExistence(timeout: 10), "The first re-tap did not pop to the root")
        XCTAssertFalse(element("performance.screen", in: app).exists)
        // Scrolled down, the next re-tap scrolls back to the top.
        for _ in 0..<3 { app.swipeUp() }
        let top = app.buttons["settings.vacation"]
        XCTAssertFalse(top.isHittable, "The list did not scroll")
        settings.tap()
        XCTAssertTrue(top.wait(for: \.isHittable, toEqual: true, timeout: 5), "The second re-tap did not scroll to the top")
    }

    /// A sheet and a pushed room page still work with Reduce Motion on.
    func testSheetAndPushWorkWithReduceMotion() throws {
        let app = try FentonHomeApp.launchSignedIn(environment: FentonHomeApp.SystemSetting.environment([.reduceMotion]))
        app.buttons["home.chip.lights"].tap()
        let rooms = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'overview.lights.room.'"))
        XCTAssertTrue(rooms.firstMatch.waitForExistence(timeout: 10))
        let room = rooms.firstMatch
        XCTAssertTrue(room.wait(for: \.isHittable, toEqual: true, timeout: 5))
        room.tap()
        XCTAssertTrue(element("overview.detail.subtitle", in: app).waitForExistence(timeout: 10), "The room page did not open")
        let back = app.buttons["BackButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(rooms.firstMatch.waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["home.chip.lights"].waitForExistence(timeout: 5))
    }

    /// The room tile zooms into its page on iOS 18 and later, and pushes before it; either way the tile opens the page and Back
    /// returns to the tile's sheet.
    func testRoomTileOpensItsPage() throws {
        let app = try FentonHomeApp.launchSignedIn()
        app.buttons["home.chip.lights"].tap()
        let room = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'overview.lights.room.'")).firstMatch
        XCTAssertTrue(room.waitForExistence(timeout: 10))
        XCTAssertTrue(room.wait(for: \.isHittable, toEqual: true, timeout: 5))
        let identifier = room.identifier
        room.tap()
        XCTAssertTrue(element("overview.detail.subtitle", in: app).waitForExistence(timeout: 10))
        app.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
    }
}
