import XCTest

/// Room pages, Quick Links and the room grid in the debug gallery (fixture state, recording service caller;
/// nothing reaches the house): semantics, service calls, sheets, accessibility audits and screenshots on iPhone,
/// iPhone Duo and iPad (`.agents/pages/rooms/`).
@MainActor
final class RoomsJourneyTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    override func tearDown() {
        MainActor.assumeIsolated {
            if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
        }
    }

    // MARK: - Helpers

    private func launch(room: String? = nil, quickLinks: Bool = false, clean: Bool = false, scenario: String? = nil,
                        arguments: [String] = []) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "rooms"
        if let scenario { app.launchEnvironment["FENTON_GALLERY_SCENARIO"] = scenario }
        app.launchEnvironment["FENTON_GALLERY_OFFLINE"] = "1"
        if let room { app.launchEnvironment["FENTON_GALLERY_ROOM"] = room }
        if quickLinks { app.launchEnvironment["FENTON_GALLERY_QUICK_LINKS"] = "1" }
        if clean { app.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1" }
        app.launchArguments += arguments
        app.launch()
        let ready = room.map { element("room.scroll.\($0)", in: app) } ?? (quickLinks ? element("quickLinks.rooms", in: app) : app.buttons["gallery.quickLinks"])
        XCTAssertTrue(ready.waitForExistence(timeout: 30), "Gallery did not open")
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

    /// Scrolls the window in short drags until `element` is hittable (see `MediaRemoteJourneyTests.reveal`).
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        for _ in 0..<24 where !element.isHittable {
            let above = element.exists && element.frame.midY < window.midY && element.frame.maxY > 0
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

    private func assertTarget(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(element.frame.width, 43, element.label, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 43, element.label, file: file, line: line)
    }

    // MARK: - Room page

    /// The Living Room: status chips, a vent sheet, the vacuum fallback and the remote sheet.
    func testLivingRoomChipsAndSheets() {
        let app = launch(room: "living-room")
        XCTAssertTrue(app.navigationBars["Living Room"].exists)
        let occupancy = element("room.chip.Occupancy", in: app)
        XCTAssertTrue(occupancy.exists)
        assertTarget(occupancy)

        let lights = element("room.chip.Lights", in: app)
        lights.tap()
        XCTAssertTrue(element("room.sheet.lights-living-room", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Living Room Lights"].exists)
        app.buttons["Close"].tap()

        let vents = element("room.card.Vents", in: app)
        reveal(vents, in: app)
        vents.tap()
        XCTAssertTrue(element("room.entity.cover.living_room_vent_1_vent", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["room.entity.cover.living_room_vent_1_vent"].exists, "Read-only tiles are not buttons")
        XCTAssertEqual(element("room.entity.cover.living_room_vent_1_vent", in: app).value as? String, "Open · 60%",
                       "An open vent shows its position, as in Advanced Controls")
        // It fills with the Vents family while open (`#3B58B8`), like Advanced Controls' vent tiles.
        if let capture = RenderedContrast.Capture.screen() {
            let frame = element("room.entity.cover.living_room_vent_1_vent", in: app).frame
            let sample = TileGeometry.rgb(at: CGPoint(x: frame.minX + 10, y: frame.maxY - 10), in: capture)
            XCTAssertTrue(sample.map { TileGeometry.matchesGlass($0, 0x3B58B8, heightFraction: 1 - 10 / frame.height) } ?? false,
                          "Open vent fill: \(String(describing: sample))")
        }
        app.buttons["Close"].tap()

        let remote = element("room.card.Living Room Remote", in: app)
        reveal(remote, in: app)
        remote.tap()
        XCTAssertTrue(element("remote.power", in: app).waitForExistence(timeout: 5), "Remote opens the media remote sheet")
    }

    /// The room rail's chips keep their text at 4.5:1 as rendered in their colours (Climate and Air Quality follow Home
    /// Assistant's colours, Occupancy fills when detected, Window reads the house), each named with its state.
    func testLivingRoomChipsReadOnTheirColours() throws {
        let app = launch(room: "living-room", clean: true)
        for title in ["Lights", "Climate", "Occupancy", "Window", "Air Quality"] {
            let chip = element("room.chip.\(title)", in: app)
            XCTAssertTrue(chip.waitForExistence(timeout: 10), title)
            XCTAssertTrue(chip.label.hasPrefix("\(title), "), chip.label)
            assertTarget(chip)
            if chip.frame.maxX <= app.windows.firstMatch.frame.maxX,
               let capture = RenderedContrast.Capture.screen(), let ratio = RenderedContrast.ratio(of: chip.frame, in: capture) {
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(title) chip measured \(ratio):1")
            }
        }
        keepScreenshot(app, "room-chips-\(FentonHomeApp.family)")
    }

    /// Towel racks send an explicit turn_on, then turn_off, never toggle.
    func testTowelRackSendsExplicitPower() {
        let app = launch(room: "guest-bathroom")
        let towel = app.switches["room.card.Towel Rack"]
        reveal(towel, in: app)
        XCTAssertEqual(towel.value as? String, "Off")
        towel.tap()
        expectCall("switch.turn_on entity_id=switch.guest_bathroom_towel_rack_switch_top", in: app)
        let on = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "On"), object: towel)
        XCTAssertEqual(XCTWaiter().wait(for: [on], timeout: 5), .completed, "The fixture echoes the rack on")
        towel.tap()
        expectCall("switch.turn_off entity_id=switch.guest_bathroom_towel_rack_switch_top", in: app)
    }

    /// Music Room sources are selections that share the remote's optimistic state.
    func testMusicRoomSources() {
        let app = launch(room: "music-room")
        let xbox = element("room.card.Xbox", in: app)
        reveal(xbox, in: app)
        xbox.tap()
        XCTAssertNotEqual(app.staticTexts["gallery.lastCall"].firstMatch.label, "Last call: None")
    }

    /// The bathroom fan tile's Lock and Power send the fan script's explicit target state, and device cards open
    /// their lane's sheets (fan, air quality); fixture state only.
    func testBathroomFanTileAndDeviceSheets() {
        let app = launch(room: "guest-bathroom")
        // Toggle accessories are switches to XCUITest (like the towel rack).
        let power = app.switches["room.fan.switch.guest_bathroom_fan_switch_top.power"]
        let lock = app.switches["room.fan.switch.guest_bathroom_fan_switch_top.lock"]
        reveal(power, in: app)
        XCTAssertEqual(power.value as? String, "Off")
        XCTAssertEqual(lock.value as? String, "Off")
        assertTarget(power)
        assertTarget(lock)
        power.tap()
        let call = app.staticTexts["gallery.lastCall"].firstMatch
        let sent = NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "script.guest_bathroom_fan_command", "target_power=on")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: sent, object: call)], timeout: 10), .completed,
                       "Power sends an explicit target, got '\(call.label)'")
        XCTAssertFalse(call.label.contains("toggle"))

        element("room.card.Fan", in: app).tap()
        XCTAssertTrue(element("device.sheet.fan", in: app).waitForExistence(timeout: 10), "The fan tile opens the fan sheet")
        app.buttons["device.sheet.done"].tap()

        let living = launch(room: "living-room")
        let purifier = element("room.card.Air Purifier", in: living)
        reveal(purifier, in: living)
        purifier.tap()
        XCTAssertTrue(element("device.sheet.purifier", in: living).waitForExistence(timeout: 10), "Air Purifier opens the air quality sheet")
    }

    // MARK: - Bathroom fan tile (owner design, 2026-10-17)

    /// The fan tile and its two buttons by the fan's power entity.
    private func fanButtons(_ power: String, in app: XCUIApplication) -> (tile: XCUIElement, lock: XCUIElement, power: XCUIElement) {
        (element("room.card.Fan", in: app), app.switches["room.fan.\(power).lock"], app.switches["room.fan.\(power).power"])
    }

    /// The chevron's ink, measured clear of the rail's own edge (the rail ends 32 pt in from the tile's edge).
    private func chevronBounds(of tile: XCUIElement) throws -> CGRect {
        let capture = try XCTUnwrap(RenderedContrast.Capture.screen())
        let frame = tile.frame
        let background = try XCTUnwrap(TileGeometry.rgb(at: CGPoint(x: frame.maxX - 18, y: frame.minY + 6), in: capture))
        let region = CGRect(x: frame.maxX - 29, y: frame.minY + 14, width: 25, height: frame.height - 28)
        return try XCTUnwrap(TileGeometry.inkBounds(in: region, background: background, capture: capture), "No chevron drawn")
    }

    /// The Power button no longer sits under the chevron: the rail is vertically centred, its circles are 44 pt, and
    /// the chevron has its own slot to the right of them. Off/unlocked (Guest) and on/locked/timed (Master).
    func testFanRailIsCentredAndClearOfTheChevron() throws {
        let cases: [(room: String, power: String, lit: Bool)] = [
            ("guest-bathroom", "switch.guest_bathroom_fan_switch_top", false),
            ("master-bathroom", "switch.master_bathroom_fan_switch_top", true),
        ]
        for fan in cases {
            let app = launch(room: fan.room, clean: true)
            let (tile, lock, power) = fanButtons(fan.power, in: app)
            reveal(power, in: app)
            for button in [lock, power] {
                assertTarget(button)
                XCTAssertEqual(button.frame.width, button.frame.height, accuracy: 1, "\(fan.room): a circle")
                XCTAssertEqual(button.frame.midY, tile.frame.midY, accuracy: 2, "\(fan.room): centred on the tile")
            }
            XCTAssertLessThan(lock.frame.maxX, power.frame.minX, "Lock then Power, not overlapping")
            let chevron = try chevronBounds(of: tile)
            XCTAssertFalse(power.frame.intersects(chevron), "\(fan.room): the chevron is not under Power")
            XCTAssertGreaterThanOrEqual(chevron.minX - power.frame.maxX, 6, "\(fan.room): spacing before the chevron")
            XCTAssertEqual(chevron.midY, tile.frame.midY, accuracy: 3, "\(fan.room): the chevron stays centred")
            // Active: a solid white circle. Inactive: a translucent one, never white.
            let capture = try XCTUnwrap(RenderedContrast.Capture.screen())
            for button in [lock, power] {
                let sample = try XCTUnwrap(TileGeometry.rgb(at: CGPoint(x: button.frame.minX + 5, y: button.frame.midY), in: capture))
                if fan.lit {
                    XCTAssertTrue(TileGeometry.matches(sample, 0xFFFFFF, tolerance: 12), "\(fan.room) \(button.label) is solid white: \(sample)")
                } else {
                    XCTAssertLessThan(sample.r, 160, "\(fan.room) \(button.label) is translucent, not white: \(sample)")
                }
            }
            keepScreenshot(app, "fan-tile-\(fan.room)-\(FentonHomeApp.family)")
        }
    }

    /// One short status line, with the lock spoken rather than written: VoiceOver reads "on, off in 12 minutes, locked".
    func testFanTileValueSpeaksPowerTimerAndLock() {
        let master = launch(room: "master-bathroom")
        let tile = element("room.card.Fan", in: master)
        reveal(tile, in: master)
        let value = tile.value as? String ?? ""
        XCTAssertTrue(value.hasPrefix("on, off in 1") && value.hasSuffix(" minutes, locked"), "Spoken value: \(value)")
        XCTAssertEqual(master.switches["room.fan.switch.master_bathroom_fan_switch_top.lock"].value as? String, "On")
        XCTAssertEqual(master.switches["room.fan.switch.master_bathroom_fan_switch_top.power"].value as? String, "On")
        let guest = launch(room: "guest-bathroom")
        let off = element("room.card.Fan", in: guest)
        reveal(off, in: guest)
        XCTAssertEqual(off.value as? String, "off")
        XCTAssertEqual(guest.switches["room.fan.switch.guest_bathroom_fan_switch_top.lock"].value as? String, "Off")
    }

    /// An unavailable fan shows no buttons (no dead controls) and says so; the tile still opens its sheet.
    func testUnavailableFanHidesItsButtons() {
        let app = launch(room: "guest-bathroom", scenario: "fan-unavailable")
        let tile = element("room.card.Fan", in: app)
        reveal(tile, in: app)
        XCTAssertEqual(tile.value as? String, "Unavailable")
        XCTAssertFalse(app.switches["room.fan.switch.guest_bathroom_fan_switch_top.power"].exists)
        XCTAssertFalse(app.switches["room.fan.switch.guest_bathroom_fan_switch_top.lock"].exists)
        keepScreenshot(app, "fan-tile-unavailable-\(FentonHomeApp.family)")
    }

    /// Regular width puts the fan in the two-column grid next to the vent; a phone keeps the full-width lead row.
    func testFanTileJoinsTheTwoColumnGridOnIPad() {
        let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]
        for orientation in orientations {
            if orientation != .unknown { XCUIDevice.shared.orientation = orientation }
            let app = launch(room: "guest-bathroom", clean: true)
            let fan = element("room.card.Fan", in: app)
            let vent = element("room.card.Vent", in: app)
            reveal(fan, in: app)
            let window = app.windows.firstMatch.frame
            if FentonHomeApp.family == .iPad {
                XCTAssertLessThan(fan.frame.width, window.width * 0.6, "Not a full-width lead row on iPad (\(orientation.rawValue))")
                XCTAssertEqual(fan.frame.minY, vent.frame.minY, accuracy: 2, "The vent shares the fan's row")
                XCTAssertLessThan(fan.frame.maxX, vent.frame.minX)
                XCTAssertEqual(fan.frame.height, vent.frame.height, accuracy: 1, "Equal heights in the grid")
                keepScreenshot(app, "fan-tile-grid-ipad-\(orientation == .landscapeLeft ? "landscape" : "portrait")")
            } else if FentonHomeApp.family == .iPhone {
                XCTAssertGreaterThan(fan.frame.width, window.width * 0.85, "A phone keeps the full-width lead row")
            }
        }
    }

    /// At the largest text the buttons drop below the status, stay circles no larger than 66 pt, and stay in the tile.
    func testFanRailMovesBelowTheTextAtAX5() {
        let app = launch(room: "master-bathroom", arguments: FentonHomeApp.ax5)
        let (tile, lock, power) = fanButtons("switch.master_bathroom_fan_switch_top", in: app)
        reveal(power, in: app)
        for button in [lock, power] {
            XCTAssertGreaterThanOrEqual(button.frame.width, 43)
            XCTAssertLessThanOrEqual(button.frame.width, 67, "The circle is capped, so the glyph cannot outgrow it")
            XCTAssertEqual(button.frame.width, button.frame.height, accuracy: 1)
            XCTAssertTrue(tile.frame.insetBy(dx: -1, dy: -1).contains(button.frame), "Inside the tile")
        }
        XCTAssertGreaterThan(power.frame.minY, tile.frame.midY, "Below the status text, not wrapped beside it")
        XCTAssertLessThan(lock.frame.minX, tile.frame.midX, "Leading, under the text")
        XCTAssertLessThan(lock.frame.maxX, power.frame.minX)
        keepScreenshot(app, "fan-tile-ax5-\(FentonHomeApp.family)")
    }

    /// Opened from its room tile (the real route), the fan sheet is as tall as its content: no band of empty ground under
    /// the last control. Idle (Guest) and timed (Master).
    func testFanSheetHeightFitsItsContentFromTheTile() {
        for (room, last) in [("guest-bathroom", "fan.setTimer"), ("master-bathroom", "fan.clearTimer")] {
            let app = launch(room: room, clean: true)
            let tile = element("room.card.Fan", in: app)
            reveal(tile, in: app)
            tile.tap()
            let control = element(last, in: app)
            XCTAssertTrue(control.waitForExistence(timeout: 10), "\(room): the fan sheet opened")
            sleep(2) // The detent settles after the first measurement.
            keepScreenshot(app, "fan-sheet-from-tile-\(room)-\(FentonHomeApp.family)")
            XCTAssertTrue(control.isHittable, "\(room): the last control is on screen without scrolling")
            let window = app.windows.firstMatch.frame
            // The footnote (idle) sits a little below the button; the button is last while timed.
            let bottom = room == "guest-bathroom" ? control.frame.maxY + 60 : control.frame.maxY
            XCTAssertLessThanOrEqual(window.maxY - bottom, 100, "\(room): empty ground under the last control")
        }
    }

    /// Master Bedroom: the wake light and each bed open the Bedroom lane's sheets (fixture state, gallery caller).
    func testMasterBedroomOpensWakeLightAndBedSheets() {
        let app = launch(room: "master-bedroom")
        let wake = element("room.card.Wake-Light Alarms", in: app)
        reveal(wake, in: app)
        wake.tap()
        XCTAssertTrue(element("wake.subtitle", in: app).waitForExistence(timeout: 10), "The wake light opens its sheet")
        app.buttons["Close"].firstMatch.tap()

        let bed = element("room.card.Stephen's Bed", in: app)
        reveal(bed, in: app)
        bed.tap()
        XCTAssertTrue(element("bed.dial", in: app).waitForExistence(timeout: 10), "The bed opens its sheet")
        XCTAssertTrue(element("bed.power", in: app).exists)
    }

    /// The Master Bedroom's beds: one heating (filled), one idle in heat mode (the off face keeps the Heating glyph).
    /// The glyph colours are unit-tested (`ThermostatTileFace`); this keeps the page for review.
    func testIdleBedKeepsItsFamilyGlyph() {
        let app = launch(room: "master-bedroom", clean: true)
        let idle = element("room.card.Steph's Bed", in: app)
        reveal(idle, in: app)
        assertTarget(idle)
        reveal(element("room.card.Stephen's Bed", in: app), in: app)
        keepScreenshot(app, "master-bedroom-beds-\(FentonHomeApp.family)")
    }

    /// Rooms without sections say so.
    func testEmptyRoom() {
        let app = launch(room: "hallway")
        XCTAssertTrue(element("room.empty", in: app).exists)
        XCTAssertTrue(app.staticTexts["Nothing Here Yet!"].exists)
    }

    /// The Kitchen's Groceries section pushes the grocery list and Food pages.
    func testKitchenGroceries() {
        let app = launch(room: "kitchen")
        let list = element("room.groceries.list", in: app)
        reveal(list, in: app)
        XCTAssertTrue(app.staticTexts["5 items"].exists)
        list.tap()
        XCTAssertTrue(app.navigationBars["Grocery List"].waitForExistence(timeout: 5))
    }

    // MARK: - Quick Links and room grid

    /// Quick Links shows its tiles, Rooms pushes the ranked grid, and a room opens with its visit counted.
    func testQuickLinksOpenARoom() {
        let app = launch(quickLinks: true)
        for id in ["rooms", "security-system", "food", "vacuums", "media", "custom-lights", "sprinklers"] {
            XCTAssertTrue(element("quickLinks.\(id)", in: app).exists, id)
        }
        XCTAssertTrue(app.staticTexts["42 Items • 3 Expiring Soon"].exists || element("quickLinks.food", in: app).value as? String == "42 Items • 3 Expiring Soon")
        element("quickLinks.rooms", in: app).tap()
        let kitchen = element("rooms.kitchen", in: app)
        XCTAssertTrue(kitchen.waitForExistence(timeout: 5))
        assertTarget(kitchen)
        kitchen.tap()
        XCTAssertTrue(app.navigationBars["Kitchen"].waitForExistence(timeout: 10), "Room pushes after the sheet closes")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "script.increment_room_access")).firstMatch.exists
            || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "script.turn_on")).firstMatch.exists)
    }

    /// The Rooms grid draws each room in its own colour with a filled white glyph and a vertically centred chevron
    /// (owner, 2026-10-16: "room tiles don't have nice colours, and icons should be filled/white").
    func testRoomsGridTilesAreColouredWithCentredChevrons() throws {
        let app = launch(quickLinks: true, clean: true)
        element("quickLinks.rooms", in: app).tap()
        XCTAssertTrue(element("rooms.kitchen", in: app).waitForExistence(timeout: 5))
        sleep(1)
        keepScreenshot(app, "rooms-grid-\(FentonHomeApp.family)")
        let capture = try XCTUnwrap(RenderedContrast.Capture.screen())
        let expected: [String: UInt32] = ["kitchen": 0x547F12, "gym": 0xAF5F00, "garage": 0xA6222C, "living-room": 0x8A6F44]
        for (room, fill) in expected {
            let tile = element("rooms.\(room)", in: app)
            // Below the fold on a short window: a tile can be hittable while its bottom edge is off the screen.
            guard tile.exists, tile.isHittable, tile.frame.maxY < app.windows.firstMatch.frame.maxY - 20 else { continue }
            assertTarget(tile)
            let frame = tile.frame
            let sample = try XCTUnwrap(TileGeometry.rgb(at: CGPoint(x: frame.minX + 10, y: frame.maxY - 10), in: capture))
            XCTAssertTrue(TileGeometry.matchesGlass(sample, fill, heightFraction: 1 - 10 / frame.height),
                          "\(room) is \(sample), expected \(String(fill, radix: 16)) under tinted glass")
            let chevron = try XCTUnwrap(TileGeometry.chevron(in: frame, capture: capture), "\(room): no chevron")
            XCTAssertEqual(chevron.midY, frame.midY, accuracy: 3, "\(room) chevron is vertically centred")
            // A filled white glyph: white ink in the leading 44 pt column, and nothing else but the title beside it.
            let glyphColumn = CGRect(x: frame.minX + 8, y: frame.minY + 6, width: 36, height: frame.height - 12)
            // Only near-white differs from every room fill by this much, so a family-coloured glyph would not register.
            let glyph = try XCTUnwrap(TileGeometry.inkBounds(in: glyphColumn, background: sample, threshold: 400, capture: capture),
                                      "\(room): no white glyph")
            XCTAssertGreaterThan(glyph.height, 14, "\(room) glyph is drawn")
        }
    }

    /// Page links close Quick Links and push their page.
    func testQuickLinksPushAPage() {
        let app = launch(quickLinks: true)
        element("quickLinks.media", in: app).tap()
        XCTAssertTrue(app.navigationBars["Media"].waitForExistence(timeout: 10))
    }

    // MARK: - Accessibility audits

    private func audit(room: String? = nil, quickLinks: Bool = false) throws {
        let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]
        for orientation in orientations {
            if orientation != .unknown { XCUIDevice.shared.orientation = orientation }
            let app = launch(room: room, quickLinks: quickLinks, clean: true)
            try FentonHomeApp.audit(app) { self.launch(room: room, quickLinks: quickLinks, clean: true, arguments: FentonHomeApp.ax5) }
        }
    }

    func testLivingRoomPassesAudit() throws { try audit(room: "living-room") }
    func testGuestBathroomPassesAudit() throws { try audit(room: "guest-bathroom") }
    /// The fan on, locked and timed, with its countdown and lit buttons.
    func testMasterBathroomPassesAudit() throws { try audit(room: "master-bathroom") }
    func testMasterBedroomPassesAudit() throws { try audit(room: "master-bedroom") }
    func testMusicRoomPassesAudit() throws { try audit(room: "music-room") }
    func testKitchenPassesAudit() throws { try audit(room: "kitchen") }
    func testQuickLinksPassesAudit() throws { try audit(quickLinks: true) }

    // MARK: - Screenshots

    /// Every room, Quick Links, the room grid and one sheet of each kind in the current pose (iPad: both
    /// orientations), named `room-<id>-<orientation>`. `FENTON_CAPTURE_SET` = `rooms-a`, `rooms-b` or `extras`
    /// captures one part, so each run fits a shared simulator slot on a loaded host; `FENTON_CAPTURE_ROOMS` (comma
    /// separated room ids) recaptures just those rooms.
    func testCaptureRoomScreens() {
        let environment = ProcessInfo.processInfo.environment
        let only = environment["FENTON_CAPTURE_ROOMS"].map { $0.split(separator: ",").map(String.init) }
        let set = only == nil ? environment["FENTON_CAPTURE_SET"] ?? "" : "rooms-only"
        let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]
        let rooms = ["living-room", "guest-room", "master-bedroom", "gym", "hallway", "office", "kitchen", "dining-room",
                     "back-deck", "music-room", "theater-room", "downstairs-hallway", "garage", "guest-bathroom",
                     "master-bathroom", "entryway"]
        for orientation in orientations {
            if orientation != .unknown { XCUIDevice.shared.orientation = orientation }
            let suffix = orientation == .landscapeLeft ? "landscape" : orientation == .portrait ? "portrait" : "current"
            let roomPart = only ?? (set == "rooms-a" ? Array(rooms.prefix(8)) : set == "rooms-b" ? Array(rooms.dropFirst(8)) : set == "extras" ? [] : rooms)
            for room in roomPart {
                let app = launch(room: room, clean: true)
                keepScreenshot(app, "room-\(room)-\(suffix)")
            }
            guard set.isEmpty || set == "extras" else { continue }
            var app = launch(quickLinks: true, clean: true)
            keepScreenshot(app, "quick-links-\(suffix)")
            element("quickLinks.rooms", in: app).tap()
            XCTAssertTrue(element("rooms.kitchen", in: app).waitForExistence(timeout: 5))
            sleep(1)
            keepScreenshot(app, "room-grid-\(suffix)")

            for (room, card, name) in [("living-room", "room.chip.Lights", "lights"), ("living-room", "room.card.Vents", "vents"),
                                       ("living-room", "room.card.Main Floor", "device-fallback"),
                                       ("master-bedroom", "room.chip.Occupancy", "occupancy"),
                                       ("garage", "room.chip.Doors", "contacts")] {
                app = launch(room: room, clean: true)
                let target = element(card, in: app)
                reveal(target, in: app)
                target.tap()
                sleep(1)
                keepScreenshot(app, "room-sheet-\(name)-\(suffix)")
            }
        }
    }
}
