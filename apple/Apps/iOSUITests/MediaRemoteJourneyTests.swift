import XCTest

/// The media remote sheet in the debug gallery (fixture state, recording service caller; nothing reaches the
/// house): semantics, service calls, layout per pose, accessibility audits and screenshots on iPhone, iPhone Duo
/// and iPad (`.agents/patterns/media-remote.md`).
@MainActor
final class MediaRemoteJourneyTests: JourneyTestCase {
    // MARK: - Helpers

    /// An element each section shows once the sheet is up: power on Remote (and in every section in two
    /// columns), otherwise the section's first control.
    private func readyID(_ remote: String, tab: String) -> String {
        switch (remote, tab) {
        case (_, "controls"): "remote.power"
        case ("music-room-remote", "apps"): "remote.app.Fortnite"
        case (_, "apps"): "remote.app.Plex"
        case ("music-room-remote", "devices"): "remote.device.TV"
        case (_, "devices"): "remote.device.Projector"
        case (_, "hueSync"): "remote.hue.Light Sync"
        default: "remote.tabs"
        }
    }

    private func launch(_ remote: String, tab: String = "controls", arguments: [String] = []) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "media-remote"
        app.launchEnvironment["FENTON_GALLERY_REMOTE"] = remote
        app.launchEnvironment["FENTON_GALLERY_TAB"] = tab
        app.launchEnvironment["FENTON_GALLERY_OFFLINE"] = "1"
        app.launchArguments += arguments
        app.launch()
        let ready = element(readyID(remote, tab: tab), in: app)
        XCTAssertTrue(ready.waitForExistence(timeout: 30), "Remote sheet did not open")
        XCTAssertTrue(ready.wait(for: \.isHittable, toEqual: true, timeout: 10), "Sheet still presenting")
        sleep(1) // Mid-animation frames fail contrast and clipping.
        return app
    }

    private func expectCall(_ expected: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        expectLastCall(expected, in: app, file: file, line: line)
    }

    /// Flips a list row's switch: XCUITest taps a row's middle, which lands on its label and leaves the switch alone.
    private func flip(_ toggle: XCUIElement, in app: XCUIApplication) {
        reveal(toggle, in: app)
        let knob = toggle.switches.firstMatch
        if knob.exists { knob.tap() } else { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
    }

    /// Scrolls toward `element` in short drags until it is hittable: full swipes overshoot long columns
    /// (AX5, the unfolded Duo), and the element may sit above or below the visible part.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, down: Bool = false) {
        let window = app.windows.firstMatch.frame
        for _ in 0..<24 where !element.isHittable {
            let above = element.exists ? element.frame.midY < window.midY : down
            // Drag in the element's own column (in two columns each side scrolls on its own), in screen points
            // from the window origin: normalized app coordinates stay portrait in a landscape window
            // (FestivalNativeApps xcuitest pitfalls).
            // On iPhone Duo, gestures from `app.coordinate` never reach the inner display; anchor them on the window
            // and keep clear of the system vertical bar at its trailing edge (FestivalNativeApps `screenOrigin`).
            var x = element.exists && element.frame.midX > 0 ? element.frame.midX : window.midX
            if FentonHomeApp.family == .iPhoneDuo { x = min(x, window.maxX - 96) }
            let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: -window.minX, dy: -window.minY))
            let from = origin.withOffset(CGVector(dx: x, dy: window.minY + window.height * (above ? 0.35 : 0.65)))
            let to = from.withOffset(CGVector(dx: 0, dy: above ? 220 : -220))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        if !element.isHittable { keep(app, "reveal-failed") }
        let scrolls = app.scrollViews.allElementsBoundByIndex.map { "\($0.frame)" }.joined(separator: "; ")
        XCTAssertTrue(element.isHittable, "\(element) never came into view: frame \(element.frame), window \(window), scroll views \(scrolls)")
    }

    private func isSelected(_ element: XCUIElement) -> Bool { element.isSelected }

    private func waitFor(_ element: XCUIElement, _ format: String, _ argument: String, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: format, argument), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    // MARK: - Controls

    /// Power and the d-pad: labels, values, 44 pt targets, the d-pad group, and the calls they send.
    func testPowerAndDirectionalPad() {
        let app = launch("living-room-shield")
        let power = app.buttons["remote.power"]
        XCTAssertEqual(power.label, "Power")
        XCTAssertEqual(power.value as? String, "On")
        assertTarget(power)

        let pad = element("remote.dpad", in: app)
        // Power sits in the pad's top row, in the cell right of Up, so no row of its own (owner, 2026-10-13).
        let up = pad.buttons["Up"]
        XCTAssertEqual(power.frame.midY, up.frame.midY, accuracy: 1, "Power shares Up's row")
        XCTAssertGreaterThan(power.frame.minX, up.frame.maxX, "Power is right of Up")
        XCTAssertEqual(power.frame.width, up.frame.width, accuracy: 1, "Power is a d-pad-sized button")
        // Direction G: Back and Home take the pad's leading corners, the keyboard its trailing bottom corner.
        let back = app.buttons["remote.button.Back"]
        XCTAssertEqual(back.frame.midY, up.frame.midY, accuracy: 1, "Back shares Up's row")
        XCTAssertLessThan(back.frame.maxX, up.frame.minX, "Back is left of Up")
        let down = pad.buttons["Down"]
        XCTAssertEqual(app.buttons["remote.button.Home"].frame.midY, down.frame.midY, accuracy: 1, "Home shares Down's row")
        XCTAssertEqual(app.buttons["remote.button.Keyboard"].frame.midY, down.frame.midY, accuracy: 1, "The keyboard shares Down's row")
        XCTAssertEqual(pad.label, "Living Room SHIELD remote controls")
        for label in ["Back", "Up", "Left", "Select", "Right", "Home", "Down"] {
            let button = pad.buttons[label]
            XCTAssertTrue(button.exists, label)
            XCTAssertTrue(button.isEnabled, label)
            assertTarget(button)
        }
        pad.buttons["Up"].tap()
        expectCall("remote.send_command command=DPAD_UP entity_id=remote.living_room_shield", in: app)
        pad.buttons["Select"].tap()
        expectCall("remote.send_command command=DPAD_CENTER entity_id=remote.living_room_shield", in: app)

        // Power off: the fixture echoes the SHIELD off, power flips and the directions disable; power stays enabled.
        power.tap()
        expectCall("remote.send_command command=POWER entity_id=remote.living_room_shield", in: app)
        XCTAssertTrue(waitFor(power, "value == %@", "Off"), "Power value is \(power.value ?? "nil")")
        XCTAssertTrue(power.isEnabled, "Power is how the device turns back on")
        XCTAssertFalse(pad.buttons["Up"].isEnabled)
        XCTAssertFalse(app.buttons["remote.button.Play"].isEnabled)
    }

    /// The Music Room power button is a switch with an On/Off value.
    func testMusicRoomPowerIsASwitch() {
        let app = launch("music-room-remote")
        let power = app.switches["remote.power"]
        XCTAssertTrue(power.exists, "Music Room power is a switch")
        XCTAssertEqual(power.value as? String, "On")
        power.tap()
        expectCall("script.music_room_tv_off", in: app)
        XCTAssertTrue(waitFor(power, "value == %@", "Off"), "Optimistic off shows at once")
    }

    /// Navigation, playback and volume rows send their configured calls.
    func testNavigationPlaybackAndVolume() {
        let app = launch("master-bedroom-apple-tv")
        XCTAssertTrue(element("remote.dpad", in: app).buttons["Select"].exists)
        app.buttons["remote.button.Menu"].tap()
        expectCall("remote.send_command command=menu entity_id=remote.master_bedroom_apple_tv", in: app)
        XCTAssertFalse(app.buttons["remote.button.Keyboard"].exists, "Apple TV has no keyboard")
        let volumeUp = app.buttons["remote.button.Volume Up"]
        assertTarget(volumeUp)
        volumeUp.tap()
        expectCall("media_player.volume_up entity_id=media_player.primary_bedroom", in: app)
        let mute = app.buttons["remote.button.Mute"]
        mute.tap()
        expectCall("script.toggle_sonos_mute sonosdevice=[media_player.primary_bedroom]", in: app)
        let play = app.buttons["remote.button.Play"]
        reveal(play, in: app)
        play.tap()
        expectCall("remote.send_command command=play entity_id=remote.master_bedroom_apple_tv", in: app)
        let slider = app.sliders["remote.volume"]
        reveal(slider, in: app)
        XCTAssertEqual(slider.label, "Volume volume")
        slider.adjust(toNormalizedSliderPosition: 0.8)
        XCTAssertTrue(waitFor(app.staticTexts["gallery.lastCall"].firstMatch, "label CONTAINS %@", "media_player.volume_set"), lastCall(in: app))
        XCTAssertTrue(lastCall(in: app).contains("entity_id=media_player.primary_bedroom"), lastCall(in: app))
    }

    /// The keyboard opens an inline field; Send types the text with quotes escaped and closes it.
    func testKeyboardSendsEscapedText() {
        let app = launch("living-room-shield")
        let keyboard = app.buttons["remote.button.Keyboard"]
        XCTAssertEqual(keyboard.value as? String, "Collapsed")
        keyboard.tap()
        let field = app.textFields["remote.keyboard.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(keyboard.value as? String, "Expanded")
        XCTAssertFalse(app.buttons["remote.keyboard.send"].isEnabled, "Blank text can't be sent")
        field.tap()
        field.typeText("it's")
        let send = app.buttons["remote.keyboard.send"]
        reveal(send, in: app)
        send.tap()
        expectCall(#"androidtv.adb_command command=input text 'it'\''s' entity_id=media_player.living_room_shield_2"#, in: app)
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
    }

    // MARK: - Tabs

    /// Only sections with content appear, in the bottom glass bar, and they switch the content: in one column the
    /// pad belongs to Remote; in two columns it stays in the leading column for every section.
    func testTabsShowOnlyWhatTheRemoteHas() {
        let app = launch("theater-room-shield")
        let tabs = app.segmentedControls["remote.tabs"]
        XCTAssertTrue(tabs.exists)
        XCTAssertEqual(tabs.buttons.count, 3)
        XCTAssertGreaterThan(tabs.frame.midY, app.windows.firstMatch.frame.midY, "The section bar sits at the bottom")
        tabs.buttons["Devices"].tap()
        XCTAssertTrue(element("remote.device.Projector", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(tabs.buttons["Devices"].isSelected)
        let power = element("remote.power", in: app)
        if element("remote.layout.twoColumn", in: app).exists {
            XCTAssertTrue(power.exists, "The pad stays beside every section in two columns")
        } else {
            XCTAssertFalse(power.exists, "The pad belongs to the Remote section in one column")
            tabs.buttons["Remote"].tap()
            XCTAssertTrue(power.waitForExistence(timeout: 5), "Remote brings the pad back")
        }
    }

    /// App tiles launch apps; the running app carries the selected trait.
    func testAppsLaunchAndShowTheRunningApp() {
        let app = launch("music-room-remote", tab: "apps")
        let fortnite = app.buttons["remote.app.Fortnite"]
        XCTAssertTrue(fortnite.waitForExistence(timeout: 5))
        XCTAssertEqual(fortnite.label, "Fortnite")
        XCTAssertFalse(isSelected(fortnite))
        assertTarget(fortnite)
        fortnite.tap()
        expectCall("script.music_room_fortnite", in: app)
        XCTAssertTrue(fortnite.wait(for: \.isSelected, toEqual: true, timeout: 5))

        let living = launch("living-room-shield", tab: "apps")
        let plex = living.buttons["remote.app.Plex"]
        XCTAssertTrue(plex.waitForExistence(timeout: 5))
        plex.tap()
        expectCall("script.launch_app_on_media_player app_id=com.plexapp.android entity=media_player.living_room_shield remote_entity=remote.living_room_shield", in: living)
    }

    /// Device rows are switches that toggle their devices; the PC presses the matching input button.
    func testDevicesToggle() {
        let app = launch("theater-room-shield", tab: "devices")
        let projector = app.switches["remote.device.Projector"]
        XCTAssertTrue(projector.waitForExistence(timeout: 5))
        XCTAssertTrue(projector.label.hasPrefix("Projector"), projector.label)
        XCTAssertEqual(projector.value as? String, "1")
        assertTarget(projector)
        flip(projector, in: app)
        expectCall("media_player.toggle entity_id=media_player.sony_projector", in: app)
        XCTAssertTrue(waitFor(projector, "value == %@", "0"), "Projector value is \(projector.value ?? "nil")")
        flip(app.switches["remote.device.Theater Room PC"], in: app)
        expectCall("input_button.press entity_id=input_button.theater_pc_on", in: app)
    }

    /// The Music Room's sources are a checkmark choice and its speaker only reports its state.
    func testMusicRoomSourcesAreAChoice() {
        let app = launch("music-room-remote", tab: "devices")
        let server = app.buttons["remote.device.Server"]
        reveal(server, in: app)
        XCTAssertFalse(server.isSelected)
        server.tap()
        XCTAssertTrue(server.wait(for: \.isSelected, toEqual: true, timeout: 5), "The chosen source is selected")
        XCTAssertFalse(app.buttons["remote.device.Sonos Beam"].exists, "A state-only device is not a button")
        XCTAssertTrue(element("remote.device.Sonos Beam", in: app).exists)
    }

    /// Hue Sync: toggles are switches, modes and choices are selected, unplugged inputs are disabled.
    func testHueSyncControls() {
        let app = launch("music-room-remote", tab: "hueSync")
        let lightSync = app.switches["remote.hue.Light Sync"]
        XCTAssertTrue(lightSync.waitForExistence(timeout: 5))
        XCTAssertEqual(lightSync.value as? String, "0")
        let modes = app.segmentedControls["remote.hue.mode"]
        reveal(modes, in: app)
        XCTAssertTrue(modes.buttons["Video"].isSelected)
        let game = modes.buttons["Game"]
        XCTAssertFalse(game.isSelected)
        game.tap()
        expectCall("select.select_option entity_id=select.music_room_music_room_sync_box_sync_mode option=game", in: app)
        XCTAssertTrue(game.wait(for: \.isSelected, toEqual: true, timeout: 5))
        XCTAssertTrue(waitFor(lightSync, "value == %@", "1"), "Choosing a mode starts syncing")

        let intensity = app.segmentedControls["remote.hue.intensity"]
        reveal(intensity, in: app)
        intensity.buttons["High"].tap()
        expectCall("select.select_option entity_id=select.music_room_music_room_sync_box_intensity option=high", in: app)
        let unplugged = element("remote.hue.hdmi.HDMI 4", in: app)
        reveal(unplugged, in: app)
        XCTAssertFalse(unplugged.isEnabled)
        XCTAssertTrue(element("remote.hue.hdmi.HDMI 1", in: app).isSelected)
    }

    // MARK: - Layout

    /// Two columns only on iPad landscape and unfolded Duo landscape; iPhone and every portrait are one column.
    func testLayoutFollowsThePose() {
        if FentonHomeApp.family == .iPad {
            XCUIDevice.shared.orientation = .portrait
            var app = launch("theater-room-shield")
            XCTAssertTrue(element("remote.layout.singleColumn", in: app).exists, "iPad portrait is one column")
            XCUIDevice.shared.orientation = .landscapeLeft
            app = launch("theater-room-shield")
            XCTAssertTrue(element("remote.layout.twoColumn", in: app).waitForExistence(timeout: 5), "iPad landscape splits")
            XCTAssertLessThan(element("remote.power", in: app).frame.maxX, app.buttons["remote.button.Play"].frame.minX,
                              "The pad leads, the section trails")
            return
        }
        let app = launch("theater-room-shield")
        let window = app.windows.firstMatch.frame
        let landscape = window.width > window.height
        if FentonHomeApp.family == .iPhone { XCTAssertFalse(landscape, "iPhone stays portrait") }
        let expected = FentonHomeApp.family == .iPhoneDuo && landscape && window.width >= 720
            ? "remote.layout.twoColumn" : "remote.layout.singleColumn"
        XCTAssertTrue(element(expected, in: app).exists, "\(FentonHomeApp.family) window \(window.size) expects \(expected)")
    }

    // MARK: - Accessibility audits

    private func audit(_ remote: String, tab: String) throws {
        let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]
        for orientation in orientations {
            if orientation != .unknown { XCUIDevice.shared.orientation = orientation }
            let app = launch(remote, tab: tab)
            try FentonHomeApp.audit(app) { self.launch(remote, tab: tab, arguments: FentonHomeApp.ax5) }
        }
    }

    func testControlsTabPassesAudit() throws { try audit("living-room-shield", tab: "controls") }
    func testAppsTabPassesAudit() throws { try audit("living-room-shield", tab: "apps") }
    func testDevicesTabPassesAudit() throws { try audit("theater-room-shield", tab: "devices") }
    func testHueSyncTabPassesAudit() throws { try audit("music-room-remote", tab: "hueSync") }

    /// At AX5 the d-pad (with power) grows and every control stays reachable by scrolling.
    func testLargestTextKeepsControlsReachable() {
        let regular = launch("living-room-shield")
        let regularHeight = element("remote.power", in: regular).frame.height
        let app = launch("living-room-shield", arguments: FentonHomeApp.ax5)
        XCTAssertGreaterThan(element("remote.power", in: app).frame.height, regularHeight * 1.2, "Power grows with the d-pad at AX5")
        for id in ["remote.button.Volume Up", "remote.button.Keyboard", "remote.button.Play"] {
            reveal(app.buttons[id], in: app)
        }
    }

    /// Online, the sheet holds a centered spinner until every app's artwork has loaded, then shows it all at once:
    /// no tile is ever drawn empty and filled in later.
    func testArtworkLoadsBeforeTheSheetShows() {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "media-remote"
        app.launchEnvironment["FENTON_GALLERY_REMOTE"] = "living-room-shield"
        app.launchEnvironment["FENTON_GALLERY_TAB"] = "apps"
        app.launch()
        let plex = element("remote.app.Plex", in: app)
        XCTAssertTrue(plex.waitForExistence(timeout: 30), "Remote sheet did not open")
        XCTAssertFalse(element("contentGate.spinner", in: app).exists, "The spinner is gone once the content shows")
        XCTAssertTrue(element("remote.app.Plex", in: app).isHittable, "App tiles show with the rest of the content")
    }

    // MARK: - Screenshots

    /// Controls, Apps, Devices (Theater) and Hue Sync (Music Room) in the current pose (iPad: both orientations),
    /// named `remote-<tab>-<orientation>`.
    func testCaptureRemoteScreens() {
        let shots = [("living-room-shield", "controls"), ("living-room-shield", "apps"),
                     ("theater-room-shield", "devices"), ("music-room-remote", "hueSync")]
        let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]
        for orientation in orientations {
            if orientation != .unknown { XCUIDevice.shared.orientation = orientation }
            let suffix = orientation == .landscapeLeft ? "landscape" : orientation == .portrait ? "portrait" : "current"
            for (remote, tab) in shots {
                let app = FentonHomeApp.makeApp()
                app.launchEnvironment["FENTON_GALLERY"] = "media-remote"
                app.launchEnvironment["FENTON_GALLERY_REMOTE"] = remote
                app.launchEnvironment["FENTON_GALLERY_TAB"] = tab
                app.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1"
                app.launch()
                XCTAssertTrue(element(readyID(remote, tab: tab), in: app).waitForExistence(timeout: 30))
                sleep(3) // Artwork loads from the server's public /local folder.
                keep(app, "remote-\(tab)-\(suffix)")
            }
        }
    }

    private func keep(_ app: XCUIApplication, _ name: String) {
        // Upright: the raw capture stays portrait in landscape (see RenderedContrast).
        let shot = XCUIScreen.main.screenshot().image
        let format = UIGraphicsImageRendererFormat()
        format.scale = shot.scale
        let upright = UIGraphicsImageRenderer(size: shot.size, format: format).image { _ in shot.draw(at: .zero) }
        let attachment = XCTAttachment(image: upright)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        // XCUIScreen captures only the outer panel, which is dark on an unfolded iPhone Duo. With
        // FENTON_CAPTURE_DIR set, the host captures the lit panel: `<name>.ready` asks, `<name>.done` answers.
        guard let folder = ProcessInfo.processInfo.environment["FENTON_CAPTURE_DIR"], !folder.isEmpty else { return }
        let ready = URL(fileURLWithPath: folder).appendingPathComponent("\(name).ready")
        let done = URL(fileURLWithPath: folder).appendingPathComponent("\(name).done")
        FileManager.default.createFile(atPath: ready.path, contents: nil)
        let deadline = Date().addingTimeInterval(30)
        while !FileManager.default.fileExists(atPath: done.path), Date() < deadline { usleep(200_000) }
    }
}
