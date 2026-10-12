import XCTest

/// The Master Bedroom wake light and bed sides in the debug gallery (fixture state, a recorder that answers like
/// Home Assistant; nothing reaches the house): service calls, prompts, layout per pose, accessibility audits and
/// screenshots on iPhone, iPhone Duo and iPad (`.agents/patterns/bedroom-devices.md`).
@MainActor
final class BedroomJourneyTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    override func tearDown() {
        MainActor.assumeIsolated {
            if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
        }
    }

    // MARK: - Helpers

    private func launch(sheet: String? = nil, tab: String? = nil, scenario: String = "default", clean: Bool = false,
                        arguments: [String] = []) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "bedroom"
        app.launchEnvironment["FENTON_GALLERY_SCENARIO"] = scenario
        if let sheet { app.launchEnvironment["FENTON_GALLERY_SHEET"] = sheet }
        if let tab { app.launchEnvironment["FENTON_GALLERY_TAB"] = tab }
        if clean { app.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1" }
        app.launchArguments += arguments
        app.launch()
        let anchor = element(sheet == nil ? "tile.wakeLight" : sheet == "wake-light" ? "wake.tabs" : "bed.hint", in: app)
        XCTAssertTrue(anchor.waitForExistence(timeout: 30), "Bedroom gallery did not open \(sheet ?? "tiles")")
        sleep(1) // Mid-animation frames fail contrast and clipping.
        return app
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func expectCall(startingWith prefix: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let label = app.staticTexts["gallery.lastCall"].firstMatch
        let predicate = NSPredicate(format: "label BEGINSWITH %@", "Last call: \(prefix)")
        let matched = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: label)], timeout: 10) == .completed
        XCTAssertTrue(matched, "Last call was '\(label.label)'", file: file, line: line)
    }

    private func expectCall(containing text: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let label = app.staticTexts["gallery.lastCall"].firstMatch
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let matched = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: label)], timeout: 10) == .completed
        XCTAssertTrue(matched, "Last call was '\(label.label)'", file: file, line: line)
    }

    /// Scrolls in short drags until `element` is hittable (see `MediaRemoteJourneyTests.reveal`).
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        for _ in 0..<24 where !element.isHittable {
            let above = element.exists ? element.frame.midY < window.midY : false
            var x = element.exists && element.frame.midX > 0 ? element.frame.midX : window.midX
            if FentonHomeApp.family == .iPhoneDuo { x = min(x, window.maxX - 96) }
            // Keep clear of the dial: drag along the column's leading edge.
            x = max(window.minX + 24, min(x, window.minX + 40))
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

    private func selectTab(_ title: String, in app: XCUIApplication) {
        let segmented = app.segmentedControls.firstMatch
        if segmented.exists { segmented.buttons[title].tap() } else { app.buttons[title].firstMatch.tap() }
    }

    /// The confirmation dialog's "Turn Off" action; the power button itself is also labelled "Turn Off".
    private func turnOffConfirmation(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Turn Off", "bed.power")).firstMatch
    }

    private func assertTarget(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(element.frame.width, 43, element.label, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 43, element.label, file: file, line: line)
    }

    // MARK: - Tiles

    func testTilesOpenTheirSheets() {
        let app = launch()
        let wake = element("tile.wakeLight", in: app)
        XCTAssertEqual(wake.label, "Wake-Light Alarms")
        XCTAssertTrue((wake.value as? String)?.hasPrefix("Next Alarm:") == true, "\(String(describing: wake.value))")
        let bed = element("tile.bed.stephens-bed", in: app)
        XCTAssertEqual(bed.value as? String, "Heating • +3")
        assertTarget(bed)
        bed.tap()
        XCTAssertTrue(element("bed.power", in: app).waitForExistence(timeout: 10))
    }

    // MARK: - Bed side

    /// The dial handle reads the signed level; turning off asks first and sends the broker script.
    func testPowerAsksBeforeTurningOff() {
        let app = launch(sheet: "stephens-bed")
        let handle = element("thermostatDial.handle.target", in: app)
        XCTAssertEqual(handle.label, "Stephen's Bed target level")
        XCTAssertEqual(handle.value as? String, "+3")
        let power = element("bed.power", in: app)
        assertTarget(power)
        power.tap()
        let confirm = turnOffConfirmation(in: app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Turning off asks first")
        confirm.tap()
        expectCall(startingWith: "script.sleepypod_hot_flash_broker action=power_off side=left", in: app)
        XCTAssertTrue(element("bed.subtitle", in: app).wait(for: \.label, toEqual: "Off", timeout: 5))
        tap("bed.power", in: app)
        expectCall(startingWith: "script.sleepypod_hot_flash_broker action=power_heat", in: app)
    }

    /// Stepping the running stage sets tonight's target and asks Tonight or All Nights.
    func testRunningStageAsksForScope() {
        let app = launch(sheet: "stephens-bed")
        tap("bed.stage.asleep.down", in: app)
        expectCall(startingWith: "script.sleepypod_stephen_temperature_tonight level=2", in: app)
        let allNights = element("bed.scope.allNights", in: app)
        XCTAssertTrue(allNights.waitForExistence(timeout: 5), "Scope prompt opens")
        allNights.tap()
        expectCall(containing: "entity_id=input_number.eight_sleep_stephen_asleep_level", in: app)
    }

    /// Other stages send the level and rewrite the schedule.
    func testOtherStagesPublishTheSchedule() {
        let app = launch(sheet: "stephens-bed")
        let stage = element("bed.stage.bedtime", in: app)
        reveal(stage, in: app)
        XCTAssertEqual(stage.value as? String, "+4")
        tap("bed.stage.bedtime.up", in: app)
        expectCall(startingWith: "mqtt.publish payload=", in: app)
        XCTAssertEqual(element("bed.stage.bedtime", in: app).value as? String, "+5")
    }

    func testRingingAlarmCanBeSnoozedAndStopped() {
        let app = launch(sheet: "stephens-bed", scenario: "ringing")
        XCTAssertTrue(element("bed.alarm.active", in: app).exists)
        tap("bed.alarm.snooze", in: app)
        expectCall(startingWith: "button.press entity_id=button.master_bedroom_sleepypod_eight_pod_left_alarm_snooze", in: app)
        tap("bed.alarm.stop", in: app)
        expectCall(startingWith: "button.press entity_id=button.master_bedroom_sleepypod_eight_pod_left_alarm_stop", in: app)
        XCTAssertTrue(element("bed.alarm.active", in: app).waitForNonExistence(timeout: 5))
    }

    func testHotFlashStartsAndCancels() {
        let app = launch(sheet: "stephens-bed", tab: "special-modes")
        tap("bed.hotFlash", in: app)
        expectCall(startingWith: "input_button.press entity_id=input_button.eight_sleep_stephen_hot_flash", in: app)
        tap("bed.hotFlash.cancel", in: app)
        expectCall(startingWith: "input_button.press entity_id=input_button.eight_sleep_stephen_cancel_hot_flash", in: app)
    }

    /// Adding a bed alarm links the wake light, then publishes the side's alarms.
    func testAddingABedAlarm() {
        let app = launch(sheet: "stephs-bed", tab: "alarms")
        tap("bed.alarms.add", in: app)
        tap("bed.editor.day.sunday", in: app)
        tap("bed.editor.save", in: app)
        expectCall(startingWith: "mqtt.publish", in: app)
        XCTAssertTrue(element("bed.alarms.sunday", in: app).waitForExistence(timeout: 5))
    }

    func testDeletingABedAlarmAsksFirst() {
        let app = launch(sheet: "stephens-bed", tab: "alarms")
        tap("bed.alarms.saturday", in: app)
        tap("bed.day.alarm.09:15", in: app)
        tap("bed.editor.delete", in: app)
        let confirm = app.buttons["Delete Alarm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        expectCall(startingWith: "mqtt.publish", in: app)
    }

    func testTravelerSideIsReadOnly() {
        let app = launch(sheet: "stephs-bed", scenario: "solo-trip")
        XCTAssertTrue(element("bed.soloTrip", in: app).exists)
        XCTAssertFalse(element("bed.power", in: app).exists, "The traveler's side has no power control")
        XCTAssertEqual(element("bed.hint", in: app).label, "Away · Read Only")
    }

    func testHomeSideControlsTheWholeBed() {
        let app = launch(sheet: "stephens-bed", scenario: "solo-trip")
        XCTAssertTrue(app.navigationBars["Stephen's Bed · Whole Bed"].exists)
        element("bed.power", in: app).tap()
        let confirm = turnOffConfirmation(in: app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Turning off asks first")
        confirm.tap()
        expectCall(startingWith: "script.household_away_command action=set_power", in: app)
    }

    // MARK: - Wake light

    func testWakeAlarmToggleAndDefaults() {
        let app = launch(sheet: "wake-light")
        let toggle = element("wake.alarm.weekday.enabled", in: app)
        reveal(toggle, in: app)
        toggle.tap()
        expectCall(containing: "operation=upsert_alarm", in: app)
        selectTab("Defaults", in: app)
        tap("wake.defaults.ramp.15", in: app)
        expectCall(containing: "operation=update_defaults", in: app)
    }

    /// A new weekly alarm with "Add to Steph's Bed" creates the missing bed alarms.
    func testAddingAWakeAlarmToABed() {
        let app = launch(sheet: "wake-light")
        tap("wake.add", in: app)
        let bed = element("wake.editor.bed.right", in: app)
        reveal(bed, in: app)
        bed.switches.firstMatch.exists ? bed.switches.firstMatch.tap() : bed.tap()
        tap("wake.editor.save", in: app)
        expectCall(startingWith: "mqtt.publish", in: app)
        XCTAssertTrue(element("wake.add", in: app).waitForExistence(timeout: 5), "Back on the list")
    }

    func testStoppingAWakeEpisode() {
        let app = launch(sheet: "wake-light", scenario: "waking")
        tap("wake.stop", in: app)
        expectCall(containing: "operation=end_episode", in: app)
        XCTAssertTrue(element("wake.stop", in: app).waitForNonExistence(timeout: 5))
    }

    func testLinkedAlarmOpensTheBed() {
        let app = launch(sheet: "wake-light")
        tap("wake.alarm.sleepypod-left.open", in: app)
        XCTAssertTrue(element("bed.alarms.add", in: app).waitForExistence(timeout: 10), "Bed sheet opens on Alarms")
    }

    // MARK: - Layout

    /// Hero beside the tabs only on iPad landscape and unfolded Duo landscape.
    func testLayoutFollowsThePose() {
        if FentonHomeApp.family == .iPad {
            XCUIDevice.shared.orientation = .portrait
            var app = launch(sheet: "stephens-bed")
            XCTAssertTrue(element("bed.layout.singleColumn", in: app).exists, "iPad portrait is one column")
            XCUIDevice.shared.orientation = .landscapeLeft
            app = launch(sheet: "stephens-bed")
            XCTAssertTrue(element("bed.layout.twoColumn", in: app).waitForExistence(timeout: 5), "iPad landscape splits")
            return
        }
        let app = launch(sheet: "stephens-bed")
        let window = app.windows.firstMatch.frame
        let landscape = window.width > window.height
        if FentonHomeApp.family == .iPhone { XCTAssertFalse(landscape, "iPhone stays portrait") }
        let expected = FentonHomeApp.family == .iPhoneDuo && landscape && window.width >= 720 ? "bed.layout.twoColumn" : "bed.layout.singleColumn"
        XCTAssertTrue(element(expected, in: app).exists, "\(FentonHomeApp.family) window \(window.size) expects \(expected)")
    }

    // MARK: - Accessibility audits

    /// Audits a sheet, or a page pushed inside it when `open` taps through to one (after each launch, including
    /// the AX5 relaunch).
    private func audit(sheet: String?, tab: String? = nil, scenario: String = "default",
                       open: ((XCUIApplication) -> Void)? = nil) throws {
        let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]
        for orientation in orientations {
            if orientation != .unknown { XCUIDevice.shared.orientation = orientation }
            let app = launch(sheet: sheet, tab: tab, scenario: scenario)
            open?(app)
            try FentonHomeApp.audit(app) {
                let large = self.launch(sheet: sheet, tab: tab, scenario: scenario, arguments: FentonHomeApp.ax5)
                open?(large)
                return large
            }
        }
    }

    private func openBedAlarmDay(_ app: XCUIApplication) {
        tap("bed.alarms.monday", in: app)
        XCTAssertTrue(element("bed.day.add", in: app).waitForExistence(timeout: 10))
        sleep(1)
    }

    private func openBedAlarmEditor(_ app: XCUIApplication) {
        openBedAlarmDay(app)
        tap("bed.day.alarm.06:30", in: app)
        XCTAssertTrue(element("bed.editor.save", in: app).waitForExistence(timeout: 10))
        sleep(1)
    }

    private func openWakeEditor(_ app: XCUIApplication) {
        tap("wake.add", in: app)
        XCTAssertTrue(element("wake.editor.save", in: app).waitForExistence(timeout: 10))
        sleep(1)
    }

    func testTilesPassAudit() throws { try audit(sheet: nil) }
    func testBedTemperaturePassesAudit() throws { try audit(sheet: "stephens-bed", scenario: "ringing") }
    func testBedSpecialModesPassesAudit() throws { try audit(sheet: "stephs-bed", tab: "special-modes", scenario: "hot-flash") }
    func testBedAlarmsPassesAudit() throws { try audit(sheet: "stephens-bed", tab: "alarms") }
    func testBedStatusPassesAudit() throws { try audit(sheet: "stephens-bed", tab: "status") }
    func testSoloTripBedPassesAudit() throws { try audit(sheet: "stephs-bed", scenario: "solo-trip") }
    func testWakeAlarmsPassesAudit() throws { try audit(sheet: "wake-light", scenario: "waking") }
    func testWakeDefaultsPassesAudit() throws { try audit(sheet: "wake-light", tab: "defaults") }
    func testBedAlarmDayPassesAudit() throws { try audit(sheet: "stephens-bed", tab: "alarms", open: openBedAlarmDay) }
    func testBedAlarmEditorPassesAudit() throws { try audit(sheet: "stephens-bed", tab: "alarms", open: openBedAlarmEditor) }
    func testWakeEditorPassesAudit() throws { try audit(sheet: "wake-light", open: openWakeEditor) }

    // MARK: - Screenshots

    /// Every sheet, tab and pushed page in the current pose (iPad: both orientations), named
    /// `bedroom-<screen>-<orientation>`. Split in three so a simulator crash retries a short run, not all of them.
    func testCaptureBedroomScreens() {
        capture([
            ("tiles", nil, nil, "default"),
            ("bed-temperature", "stephens-bed", nil, "default"),
            ("bed-ringing", "stephens-bed", nil, "ringing"),
            ("bed-special-modes", "stephs-bed", "special-modes", "hot-flash"),
            ("bed-alarms", "stephens-bed", "alarms", "default"),
            ("bed-status", "stephens-bed", "status", "default"),
        ])
    }

    func testCaptureBedroomScreensMore() {
        capture([
            ("bed-solo-trip-home", "stephens-bed", nil, "solo-trip"),
            ("bed-solo-trip-traveler", "stephs-bed", nil, "solo-trip"),
            ("bed-unavailable", "stephens-bed", nil, "unavailable"),
            ("wake-alarms", "wake-light", nil, "default"),
            ("wake-active", "wake-light", nil, "waking"),
            ("wake-defaults", "wake-light", "defaults", "default"),
        ])
    }

    /// Pushed pages and prompts.
    func testCaptureBedroomPushedScreens() {
        forEachCaptureOrientation { suffix in
            var app = launch(sheet: "stephens-bed", tab: "alarms", clean: true)
            tap("bed.alarms.monday", in: app)
            sleep(1)
            keepScreenshot(app, "bedroom-bed-alarm-day-\(suffix)")
            tap("bed.day.alarm.06:30", in: app)
            sleep(1)
            keepScreenshot(app, "bedroom-bed-alarm-editor-\(suffix)")
            app = launch(sheet: "stephens-bed", clean: true)
            tap("bed.stage.asleep.up", in: app)
            XCTAssertTrue(element("bed.scope.allNights", in: app).waitForExistence(timeout: 5))
            sleep(1)
            keepScreenshot(app, "bedroom-bed-scope-prompt-\(suffix)")
            app = launch(sheet: "wake-light", clean: true)
            tap("wake.add", in: app)
            sleep(1)
            keepScreenshot(app, "bedroom-wake-editor-\(suffix)")
        }
    }

    private func capture(_ shots: [(name: String, sheet: String?, tab: String?, scenario: String)]) {
        forEachCaptureOrientation { suffix in
            for shot in shots {
                let app = launch(sheet: shot.sheet, tab: shot.tab, scenario: shot.scenario, clean: true)
                keepScreenshot(app, "bedroom-\(shot.name)-\(suffix)")
            }
        }
    }

    /// Runs `body` in each orientation the family captures (iPad: portrait, then landscape; others: the current
    /// pose) with its file-name suffix.
    private func forEachCaptureOrientation(_ body: (String) -> Void) {
        guard FentonHomeApp.family == .iPad else { return body("current") }
        for (orientation, suffix) in [(UIDeviceOrientation.portrait, "portrait"), (.landscapeLeft, "landscape")] {
            XCUIDevice.shared.orientation = orientation
            body(suffix)
        }
    }
}
