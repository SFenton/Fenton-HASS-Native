import XCTest

/// The Media, Custom Lights and Sprinklers pages in the debug gallery (fixture state, recording service caller;
/// nothing reaches the house): what each control sends, sheets and pushes, accessibility audits with the AX5
/// relaunch, and screenshots on iPhone, iPhone Duo and iPad. Specs: `.agents/pages/{media,custom-lights,sprinklers}`.
@MainActor
final class HomePagesJourneyTests: XCTestCase {
    /// The next `launch` adds the AX5 text size (the audit's relaunch).
    private var nextLaunchIsAX5 = false

    override func setUp() { continueAfterFailure = false }
    override func tearDown() {
        MainActor.assumeIsolated {
            if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
        }
    }

    // MARK: - Helpers

    private func launch(_ page: String, _ environment: [String: String] = [:], arguments: [String] = [],
                        waitFor id: String) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = page
        app.launchEnvironment["FENTON_GALLERY_OFFLINE"] = "1"
        app.launchEnvironment.merge(environment) { _, new in new }
        app.launchArguments += arguments
        if nextLaunchIsAX5 {
            app.launchArguments += FentonHomeApp.ax5
            nextLaunchIsAX5 = false
        }
        app.launch()
        let ready = element(id, in: app)
        XCTAssertTrue(ready.waitForExistence(timeout: 30), "\(id) did not appear")
        XCTAssertTrue(ready.wait(for: \.isHittable, toEqual: true, timeout: 10), "\(id) not reachable")
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

