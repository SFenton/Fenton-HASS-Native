import XCTest

/// Direction G's foundation in the debug gallery (`FENTON_GALLERY=direction-g`): status chips, tile faces, the
/// light dragger, modules, spinners, the primary button and a sheet with the bottom glass section bar. Names,
/// targets, actions, audits (including the rendered contrast check) and screenshots on iPhone, iPhone Duo and iPad
/// (`.agents/design/direction-g-plan.md`, Phase 1).
@MainActor
final class DirectionGJourneyTests: JourneyTestCase {
    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = FentonHomeApp.launchGallery("direction-g", arguments: arguments)
        XCTAssertTrue(app.buttons["g.chip.Lights"].waitForExistence(timeout: 10))
        return app
    }

    private func lastAction(_ app: XCUIApplication) -> String {
        app.staticTexts["gallery.lastCall"].label
    }

    /// Chips read their title and state, tiles read their state, and every control is at least 44 pt.
    func testChipsAndTilesAreNamedAndLargeEnough() {
        let app = launch()
        let lights = app.buttons["g.chip.Lights"]
        XCTAssertEqual(lights.label, "Lights, 3 On")
        assertTarget(lights)
        for id in ["g.tile.Office Lamp", "g.tile.Living Room Purifier", "g.tile.Garage Door", "g.tile.light"] {
            let tile = element(id, in: app)
            XCTAssertTrue(tile.exists, "\(id) missing")
            assertTarget(tile)
        }
        XCTAssertEqual(element("g.tile.Garage Door", in: app).value as? String, "Didn't Respond",
                       "An error tile reads its state, not On or Off")
        XCTAssertEqual(element("g.tile.light", in: app).value as? String, "60%")
    }

    /// Tapping a chip and a tile records their actions (the light's taps are ``testLightTogglesRepeatedly``).
    func testChipAndTileTapsAct() {
        let app = launch()
        app.buttons["g.chip.Climate"].tap()
        XCTAssertEqual(lastAction(app), "Last action: chip Climate")
        element("g.tile.Office Lamp", in: app).tap()
        XCTAssertEqual(lastAction(app), "Last action: tile Office Lamp")
    }

    /// The light toggles off and on repeatedly, its face swapping between the lit and off grounds each time.
    func testLightTogglesRepeatedly() {
        let app = launch()
        let light = element("g.tile.light", in: app)
        for expected in ["power false", "power true", "power false", "power true", "power false", "power true"] {
            light.tap()
            XCTAssertEqual(lastAction(app), "Last action: \(expected)")
        }
        XCTAssertEqual(light.value as? String, "100%")
    }

    /// Dragging the light tile sideways sets its brightness.
    func testDraggingTheLightSetsBrightness() {
        let app = launch()
        let tile = element("g.tile.light", in: app)
        let start = tile.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        let end = tile.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(lastAction(app).hasPrefix("Last action: brightness"), lastAction(app))
    }

    func testPagePassesAccessibilityAudit() throws {
        let app = launch()
        keepScreenshot(app, "direction-g-\(layout)")
        try FentonHomeApp.audit(app) { self.launch(arguments: FentonHomeApp.ax5) }
        // The modules, spinners and primary buttons, moved to the top so they are audited unscrolled.
        let lowerFirst = ["-directionGOrder", "lower"]
        let lower = launch(arguments: lowerFirst)
        keepScreenshot(lower, "direction-g-lower-\(layout)")
        try FentonHomeApp.audit(lower) { self.launch(arguments: lowerFirst + FentonHomeApp.ax5) }
    }

    /// The sheet's section bar is a segmented control along the bottom, and switching sections swaps the tiles.
    func testSheetSectionBarSitsAtTheBottomAndSwitches() throws {
        func open(_ app: XCUIApplication) -> XCUIApplication {
            let primary = app.buttons["g.primary"]
            for _ in 0..<6 where !primary.isHittable { app.swipeUp() }
            primary.tap()
            XCTAssertTrue(app.buttons["sheet.close"].waitForExistence(timeout: 5))
            sleep(1) // Let the sheet settle.
            return app
        }
        let app = open(launch())
        let tabs = app.segmentedControls["g.sheet.tabs"]
        XCTAssertTrue(tabs.exists)
        XCTAssertGreaterThan(tabs.frame.midY, app.windows.firstMatch.frame.midY, "The section bar sits in the bottom half")
        tabs.buttons["Apps"].tap()
        XCTAssertTrue(app.buttons["Netflix"].waitForExistence(timeout: 5))
        keepScreenshot(app, "direction-g-sheet-\(layout)")
        try FentonHomeApp.audit(app) { open(self.launch(arguments: FentonHomeApp.ax5)) }
    }
}
