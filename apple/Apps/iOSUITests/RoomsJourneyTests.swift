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

    private func launch(room: String? = nil, quickLinks: Bool = false, clean: Bool = false, arguments: [String] = []) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "rooms"
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
        app.buttons["Done"].tap()

        let vents = element("room.card.Vents", in: app)
        reveal(vents, in: app)
        vents.tap()
        XCTAssertTrue(element("room.entity.cover.living_room_vent_1_vent", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["room.entity.cover.living_room_vent_1_vent"].exists, "Read-only tiles are not buttons")
        app.buttons["Done"].tap()

        let remote = element("room.card.Living Room Remote", in: app)
        reveal(remote, in: app)
        remote.tap()
        XCTAssertTrue(element("remote.power", in: app).waitForExistence(timeout: 5), "Remote opens the media remote sheet")
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