    /// Scrolls the page in short drags until `element` is hittable (full swipes overshoot at AX5 and on the Duo).
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        for _ in 0..<20 where !element.isHittable {
            let above = element.exists && element.frame.midY < window.midY
            var x = window.midX
            if FentonHomeApp.family == .iPhoneDuo { x = min(x, window.maxX - 96) }
            let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: -window.minX, dy: -window.minY))
            let from = origin.withOffset(CGVector(dx: x, dy: window.minY + window.height * (above ? 0.35 : 0.65)))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: above ? 220 : -220)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(element.isHittable, "\(element) never came into view")
    }

    private func tap(_ id: String, in app: XCUIApplication) {
        let target = element(id, in: app)
        XCTAssertTrue(target.waitForExistence(timeout: 10), "\(id) missing")
        reveal(target, in: app)
        target.tap()
    }

    /// Flips a `Form` toggle: XCUITest taps a row's middle, which lands on its label and leaves the switch alone.
    private func flip(_ id: String, in app: XCUIApplication) {
        let row = app.switches[id].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "\(id) missing")
        reveal(row, in: app)
        let knob = row.switches.firstMatch
        if knob.exists { knob.tap() } else { row.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
    }

    private func assertTarget(_ id: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(id, in: app)
        XCTAssertGreaterThanOrEqual(target.frame.width, 43, id, file: file, line: line)
        XCTAssertGreaterThanOrEqual(target.frame.height, 43, id, file: file, line: line)
    }

    /// Audits (with the AX5 relaunch) and keeps a screenshot, in portrait and, on iPad, landscape too.
    private func auditAndCapture(_ name: String, relaunch: @escaping () -> XCUIApplication) throws {
        var app = relaunch()
        for orientation in FentonHomeApp.family == .iPad ? ["portrait", "landscape"] : ["portrait"] {
            if orientation == "landscape" {
                XCUIDevice.shared.orientation = .landscapeLeft
                sleep(1)
            }
            try FentonHomeApp.audit(app) {
                self.nextLaunchIsAX5 = true
                return relaunch()
            }
            app = relaunch()
            keepScreenshot(app, "\(name)-\(orientation)")
        }
    }

    // MARK: - Media

    func testMediaTilesSendTheirCommandsAndOpenRemotes() {
        let app = launch("media-page", waitFor: "media.card.living-room.living-room-shield")
        let xbox = element("media.card.music-room.xbox", in: app)
        XCTAssertEqual(xbox.value as? String, "Off")
        tap("media.card.music-room.xbox", in: app)
        expectCall("script.music_room_xbox", in: app)
        let shownOn = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'On'"), object: xbox)
        XCTAssertEqual(XCTWaiter().wait(for: [shownOn], timeout: 5), .completed, "The source shows on at once")
        tap("media.card.theater-room.nintendo-switch", in: app)
        expectCall("script.theater_room_nintendo_switch", in: app)
        for id in ["media.card.living-room.living-room-shield", "media.card.music-room.server", "media.card.theater-room.theater-shield"] {
            assertTarget(id, in: app)
        }
        tap("media.card.living-room.living-room-shield", in: app)
        XCTAssertTrue(element("remote.power", in: app).waitForExistence(timeout: 10), "The Living Room remote opened")
    }

    func testMusicRoomRemoteSharesTheSourceWithThePage() {
        let app = launch("media-page", ["FENTON_GALLERY_REMOTE": "music-room-remote", "FENTON_GALLERY_TAB": "devices"],
                         waitFor: "remote.power")
        XCTAssertTrue(app.navigationBars["Music Room Remote"].exists)
    }

    func testMediaAuditsAndScreenshots() throws {
        try auditAndCapture("media") { self.launch("media-page", ["FENTON_GALLERY_CLEAN": "1"], waitFor: "media.card.living-room.living-room-shield") }
    }

    // MARK: - Custom Lights

    func testManualControlAndModes() {
        let app = launch("custom-lights", waitFor: "customLights.manual")
        tap("customLights.mode", in: app)
        tap("customLights.mode.Seahawks", in: app)
        expectCall("input_select.select_option entity_id=input_select.front_yard_custom_lights option=Seahawks", in: app)
        XCTAssertFalse(element("customLights.resetAll", in: app).waitForExistence(timeout: 3), "Lights show only in Custom mode")
        tap("customLights.manual", in: app)
        expectCall("input_boolean.turn_off entity_id=input_boolean.manually_control_front_yard_lights", in: app)
        XCTAssertFalse(element("customLights.mode", in: app).waitForExistence(timeout: 3), "Mode hides without manual control")
    }

    func testLightTilesOpenTheirSheet() {
        let app = launch("custom-lights", waitFor: "customLights.manual")
        tap("customLights.light.light.front_door_bollard_1", in: app)
        XCTAssertTrue(element("customLight.brightness", in: app).waitForExistence(timeout: 10), "Light sheet opened")
        // Copy a color before any reset: the gallery echoes a reset as every light at 2000 K.
        tap("customLight.other.light.front_door_exterior_left_light", in: app)
        expectCall("light.turn_on entity_id=light.front_door_bollard_1 rgb_color=[0,255,0]", in: app)
        tap("customLight.reset", in: app)
        expectCall("light.turn_on brightness=255 color_temp_kelvin=2000 entity_id=light.front_door_bollard_1 transition=1", in: app)
        tap("customLight.brightness", in: app)
        expectCall("light.turn_off entity_id=light.front_door_bollard_1", in: app)
        app.navigationBars.buttons["Done"].firstMatch.tap()
        tap("customLights.resetAll", in: app)
        expectCall("light.turn_on brightness=255 color_temp_kelvin=2000 entity_id=light.front_yard_lights transition=1", in: app)
    }

    /// A sideways drag on a tile sets brightness; a vertical one scrolls the page (it used to be swallowed).
    func testTileDragSetsBrightnessAndVerticalDragScrolls() {
        let app = launch("custom-lights", waitFor: "customLights.manual")
        let tile = element("customLights.light.light.front_door_bollard_1", in: app)
        reveal(tile, in: app)
        let start = tile.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: tile.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)),
                    withVelocity: .slow, thenHoldForDuration: 0.1)
        let label = app.staticTexts["gallery.lastCall"].firstMatch
        let parts = ["light.turn_on", "brightness_pct=", "entity_id=light.front_door_bollard_1"]
        let predicate = NSPredicate(format: parts.map { _ in "label CONTAINS %@" }.joined(separator: " AND "), argumentArray: parts)
        let sent = XCTNSPredicateExpectation(predicate: predicate, object: label)
        XCTAssertEqual(XCTWaiter().wait(for: [sent], timeout: 10), .completed, "Last call was '\(label.label)'")

        // Only where the page is taller than the window (an iPad in landscape shows it all).
        guard element("customLights.resetAll", in: app).frame.maxY > app.windows.firstMatch.frame.maxY else { return }
        let manual = element("customLights.manual", in: app)
        let before = manual.frame.minY
        let onTile = element("customLights.light.light.front_door_exterior_left_light", in: app)
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        onTile.press(forDuration: 0.05, thenDragTo: onTile.withOffset(CGVector(dx: 0, dy: -200)), withVelocity: .slow,
                     thenHoldForDuration: 0.2)
        XCTAssertLessThan(manual.frame.minY, before - 40, "A vertical drag starting on a tile scrolls the page")
    }

    func testCustomLightsAuditsAndScreenshots() throws {
        try auditAndCapture("custom-lights") { self.launch("custom-lights", ["FENTON_GALLERY_CLEAN": "1"], waitFor: "customLights.manual") }
        try auditAndCapture("custom-lights-modes") {
            self.launch("custom-lights", ["FENTON_GALLERY_CLEAN": "1", "FENTON_GALLERY_PICKER": "1"], waitFor: "customLights.mode.Custom")
        }
        try auditAndCapture("custom-light-sheet") {
            self.launch("custom-lights", ["FENTON_GALLERY_CLEAN": "1", "FENTON_GALLERY_LIGHT": "light.front_door_bollard_1"],
                        waitFor: "customLight.brightness")
        }
    }

    // MARK: - Sprinklers

    func testControllerSheetSettingsAndWatering() {
        let app = launch("sprinklers", waitFor: "sprinklers.controller.frontYard")
        tap("sprinklers.controller.frontYard", in: app)
        XCTAssertTrue(element("sprinkler.overview", in: app).waitForExistence(timeout: 10))
        flip("sprinkler.rainDelay", in: app)
        expectCall("switch.turn_on entity_id=switch.front_yard_rain_delay", in: app)
        tap("sprinkler.zone.0", in: app)
        tap("sprinkler.startWatering", in: app)
        expectCall("bhyve.start_watering entity_id=valve.front_yard_zone minutes=15", in: app)
        XCTAssertTrue(element("sprinkler.stop", in: app).wait(for: \.isEnabled, toEqual: true, timeout: 10), "Back on the overview, watering")
        tap("sprinkler.stop", in: app)
        expectCall("bhyve.stop_watering entity_id=valve.front_yard_zone", in: app)
    }

    /// While one zone waters, another zone's row still opens and says why it can't start.
    func testBusyControllerExplainsWhyAZoneCannotStart() {
        let app = launch("sprinklers", ["FENTON_GALLERY_SPRINKLER": "backyard"], waitFor: "sprinkler.overview")
        tap("sprinkler.zone.0", in: app)
        XCTAssertTrue(element("sprinkler.waterBlocked", in: app).waitForExistence(timeout: 10), "The reason shows")
        XCTAssertFalse(element("sprinkler.startWatering", in: app).isEnabled, "Start waits for the running zone")
    }

    func testScheduleEditorSavesTheProgram() {
        let app = launch("sprinklers", ["FENTON_GALLERY_SPRINKLER": "frontYard", "FENTON_GALLERY_DETAIL": "schedule-0"],
                         waitFor: "sprinkler.schedule.apply")
        let sunday = element("sprinkler.schedule.day.0", in: app)
        XCTAssertFalse(sunday.isSelected)
        sunday.tap()
        XCTAssertTrue(sunday.isSelected)
        assertTarget("sprinkler.schedule.day.0", in: app)
        tap("sprinkler.schedule.apply", in: app)
        // `frequency` prints as a dictionary, whose key order is not fixed: check its parts.
        let label = app.staticTexts["gallery.lastCall"].firstMatch
        let parts = ["bhyve.update_program budget=100 entity_id=switch.front_yard_front_yard_program", "[0, 1, 3, 5]",
                     "start_times=[06:30]"]
        let predicate = NSPredicate(format: parts.map { _ in "label CONTAINS %@" }.joined(separator: " AND "), argumentArray: parts)
        let saved = XCTNSPredicateExpectation(predicate: predicate, object: label)
        XCTAssertEqual(XCTWaiter().wait(for: [saved], timeout: 10), .completed, "Last call was '\(label.label)'")
        XCTAssertTrue(element("sprinkler.overview", in: app).waitForExistence(timeout: 10), "Apply returns to the overview")
    }

    func testSprinklersAuditsAndScreenshots() throws {
        try auditAndCapture("sprinklers") { self.launch("sprinklers", ["FENTON_GALLERY_CLEAN": "1"], waitFor: "sprinklers.controller.frontYard") }
        try auditAndCapture("sprinkler-controller") {
            self.launch("sprinklers", ["FENTON_GALLERY_CLEAN": "1", "FENTON_GALLERY_SPRINKLER": "backyard"], waitFor: "sprinkler.overview")
        }
        try auditAndCapture("sprinkler-water") {
            self.launch("sprinklers", ["FENTON_GALLERY_CLEAN": "1", "FENTON_GALLERY_SPRINKLER": "frontYard", "FENTON_GALLERY_DETAIL": "water-0"],
                        waitFor: "sprinkler.startWatering")
        }
        try auditAndCapture("sprinkler-schedule") {
            self.launch("sprinklers", ["FENTON_GALLERY_CLEAN": "1", "FENTON_GALLERY_SPRINKLER": "frontYard", "FENTON_GALLERY_DETAIL": "schedule-0"],
                        waitFor: "sprinkler.schedule.apply")
        }
    }

}
