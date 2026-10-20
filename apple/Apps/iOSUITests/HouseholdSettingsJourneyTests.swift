import XCTest

/// Household Settings pages (Admin, Special Device Modes, Guest Controls, Mach-E). Controls are exercised in the
/// debug gallery (`FENTON_GALLERY=household-settings`) on fixture state with a recording caller, so no journey
/// switches anything in the house; the signed-in journey only opens the live pages and audits them.
@MainActor
final class HouseholdSettingsJourneyTests: JourneyTestCase {
    // MARK: - Helpers

    /// Opens the gallery on `page` (`admin`, `specialDeviceModes`, `guests`, `machE`).
    private func launch(_ page: String, unavailable: Bool = false, arguments: [String] = [], clean: Bool = false) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "household-settings"
        app.launchEnvironment["FENTON_GALLERY_HOUSEHOLD"] = page
        if unavailable { app.launchEnvironment["FENTON_GALLERY_UNAVAILABLE"] = "1" }
        if clean { app.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1" }
        app.launchArguments += arguments
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["household.\(page)"].waitForExistence(timeout: 10), "\(page) page did not open")
        return app
    }

    /// A tile by entity id.
    private func tile(_ app: XCUIApplication, _ entityId: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "household.tile.\(entityId)").firstMatch
    }

    /// Scrolls the page until `element` can be tapped.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, scroller: XCUIElement? = nil) -> XCUIElement {
        let scroll = scroller ?? app.scrollViews.firstMatch
        // The gallery's last-call bar covers the bottom of the page, and a tile under it still reads as hittable.
        let bar = lastCall(app)
        func clear() -> Bool {
            guard element.exists, element.isHittable else { return false }
            return !bar.exists || element.frame.maxY <= bar.frame.minY
        }
        var swiped = false
        for _ in 0..<12 where !clear() {
            scroll.swipeUp(velocity: .slow)
            swiped = true
        }
        // A tap during scroll momentum only stops the scroll, so let it settle first.
        if swiped { usleep(800_000) }
        return element
    }

    /// Waits until the element's accessibility value is `text`.
    private func waitForValue(_ element: XCUIElement, _ text: String, timeout: TimeInterval = 6) -> Bool {
        let predicate = NSPredicate(format: "value == %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    private func lastCall(_ app: XCUIApplication) -> XCUIElement { app.staticTexts["gallery.lastCall"] }

    private func expectLastCall(_ app: XCUIApplication, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(lastCall(app).wait(for: \.label, toEqual: "Last call: \(text)", timeout: 6),
                      "Last call was \(lastCall(app).label)", file: file, line: line)
    }

    /// Back: the bar's back button, which the folded iPhone Duo moves to its rail.
    private func goBack(_ app: XCUIApplication) {
        let back = app.buttons["BackButton"].firstMatch
        if back.exists { back.tap() } else { app.navigationBars.buttons.element(boundBy: 0).tap() }
    }

    /// Back from the presence detail to the room grid. Prefers the detail's own bar: with the sheet over the
    /// page, the first `BackButton` can be the page's (behind the sheet) on the unfolded iPhone Duo.
    private func backFromPresenceDetail(_ app: XCUIApplication) {
        // The detail's bar is titled with the room and carries the sheet's Done; the grid's is the sheet title.
        let bar = app.navigationBars.containing(.button, identifier: "household.sheet.done")
            .matching(NSPredicate(format: "identifier != 'Presence-Based Overrides'")).firstMatch
        // The detail's bar also carries the sheet's Done, which closes the whole sheet: never pick that.
        let back = bar.buttons.matching(NSPredicate(format: "identifier != 'household.sheet.done'")).firstMatch
        if back.exists, back.isHittable { back.tap() } else { goBack(app) }
    }

    /// Opens one of the Admin sheets.
    private func openSheet(_ app: XCUIApplication, _ sheet: String) {
        let opener = reveal(app.buttons["admin.open.\(sheet)"], in: app)
        opener.tap()
        let done = app.buttons["household.sheet.done"]
        // A loaded host can drop the first tap; tap once more if the sheet hasn't started presenting.
        if !done.waitForExistence(timeout: 6), opener.isHittable { opener.tap() }
        XCTAssertTrue(done.waitForExistence(timeout: 6), "\(sheet) sheet did not open")
        sleep(1) // Let the sheet finish presenting.
    }

    // MARK: - Admin

    func testAdminTogglesSendExplicitOnOff() {
        let app = launch("admin")
        let autoLock = tile(app, "input_boolean.is_front_door_auto_lock_enabled")
        XCTAssertTrue(autoLock.waitForExistence(timeout: 5))
        XCTAssertEqual(autoLock.value as? String, "On")
        XCTAssertGreaterThanOrEqual(autoLock.frame.height, 44)
        autoLock.tapCenter()
        expectLastCall(app, "input_boolean.turn_off entity_id=input_boolean.is_front_door_auto_lock_enabled")
        XCTAssertTrue(waitForValue(autoLock, "Off"), "autoLock value is \(autoLock.value ?? "nil")")

        let faucets = reveal(tile(app, "input_boolean.show_outdoor_faucets"), in: app)
        XCTAssertEqual(faucets.value as? String, "Off")
        faucets.tapCenter()
        expectLastCall(app, "input_boolean.turn_on entity_id=input_boolean.show_outdoor_faucets")
    }

    func testPowerRecoveryTriggersTheAutomation() {
        let app = launch("admin")
        reveal(app.buttons["admin.powerRecovery"], in: app).tap()
        expectLastCall(app, "automation.trigger entity_id=automation.attempt_to_turn_power_back_on_in_living_room")
    }

    /// Fixtures start with Relay Control Mode and Guest Room guest mode on, so the warning shows until relay mode is off.
    func testRelayWarningFollowsRelayModeAndGuestRoom() {
        let app = launch("admin")
        let warning = app.descendants(matching: .any)["admin.relayWarning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5), "Relay warning missing")
        // Reveal the tile itself: revealing the warning below it can leave the tile under the bar on the
        // folded iPhone Duo, where a tap misses (flaky, 2026-10-12).
        let relay = reveal(tile(app, "input_boolean.relay_control_mode"), in: app)
        XCTAssertTrue(waitForValue(relay, "On"), "relay value is \(relay.value ?? "nil")")
        relay.tapCenter()
        expectLastCall(app, "input_boolean.turn_off entity_id=input_boolean.relay_control_mode")
        XCTAssertTrue(warning.waitForNonExistence(timeout: 3), "Relay warning stayed after relay mode turned off")
    }

    func testPresenceOverrideSetsTheRoomMode() {
        let app = launch("admin")
        openSheet(app, "presenceOverrides")
        let livingRoom = app.buttons["presence.room.switch.living_room_presence_living_room_lights_presence_allowed"]
        XCTAssertTrue(livingRoom.waitForExistence(timeout: 5))
        XCTAssertEqual(livingRoom.value as? String, "Enabled")
        // An unavailable room still opens (its detail disables the choices); see testUnavailableEntitiesDisableTheirControls.
        let upperDeck = app.buttons["presence.room.switch.upper_deck_presence_back_deck_lights_presence_allowed"]
        XCTAssertEqual(upperDeck.value as? String, "Unavailable")
        XCTAssertTrue(upperDeck.isEnabled, "An unavailable room should still open")
        livingRoom.tap()
        let paused = app.buttons["presence.option.paused"]
        XCTAssertTrue(paused.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["presence.option.enabled"].isSelected)
        paused.tap()
        XCTAssertTrue(paused.isSelected, "Paused not shown at once")
        sleep(1) // The recorder echoes after 400 ms; the live value must keep it selected.
        XCTAssertTrue(paused.isSelected)
        XCTAssertFalse(app.buttons["presence.option.enabled"].isSelected)
        backFromPresenceDetail(app)
        XCTAssertTrue(waitForValue(livingRoom, "Paused"), "livingRoom value is \(livingRoom.value ?? "nil")")
        app.buttons["household.sheet.done"].tap()
        expectLastCall(app, "presence_based_lighting.set_automation_state entity_id=switch.living_room_presence_living_room_lights_presence_allowed state=paused")
    }

    func testAutoResetSheetToggles() {
        let app = launch("admin")
        openSheet(app, "autoReset")
        let kitchen = tile(app, "switch.kitchen_auto_re_enable_presence_lighting")
        XCTAssertTrue(kitchen.waitForExistence(timeout: 5))
        XCTAssertEqual(kitchen.value as? String, "On")
        kitchen.tapCenter()
        XCTAssertTrue(waitForValue(kitchen, "Off"), "kitchen value is \(kitchen.value ?? "nil")")
        app.buttons["household.sheet.done"].tap()
        expectLastCall(app, "switch.turn_off entity_id=switch.kitchen_auto_re_enable_presence_lighting")
    }

    // MARK: - Other pages

    func testSpecialDeviceModesTogglesHighAqi() {
        let app = launch("specialDeviceModes")
        let aqi = tile(app, "input_boolean.high_aqi_mode")
        XCTAssertTrue(aqi.waitForExistence(timeout: 5))
        XCTAssertEqual(aqi.value as? String, "Off")
        aqi.tapCenter()
        expectLastCall(app, "input_boolean.turn_on entity_id=input_boolean.high_aqi_mode")
        XCTAssertTrue(waitForValue(aqi, "On"), "aqi value is \(aqi.value ?? "nil")")
    }

    func testGuestControlsToggleEachRoom() {
        let app = launch("guests")
        for id in ["guest_room", "music_room", "theater_room"] {
            XCTAssertTrue(tile(app, "input_boolean.guests_staying_in_\(id)").waitForExistence(timeout: 5), id)
        }
        tile(app, "input_boolean.guests_staying_in_music_room").tapCenter()
        expectLastCall(app, "input_boolean.turn_on entity_id=input_boolean.guests_staying_in_music_room")
    }

    func testMachETilesAreReadOnly() {
        let app = launch("machE")
        let doors = tile(app, "lock.fordpass_3fmtk3su5mma09266_doorlock")
        XCTAssertTrue(doors.waitForExistence(timeout: 5))
        XCTAssertEqual(doors.value as? String, "Locked")
        XCTAssertFalse(app.buttons["household.tile.lock.fordpass_3fmtk3su5mma09266_doorlock"].exists, "Mach-E tiles must not be buttons")
        XCTAssertEqual(tile(app, "sensor.fordpass_3fmtk3su5mma09266_elvehcharging").value as? String, "ChargingAC")
    }

    func testUnavailableEntitiesDisableTheirControls() {
        let app = launch("admin", unavailable: true)
        let autoLock = tile(app, "input_boolean.is_front_door_auto_lock_enabled")
        XCTAssertTrue(autoLock.waitForExistence(timeout: 5))
        XCTAssertEqual(autoLock.value as? String, "Unavailable")
        XCTAssertFalse(autoLock.isEnabled)
        openSheet(app, "presenceOverrides")
        // The room opens so it can say why; its choices are disabled and nothing is sent.
        let kitchen = app.buttons["presence.room.switch.kitchen_presence_kitchen_lights_presence_allowed"]
        XCTAssertTrue(kitchen.waitForExistence(timeout: 5))
        XCTAssertEqual(kitchen.value as? String, "Unavailable")
        kitchen.tap()
        let enabled = app.buttons["presence.option.enabled"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 5))
        for mode in ["enabled", "off", "paused", "quieted"] {
            XCTAssertFalse(app.buttons["presence.option.\(mode)"].isEnabled, "\(mode) should be disabled")
        }
        app.buttons["household.sheet.done"].firstMatch.tap()
        XCTAssertTrue(enabled.waitForNonExistence(timeout: 5), "Done on the detail should close the sheet")
        XCTAssertFalse(lastCall(app).label.contains("set_automation_state"), "An unavailable room sent \(lastCall(app).label)")
    }

    // MARK: - Audits and screenshots

    /// Full audit (with the AX5 relaunch) of every page, both Admin sheets and the presence detail.
    func testPagesPassAccessibilityAudit() throws {
        for page in ["admin", "specialDeviceModes", "guests", "machE"] {
            let app = launch(page, clean: true)
            try FentonHomeApp.audit(app) { self.launch(page, arguments: FentonHomeApp.ax5, clean: true) }
        }
        for sheet in ["presenceOverrides", "autoReset"] {
            let app = launch("admin", clean: true)
            openSheet(app, sheet)
            try FentonHomeApp.audit(app) {
                let large = self.launch("admin", arguments: FentonHomeApp.ax5, clean: true)
                self.openSheet(large, sheet)
                return large
            }
        }
        func openPresenceDetail(_ app: XCUIApplication) {
            openSheet(app, "presenceOverrides")
            app.buttons["presence.room.switch.kitchen_presence_kitchen_lights_presence_allowed"].tap()
            XCTAssertTrue(app.buttons["presence.option.enabled"].waitForExistence(timeout: 5))
        }
        let app = launch("admin", clean: true)
        openPresenceDetail(app)
        // With the AX5 page, "may be clipped" is checked against the text at AX5 like the sheets above; without it the
        // folded Duo's two-line option titles could not be disproved (2026-10-14).
        try FentonHomeApp.audit(app) {
            let large = self.launch("admin", arguments: FentonHomeApp.ax5, clean: true)
            openPresenceDetail(large)
            return large
        }
    }

    /// Screenshots of each page, sheet and the presence detail in the current pose (iPad: also landscape).
    func testCaptureHouseholdScreens() throws {
        let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]
        for orientation in orientations {
            if orientation != .unknown { XCUIApplication().terminate(); XCUIDevice.shared.orientation = orientation }
            let suffix = orientation == .landscapeLeft ? "landscape" : orientation == .portrait ? "portrait" : "current"
            for page in ["admin", "specialDeviceModes", "guests", "machE"] {
                let app = launch(page, clean: true)
                sleep(1)
                keepScreenshot(app, "\(page)-\(suffix)")
            }
            let app = launch("admin", clean: true)
            reveal(app.descendants(matching: .any)["admin.relayWarning"], in: app)
            keepScreenshot(app, "admin-lower-\(suffix)")
            openSheet(app, "presenceOverrides")
            keepScreenshot(app, "presence-overrides-\(suffix)")
            app.buttons["presence.room.switch.hallway_presence_hallway_lights_presence_allowed"].tap()
            XCTAssertTrue(app.buttons["presence.option.enabled"].waitForExistence(timeout: 5))
            sleep(1)
            keepScreenshot(app, "presence-detail-\(suffix)")
            backFromPresenceDetail(app) // Back to the grid; the next sheet opens from the page.
            XCTAssertTrue(app.buttons["household.sheet.done"].firstMatch.waitForExistence(timeout: 5))
            app.buttons["household.sheet.done"].firstMatch.tap()
            openSheet(app, "autoReset")
            keepScreenshot(app, "auto-reset-\(suffix)")
        }
        // Only iPad rotates here; setting the orientation on an unfolded Duo hangs the runner (devices.md).
        if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
    }

    // MARK: - Live

    /// The Settings tab lists the household rows and each opens its live page. Read-only: nothing is tapped
    /// inside the pages, so the house is never switched.
    func testSettingsRowsOpenTheLivePages() throws {
        let app = try FentonHomeApp.launchSignedIn()
        showSettingsTab(app)
        for page in ["specialDeviceModes", "guests", "machE", "admin"] {
            let row = app.buttons["settings.topic.\(page)"]
            app.revealSettingsRow(row)
            XCTAssertTrue(row.waitForExistence(timeout: 5), "\(page) row missing")
            XCTAssertGreaterThanOrEqual(row.frame.height, 43)
            row.tap()
            XCTAssertTrue(app.descendants(matching: .any)["household.\(page)"].waitForExistence(timeout: 10), "\(page) did not open")
            // Where Settings splits, the next row replaces the trailing pane; elsewhere go back to the list.
            if page != "admin", !app.buttons["split.close"].exists { goBack(app) }
        }
        // Admin last: its audit relaunches at AX5 (for the Dynamic Type check), which leaves `app` there.
        XCTAssertTrue(waitForLiveAdmin(app), "Live state did not load")
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            self.showSettingsTab(large)
            self.reveal(large.buttons["settings.topic.admin"], in: large, scroller: large.settingsList).tap()
            XCTAssertTrue(self.waitForLiveAdmin(large), "Live state did not load at AX5")
            return large
        }
    }

    /// Goes to Settings: the profile avatar's Account sheet (direction G).
    private func showSettingsTab(_ app: XCUIApplication) {
        app.openAccountSettings()
    }

    /// Waits for the live Admin page's first tile to show a real state.
    private func waitForLiveAdmin(_ app: XCUIApplication) -> Bool {
        let autoLock = tile(app, "input_boolean.is_front_door_auto_lock_enabled")
        return autoLock.waitForExistence(timeout: 15) && autoLock.value as? String != "Unavailable"
    }
}

private extension XCUIElement {
    /// Taps the middle of a toggle tile. Plain `tap()` on these switch-type elements often didn't reach the
    /// tile on the iPhone Duo (iOS 27.1) while button tiles were fine; the tile takes taps anywhere.
    func tapCenter() {
        coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}
