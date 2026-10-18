import XCTest

/// The room device sheets in the debug gallery (fixture state, recording service caller; nothing reaches the
/// house): what each control sends, semantics, layout per pose, accessibility audits and screenshots on iPhone,
/// iPhone Duo and iPad (`.agents/patterns/room-device-sheets.md`).
/// The fan timer's lengths in minutes (`BathroomFanController.timerMinutes`).
private enum BathroomLengths {
    static let all = [5, 10, 15, 20, 30, 60]
}

@MainActor
final class RoomDevicesJourneyTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    override func tearDown() {
        MainActor.assumeIsolated {
            if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
        }
    }

    // MARK: - Helpers

    /// Opens a gallery fixture's sheet and waits for `ready` to be hittable.
    private func launch(_ device: String, ready: String, tab: String = "controls", clean: Bool = false,
                        appearance: String? = nil, arguments: [String] = []) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        if let appearance { app.launchEnvironment["FENTON_APPEARANCE"] = appearance }
        app.launchEnvironment["FENTON_GALLERY"] = "room-devices"
        app.launchEnvironment["FENTON_GALLERY_DEVICE"] = device
        app.launchEnvironment["FENTON_GALLERY_TAB"] = tab
        if clean { app.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1" }
        app.launchArguments += arguments
        app.launch()
        let element = element(ready, in: app)
        XCTAssertTrue(element.waitForExistence(timeout: 30), "\(device) sheet did not open")
        XCTAssertTrue(element.wait(for: \.isHittable, toEqual: true, timeout: 10), "Sheet still presenting")
        sleep(1) // Mid-animation frames fail contrast and clipping.
        return app
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// One option of a segmented choice (`SegmentedChoice`), found by its control and title.
    private func segment(_ control: String, _ title: String, in app: XCUIApplication) -> XCUIElement {
        app.segmentedControls[control].buttons[title].firstMatch
    }

    private func expectCall(_ expected: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let label = app.staticTexts["gallery.lastCall"].firstMatch
        let matched = label.wait(for: \.label, toEqual: "Last call: \(expected)", timeout: 10)
        XCTAssertTrue(matched, "Last call was '\(label.label)'", file: file, line: line)
    }

    /// Scrolls the column holding `element` in short drags until it is hittable (anchored on the window so
    /// gestures reach the inner display of an unfolded iPhone Duo).
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        for _ in 0..<24 where !element.isHittable {
            let above = element.exists && element.frame.midY < window.midY && element.frame.maxY < window.minY + 120
            var x = element.exists && element.frame.midX > 0 ? element.frame.midX : window.midX
            if FentonHomeApp.family == .iPhoneDuo { x = min(x, window.maxX - 96) }
            let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: -window.minX, dy: -window.minY))
            let from = origin.withOffset(CGVector(dx: x, dy: window.minY + window.height * (above ? 0.35 : 0.65)))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: above ? 220 : -220)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(element.isHittable, "\(element) never came into view")
    }

    /// A 44 pt control inside a content-fitted sheet. iOS draws the inset (non-large) sheet's content at 0.955x (384 of 402 pt
    /// wide on iPhone), so a 44 pt target measures 42 pt there; the large sheet draws it at full size.
    private func assertSheetTarget(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(element.frame.height, 41.5, element.label, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.width, 41.5, element.label, file: file, line: line)
    }

    private func assertTarget(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(element.frame.width, 43, element.label, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 43, element.label, file: file, line: line)
    }

    // MARK: - Bathroom fan

    /// Power and lock are toggles; the timer starts from the segmented row and one button, which works while the fan is off
    /// (the script turns it on).
    func testFanTogglesAndTimer() {
        let app = launch("fan-guest", ready: "fan.power")
        let power = element("fan.power", in: app)
        XCTAssertEqual(power.value as? String, "Off")
        assertTarget(power)
        let set = element("fan.setTimer", in: app)
        reveal(set, in: app)
        XCTAssertTrue(set.isEnabled, "Starting a timer turns the fan on, so the button needs no running fan")
        XCTAssertEqual(set.label, "Turn Off in 30 Minutes")
        XCTAssertFalse(app.staticTexts["Auto-disable lock"].exists)
        XCTAssertFalse(element("fan.autoUnlock", in: app).exists, "The auto-unlock choice is gone")
        power.tap()
        expectCall("script.guest_bathroom_fan_command command=power target_power=on", in: app)
        XCTAssertEqual(power.value as? String, "On")
        element("fan.lock", in: app).tap()
        expectCall("script.guest_bathroom_fan_command command=lock locked=true", in: app)
        XCTAssertFalse(element("fan.autoUnlock", in: app).exists, "Locked and on no longer shows an auto-unlock choice")
        reveal(set, in: app)
        let ten = element("fan.timerOption.10", in: app)
        ten.tap()
        XCTAssertTrue(ten.isSelected)
        XCTAssertEqual(set.label, "Turn Off in 10 Minutes")
        set.tap()
        expectCall("script.guest_bathroom_fan_command auto_unlock=true command=timer_start minutes=10", in: app)
        XCTAssertTrue(element("fan.remaining", in: app).waitForExistence(timeout: 5), "Counts down")
    }

    /// Starting a timer on an off fan turns it on (the echo, like the script, switches it on).
    func testTimerOnAnOffFanTurnsItOn() {
        let app = launch("fan-guest", ready: "fan.power")
        let power = element("fan.power", in: app)
        XCTAssertEqual(power.value as? String, "Off")
        let set = element("fan.setTimer", in: app)
        reveal(set, in: app)
        element("fan.timerOption.60", in: app).tap()
        XCTAssertEqual(set.label, "Turn Off in 1 Hour")
        set.tap()
        expectCall("script.guest_bathroom_fan_command auto_unlock=true command=timer_start minutes=60", in: app)
        XCTAssertTrue(element("fan.remaining", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(power.value as? String, "On")
    }

    /// Six lengths, each a 44 pt target; the chosen one is selected; the footnote says what the button does.
    func testTimerLengthRowAndFootnote() {
        let app = launch("fan-guest", ready: "fan.power")
        let set = element("fan.setTimer", in: app)
        reveal(set, in: app)
        let expected = [5: "5 minutes", 10: "10 minutes", 15: "15 minutes", 20: "20 minutes", 30: "30 minutes", 60: "1 hour"]
        var previousX: CGFloat = -1
        for minutes in expected.keys.sorted() {
            let option = element("fan.timerOption.\(minutes)", in: app)
            XCTAssertTrue(option.exists, "\(minutes)")
            XCTAssertEqual(option.label, expected[minutes])
            assertSheetTarget(option)
            XCTAssertGreaterThan(option.frame.minX, previousX, "In order, left to right")
            previousX = option.frame.minX
        }
        XCTAssertTrue(element("fan.timerOption.30", in: app).isSelected, "30 minutes is the default")
        XCTAssertTrue(app.staticTexts["The fan runs, then turns itself off. Starting a timer turns it on if it's off."].exists)
    }

    /// A running timer counts down in orange and Clear Timer cancels it. Master is on, locked and timed.
    func testFanClearsARunningTimer() {
        let app = launch("fan-master", ready: "fan.power")
        let remaining = element("fan.remaining", in: app)
        XCTAssertTrue(remaining.exists)
        XCTAssertTrue((remaining.value as? String ?? "").contains("minute"), "Spoken as a duration: \(remaining.value ?? "")")
        XCTAssertGreaterThanOrEqual(remaining.frame.height, 40, "A 40 pt countdown")
        XCTAssertEqual(element("fan.lock", in: app).value as? String, "On")
        XCTAssertFalse(element("fan.autoUnlock", in: app).exists, "No auto-unlock choice while locked and timed")
        XCTAssertFalse(element("fan.timerOption.5", in: app).exists, "The length row is hidden while a timer runs")
        let clear = element("fan.clearTimer", in: app)
        reveal(clear, in: app)
        XCTAssertEqual(clear.label, "Clear Timer")
        assertSheetTarget(clear)
        clear.tap()
        expectCall("script.master_bathroom_fan_command command=timer_cancel", in: app)
        XCTAssertTrue(element("fan.setTimer", in: app).waitForExistence(timeout: 5))
    }

    /// Power is the air teal and Lock the security blue, so the two read apart at a glance (both on in Master).
    func testPowerAndLockTilesAreDistinctColours() throws {
        let app = launch("fan-master", ready: "fan.power", clean: true)
        let power = element("fan.power", in: app)
        let lock = element("fan.lock", in: app)
        let capture = try XCTUnwrap(RenderedContrast.Capture.screen())
        let teal = try XCTUnwrap(TileGeometry.rgb(at: CGPoint(x: power.frame.minX + 8, y: power.frame.maxY - 8), in: capture))
        let blue = try XCTUnwrap(TileGeometry.rgb(at: CGPoint(x: lock.frame.minX + 8, y: lock.frame.maxY - 8), in: capture))
        XCTAssertTrue(TileGeometry.matches(teal, 0x006E62, tolerance: 14), "Power fills with the air teal: \(teal)")
        XCTAssertTrue(TileGeometry.matches(blue, 0x1565C0, tolerance: 14), "Lock fills with the security blue: \(blue)")
        keepScreenshot(app, "fan-sheet-running-\(FentonHomeApp.family)")
    }

    /// The sheet reads in the light appearance too (a dark selected segment, a deeper timer orange).
    func testFanSheetPassesAuditInLight() throws {
        for device in ["fan-guest", "fan-master"] {
            let app = launch(device, ready: "fan.power", clean: true, appearance: "light")
            try FentonHomeApp.audit(app) {
                self.launch(device, ready: "fan.power", clean: true, appearance: "light", arguments: FentonHomeApp.ax5)
            }
            keepScreenshot(app, "fan-sheet-light-\(device)-\(FentonHomeApp.family)")
        }
    }

    // MARK: - Air quality

    /// Modes are segmented choices; Auto shows its sub-modes and Manual its speeds.
    func testPurifierModesAndSpeeds() {
        let app = launch("purifier-manual", ready: "purifier.mode")
        XCTAssertTrue(segment("purifier.mode", "Manual", in: app).isSelected)
        XCTAssertTrue(segment("purifier.speed", "Medium", in: app).isSelected)
        XCTAssertFalse(element("purifier.auto", in: app).exists)
        segment("purifier.speed", "High", in: app).tap()
        expectCall("fan.set_percentage entity_id=fan.living_room_air_purifier_levoit_purifier percentage=100", in: app)
        segment("purifier.mode", "Auto", in: app).tap()
        expectCall("select.select_option entity_id=select.living_room_air_purifier_fan_mode option=Auto", in: app)
        let quiet = segment("purifier.auto", "Quiet", in: app)
        XCTAssertTrue(quiet.waitForExistence(timeout: 5))
        XCTAssertFalse(element("purifier.speed", in: app).exists)
        quiet.tap()
        expectCall("select.select_option entity_id=select.living_room_air_purifier_auto_mode option=Quiet", in: app)
        XCTAssertTrue(quiet.wait(for: \.isSelected, toEqual: true, timeout: 5))
    }

    // MARK: - Grill

    /// Sensors are read-only; the switches toggle with explicit services.
    func testGrillCards() {
        let app = launch("grill", ready: "grill.Keep Warm")
        XCTAssertEqual(element("grill.Probe 1", in: app).value as? String, "165 °F")
        XCTAssertFalse(element("grill.Probe 1", in: app).elementType == .button, "Sensors are not buttons")
        let keepWarm = element("grill.Keep Warm", in: app)
        XCTAssertEqual(keepWarm.value as? String, "Off")
        keepWarm.tap()
        expectCall("switch.turn_on entity_id=switch.d8478fa2ad0a_keep_warm_enabled", in: app)
        let on = NSPredicate(format: "value == %@", "On")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: on, object: keepWarm)], timeout: 5), .completed)
    }

    // MARK: - Humidifier

    /// Presets, warm mist and Turn Off send the humidifier's services; the dial is one adjustable handle.
    func testHumidifierControls() {
        let app = launch("humidifier", ready: "humidifier.power")
        let handle = element("thermostatDial.handle.target", in: app)
        XCTAssertTrue(handle.exists)
        XCTAssertEqual(handle.label, "Mist level")
        XCTAssertEqual(handle.value as? String, "5")
        assertTarget(handle)
        let high = segment("humidifier.mist", "High", in: app)
        reveal(high, in: app)
        high.tap()
        expectCall("script.master_bedroom_humidifier_set_level level=8", in: app)
        let warm = segment("humidifier.warm", "High", in: app)
        reveal(warm, in: app)
        warm.tap()
        expectCall("number.set_value entity_id=number.lv600s_humidifier_warm_level value=3", in: app)
        XCTAssertTrue(warm.wait(for: \.isSelected, toEqual: true, timeout: 5))
        let targetHandle = element("humidifier.targetDial", in: app).descendants(matching: .any)["thermostatDial.handle.target"].firstMatch
        reveal(targetHandle, in: app)
        XCTAssertEqual(targetHandle.label, "Target humidity")
        XCTAssertEqual(targetHandle.value as? String, "50 percent")
        let power = element("humidifier.power", in: app)
        reveal(power, in: app)
        power.tap()
        expectCall("switch.turn_off entity_id=switch.lv600s_humidifier_power", in: app)
    }

    /// A removed tank locks output and explains why.
    func testHumidifierFault() {
        let app = launch("humidifier-fault", ready: "humidifier.power")
        XCTAssertFalse(element("thermostatDial.handle.target", in: app).exists, "Read-only while faulted")
        XCTAssertTrue(app.staticTexts["Reinsert the water tank to restore controls."].exists)
        XCTAssertFalse(segment("humidifier.mode", "Sleep", in: app).isEnabled)
    }

    /// Schedules list the activities; editing one and saving writes the helper.
    func testHumidifierSchedules() {
        let app = launch("humidifier", ready: "humidifier.power", tab: "schedules")
        let night = element("humidifier.activity.Night", in: app)
        reveal(night, in: app)
        XCTAssertTrue(element("humidifier.activity.Evening", in: app).exists)
        night.tap()
        let save = element("activity.save", in: app)
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        // The fixture's Night runs Sunday–Thursday; adding Friday and Saturday makes it every day.
        element("activity.day.friday", in: app).tap()
        element("activity.day.saturday", in: app).tap()
        save.tap()
        XCTAssertTrue(night.waitForExistence(timeout: 10), "Back on the list after saving")
        XCTAssertTrue(night.label.contains("Every day"), night.label)

        let add = element("humidifier.addActivity", in: app)
        reveal(add, in: app)
        add.tap()
        XCTAssertTrue(element("activity.save", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["This activity overlaps another activity on Monday."].waitForExistence(timeout: 5),
                      "A new weekday night overlaps the existing one")
        // The saved editor's Save can still be in the tree while its page pops (iPad landscape, 2026-10-17): wait for the
        // new editor's to be the only one, then read it.
        let saves = app.descendants(matching: .any).matching(identifier: "activity.save")
        let deadline = Date().addingTimeInterval(10)
        while saves.count > 1, Date() < deadline { usleep(200_000) }
        XCTAssertEqual(saves.count, 1, "The previous editor's Save stayed in the tree")
        if saves.firstMatch.isEnabled { add(XCTAttachment(string: app.debugDescription)) }
        XCTAssertFalse(saves.firstMatch.isEnabled, "Save stays off while the activity overlaps another")
    }

    /// Two columns only on iPad landscape and unfolded Duo landscape; iPhone and every portrait are one column.
    func testHumidifierLayoutFollowsThePose() {
        if FentonHomeApp.family == .iPad {
            XCUIDevice.shared.orientation = .portrait
            var app = launch("humidifier", ready: "humidifier.power")
            XCTAssertTrue(element("humidifier.layout.singleColumn", in: app).exists, "iPad portrait is one column")
            XCUIDevice.shared.orientation = .landscapeLeft
            app = launch("humidifier", ready: "humidifier.power")
            XCTAssertTrue(element("humidifier.layout.twoColumn", in: app).waitForExistence(timeout: 5), "iPad landscape splits")
            // The hero leads; the tab's controls trail (the section bar runs along the bottom of both).
            XCTAssertLessThan(element("humidifier.power", in: app).frame.maxX, app.segmentedControls["humidifier.mode"].frame.minX)
            return
        }
        let app = launch("humidifier", ready: "humidifier.power")
        let window = app.windows.firstMatch.frame
        let landscape = window.width > window.height
        if FentonHomeApp.family == .iPhone { XCTAssertFalse(landscape, "iPhone stays portrait") }
        let expected = FentonHomeApp.family == .iPhoneDuo && landscape && window.width >= 720
            ? "humidifier.layout.twoColumn" : "humidifier.layout.singleColumn"
        XCTAssertTrue(element(expected, in: app).exists, "\(FentonHomeApp.family) window \(window.size) expects \(expected)")
    }

    // MARK: - Accessibility audits

    private func audit(_ device: String, ready: String, tab: String = "controls") throws {
        let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]
        for orientation in orientations {
            if orientation != .unknown { XCUIDevice.shared.orientation = orientation }
            let app = launch(device, ready: ready, tab: tab)
            try FentonHomeApp.audit(app) { self.launch(device, ready: ready, tab: tab, arguments: FentonHomeApp.ax5) }
        }
    }

    func testFanPassesAudit() throws { try audit("fan-master", ready: "fan.power") }
    func testIdleFanPassesAudit() throws { try audit("fan-guest", ready: "fan.power") }
    func testPurifierPassesAudit() throws { try audit("purifier-auto", ready: "purifier.mode") }
    // The header, not a card: at AX5 the cards start below the folded iPhone Duo's fold.
    func testGrillPassesAudit() throws { try audit("grill", ready: "grill.header") }
    func testHumidifierControlsPassAudit() throws { try audit("humidifier", ready: "humidifier.power") }
    func testHumidifierSchedulesPassAudit() throws { try audit("humidifier", ready: "humidifier.power", tab: "schedules") }
    func testHumidifierInfoPassesAudit() throws { try audit("humidifier", ready: "humidifier.power", tab: "info") }

    /// At AX5 the sheets keep every control reachable by scrolling.
    func testLargestTextKeepsControlsReachable() {
        let fan = launch("fan-guest", ready: "fan.power", arguments: FentonHomeApp.ax5)
        reveal(element("fan.setTimer", in: fan), in: fan)
        // The six lengths wrap to a grid and stay 44 pt targets that fit the width.
        let window = fan.windows.firstMatch.frame
        for minutes in BathroomLengths.all {
            let option = element("fan.timerOption.\(minutes)", in: fan)
            XCTAssertTrue(option.exists, "\(minutes)")
            XCTAssertGreaterThanOrEqual(option.frame.height, 43)
            XCTAssertLessThanOrEqual(option.frame.maxX, window.maxX + 1, "\(minutes)m fits the width")
        }
        let timed = launch("fan-master", ready: "fan.power", arguments: FentonHomeApp.ax5)
        let remaining = element("fan.remaining", in: timed)
        reveal(remaining, in: timed)
        XCTAssertLessThanOrEqual(remaining.frame.maxX, timed.windows.firstMatch.frame.maxX + 1, "The countdown fits at AX5")
        reveal(element("fan.clearTimer", in: timed), in: timed)
        let humidifier = launch("humidifier", ready: "humidifier.power", arguments: FentonHomeApp.ax5)
        reveal(element("humidifier.display", in: humidifier), in: humidifier)
    }

    // MARK: - Screenshots

    /// Every sheet in the current pose (iPad: both orientations), named `device-<fixture>-<tab>-<orientation>`.
    func testCaptureDeviceScreens() {
        let shots = [("fan-guest", "fan.power", "controls"), ("fan-master", "fan.power", "controls"), ("purifier-auto", "purifier.mode", "controls"),
                     ("grill", "grill.header", "controls"), ("humidifier", "humidifier.power", "controls"),
                     ("humidifier", "humidifier.power", "schedules"), ("humidifier", "humidifier.power", "info"),
                     ("humidifier-fault", "humidifier.power", "controls")]
        let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]
        for orientation in orientations {
            if orientation != .unknown { XCUIDevice.shared.orientation = orientation }
            let suffix = orientation == .landscapeLeft ? "landscape" : orientation == .portrait ? "portrait" : "current"
            for (device, ready, tab) in shots {
                let app = launch(device, ready: ready, tab: tab, clean: true)
                keepScreenshot(app, "device-\(device)-\(tab)-\(suffix)")
            }
        }
    }
}
