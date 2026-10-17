import XCTest

/// The Climate page (`.agents/pages/climate/ios.md`): page sections, the Thermostat Hub picker, the
/// advanced-controls sheet tabs and detail pages, accessibility audits and screenshots on iPhone, iPhone Duo
/// and iPad. Every journey that taps a control runs on the gallery's fixtures (`FENTON_GALLERY=climate`), so no
/// test changes the house; the signed-in journey only reads.
@MainActor
final class ClimateJourneyTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    // Only the iPad journeys rotate; leave a Duo pose set in Device Hub alone.
    override func tearDown() { MainActor.assumeIsolated { if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait } } }

    // MARK: - Helpers

    /// Launches the Climate gallery, optionally on the away fixture or with the sheet open on `open`.
    private func launch(open: String? = nil, scenario: String? = nil, clean: Bool = false, arguments: [String] = []) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "climate"
        if let open { app.launchEnvironment["FENTON_GALLERY_CLIMATE_OPEN"] = open }
        if let scenario { app.launchEnvironment["FENTON_GALLERY_CLIMATE_SCENARIO"] = scenario }
        if clean { app.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1" }
        app.launchArguments += arguments
        app.launch()
        let ready = open == nil ? element("climate.wholeHome", in: app) : app.buttons["Close"]
        XCTAssertTrue(ready.waitForExistence(timeout: 15), "Climate did not appear")
        return app
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Scrolls the frontmost scroll view until `element` is fully on screen.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let window = app.windows.firstMatch
        for attempt in 0..<30 {
            // Scroll inside the sheet when one is up: an iPad sheet doesn't cover the window, and a drag on the
            // dimmed area outside it scrolls nothing.
            // Sheet pages are forms (collection views); the page is a scroll view.
            let named = NSPredicate(format: "identifier BEGINSWITH 'climate.sheet.' OR identifier == 'climate.detail'")
            let sheets = app.descendants(matching: .any).matching(NSPredicate(format: "elementType IN %@",
                [XCUIElement.ElementType.scrollView, .collectionView, .table].map(\.rawValue))).matching(named)
            // The one holding the element: after Back the popped detail's scroll view can linger in the tree.
            let holder = element.exists
                ? sheets.allElementsBoundByIndex.first { $0.descendants(matching: .any)[element.identifier].exists }
                : nil
            let area = holder ?? sheets.allElementsBoundByIndex.last { $0.exists && $0.isHittable } ?? window
            let frame = area.frame
            // Clear of the bars: navigation bar and the gallery's last-call line at the top, home indicator below.
            let top = frame.minY + Swift.min(frame.height * 0.18, 160)
            let bottom = frame.maxY - frame.height * 0.08
            if element.exists, element.isHittable, element.frame.maxY <= bottom, element.frame.minY >= top { break }
            // A row that is not in the tree yet is searched for downwards first, then upwards: a lazy Form drops the rows
            // that scrolled away, so on the folded Duo's short screen the row can be above the end the page was left at
            // (Predictive Comfort While Away, above the reasons; 2026-10-17).
            let above = element.exists ? element.frame.minY < top : attempt >= 8
            let start = area.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: above ? 0.35 : 0.7))
            // Slow drag with a hold so the scroll doesn't coast: a tap during momentum only stops the scroll.
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: (above ? 1 : -1) * frame.height * 0.2)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(element.isHittable, "\(element) never came into view", file: file, line: line)
        return element
    }

    private func lastCall(_ app: XCUIApplication) -> String { app.staticTexts["gallery.lastCall"].firstMatch.label }

    private func waitForCall(_ prefix: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let label = app.staticTexts["gallery.lastCall"].firstMatch
        let matches = NSPredicate(format: "label BEGINSWITH %@", "Last call: \(prefix)")
        let found = XCTNSPredicateExpectation(predicate: matches, object: label)
        XCTAssertEqual(XCTWaiter().wait(for: [found], timeout: 4), .completed, "Last call was '\(label.label)'", file: file, line: line)
    }

    /// The sheet page's navigation bar titled `title`.
    private func heading(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.navigationBars[title]
    }

    /// The Thermostat Hub row's text: "Thermostat Hub, <state>" (its mode menu is a separate element).
    private func hubRow(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Thermostat Hub, '")).firstMatch
    }

    /// Flips a system switch in a form row: XCUITest's tap on the row's centre misses the switch.
    private func flip(_ toggle: XCUIElement) {
        let inner = toggle.switches.firstMatch
        if inner.exists, inner.isHittable { inner.tap() } else { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
    }

    /// A section header (grouped forms may draw it in capitals).
    private func header(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", title)).firstMatch
    }

    private func value(_ element: XCUIElement) -> String { element.value as? String ?? "" }

    /// Waits up to 3 s for `element`'s accessibility value to become `expected`.
    private func hasValue(_ element: XCUIElement, _ expected: String) -> Bool {
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: element)
        return XCTWaiter().wait(for: [match], timeout: 3) == .completed
    }

    /// Back to the parent page, confirmed by its heading (`parent`, default the sheet's root title). Tries the
    /// `BackButton` (folded Duo rail, iPad), then the bar button that isn't Close.
    private func back(_ app: XCUIApplication, to parent: String = "Advanced Controls",
                      file: StaticString = #filePath, line: UInt = #line) {
        var candidates: [XCUIElement] = [app.buttons["BackButton"]]
        candidates += app.navigationBars.buttons.allElementsBoundByIndex.filter { $0.label != "Close" }
        for button in candidates where button.exists && button.isHittable {
            button.tap()
            // Hittable, not just present: the root page stays in the tree under a pushed detail.
            let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: heading(parent, in: app))
            if XCTWaiter().wait(for: [shown], timeout: 4) == .completed { return }
        }
        XCTFail("Back did not return to \(parent)", file: file, line: line)
    }

    // MARK: - Page

    /// Whole Home dial, hub row and pop-up menus, open contacts and the three entries, with names and roles.
    func testPageSectionsAndSemantics() {
        let app = launch()
        XCTAssertTrue(element("thermostatDial.readout", in: app).label.hasPrefix("Whole Home thermostat, Heating"))
        XCTAssertEqual(hubRow(in: app).label, "Thermostat Hub, Heat")
        let mode = element("climate.hub.mode", in: app)
        XCTAssertEqual(mode.label, "Thermostat Hub Mode")
        XCTAssertEqual(value(mode), "Heat")
        XCTAssertGreaterThanOrEqual(mode.frame.height, 43)
        XCTAssertEqual(value(element("climate.hub.fan", in: app)), "Auto")
        XCTAssertFalse(element("climate.awayNotice", in: app).exists, "Home shows no away notice")
        XCTAssertFalse(element("climate.integrationWarning", in: app).exists)
        let window = element("climate.contact.binary_sensor.office_window_contact_sensor_contact", in: app)
        XCTAssertTrue(window.exists)
        XCTAssertEqual(window.label, "Office Window")
        XCTAssertEqual(value(window), "Open")
        XCTAssertNotEqual(window.elementType, .button, "Contact cards are not buttons")
        for (tab, title) in [("rooms", "Room Thermostats"), ("automation", "Advanced Configuration"), ("tracking", "Room Tracking")] {
            let entry = reveal(element("climate.entry.\(tab)", in: app), in: app)
            XCTAssertEqual(entry.label, title)
            XCTAssertGreaterThanOrEqual(entry.frame.height, 43)
        }
    }

    /// Whole Home is compact (owner, 2026-10-16: "takes up too much space now and I don't want the card background"):
    /// the dial sits straight on the wallpaper with no card around it, and the hub is one short pill under it.
    func testWholeHomeIsCompactWithNoCard() throws {
        let app = launch(clean: true)
        let home = element("climate.wholeHome", in: app)
        let hub = element("climate.hub", in: app)
        XCTAssertTrue(hub.waitForExistence(timeout: 5))
        XCTAssertLessThan(hub.frame.height, 90, "The hub is one compact row, not two list rows")
        XCTAssertLessThanOrEqual(hub.frame.minY - home.frame.maxY, 20, "The hub sits right under the dial")
        keepScreenshot(app, "climate-whole-home-\(FentonHomeApp.family)")
        // No card: the dial container's corner is the wallpaper, the same as the page margin beside it.
        let capture = try XCTUnwrap(RenderedContrast.Capture.screen())
        let inside = try XCTUnwrap(TileGeometry.rgb(at: CGPoint(x: home.frame.minX + 6, y: home.frame.minY + 6), in: capture))
        let beside = try XCTUnwrap(TileGeometry.rgb(at: CGPoint(x: max(2, home.frame.minX - 6), y: home.frame.minY + 6), in: capture))
        XCTAssertLessThan(abs(inside.r - beside.r) + abs(inside.g - beside.g) + abs(inside.b - beside.b), 30,
                          "The dial has no card background: \(inside) vs \(beside)")
    }

    /// Away on vacation: the notice reads Vacation Mode, Automatic Thermostat's warning shows, nothing is open.
    func testAwayScenarioShowsTheNoticeAndWarning() {
        let app = launch(scenario: "away")
        let notice = element("climate.awayNotice", in: app)
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertTrue(notice.label.hasPrefix("Vacation Mode Active. The room may be cooler or warmer"), notice.label)
        XCTAssertTrue(reveal(element("climate.integrationWarning", in: app), in: app).label.hasPrefix("Automatic Thermostat is off."))
        XCTAssertFalse(app.staticTexts["Open Contact Sensors"].exists)
        // The dial shows the eco-away thermostat's wider range.
        XCTAssertEqual(element("thermostatDial.handle.low", in: app).value as? String, "62 degrees")
    }

    /// A choice in the hub's dropdown menu (the system menu's item button).
    private func menuItem(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.collectionViews.buttons[title].exists ? app.collectionViews.buttons[title] : app.buttons[title].firstMatch
    }

    /// The hub's mode and fan dropdowns are native menus with the current choice checked; a choice closes the menu
    /// and sends `climate.set_hvac_mode` / `climate.set_fan_mode`.
    func testHubDropdownsSendModeAndFan() {
        let app = launch()
        element("climate.hub.mode", in: app).tap()
        let cool = menuItem("Cool", in: app)
        XCTAssertTrue(cool.waitForExistence(timeout: 5), "Mode menu did not open")
        XCTAssertTrue(menuItem("Heat", in: app).isSelected, "The current mode is checked")
        cool.tap()
        waitForCall("climate.set_hvac_mode entity_id=climate.thermostat_hub_w200 hvac_mode=cool", in: app)
        XCTAssertTrue(hasValue(element("climate.hub.mode", in: app), "Cool"))

        element("climate.hub.fan", in: app).tap()
        let on = menuItem("On", in: app)
        XCTAssertTrue(on.waitForExistence(timeout: 5), "Fan menu did not open")
        on.tap()
        XCTAssertTrue(element("climate.hub.fan", in: app).waitForExistence(timeout: 5), "Fan menu closes after a choice")
        waitForCall("climate.set_fan_mode entity_id=climate.thermostat_hub_w200 fan_mode=on", in: app)
    }

    // MARK: - Sheet

    /// An entry opens the sheet on its tab; the tab control switches tabs; Close closes it.
    func testEntriesOpenTheSheetOnTheirTab() {
        let app = launch()
        reveal(element("climate.entry.tracking", in: app), in: app).tap()
        XCTAssertTrue(element("climate.sheet.tracking", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(heading("Advanced Controls", in: app).exists)
        let tabs = app.segmentedControls["climate.sheet.tabs"]
        if tabs.exists {
            tabs.buttons["Rooms"].tap()
        } else {
            // A menu at accessibility sizes.
            element("climate.sheet.tabs", in: app).tap()
            app.buttons["Rooms"].tap()
        }
        XCTAssertTrue(element("climate.sheet.rooms", in: app).waitForExistence(timeout: 5))
        // Forms load rows as they scroll: the first and the last room.
        XCTAssertTrue(element("climate.room.living_room", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(reveal(element("climate.room.theater_room", in: app), in: app).exists)
        app.buttons["Close"].tap()
        XCTAssertTrue(element("climate.wholeHome", in: app).waitForExistence(timeout: 5))
    }

    /// The Rooms tab is a grid of the same colour room tiles as the Rooms grid: a button each, a solid fill, a filled white
    /// glyph and a vertically centred chevron (owner, 2026-10-16: "standardise on room tiles across the app").
    func testRoomsTabShowsColourRoomTiles() throws {
        let app = launch(open: "rooms")
        sleep(1)
        keepScreenshot(app, "climate-rooms-tab-\(FentonHomeApp.family)")
        let capture = try XCTUnwrap(RenderedContrast.Capture.screen())
        let expected: [String: UInt32] = ["living_room": 0x8A6F44, "office": 0x007E94, "master_bedroom": 0x3E3EB7]
        for (key, fill) in expected {
            let tile = element("climate.room.\(key)", in: app)
            XCTAssertTrue(tile.waitForExistence(timeout: 5), key)
            XCTAssertEqual(tile.elementType, .button, "A room tile opens its room")
            XCTAssertGreaterThanOrEqual(tile.frame.height, 43)
            guard tile.isHittable else { continue }
            let frame = tile.frame
            let sample = try XCTUnwrap(TileGeometry.rgb(at: CGPoint(x: frame.minX + 10, y: frame.maxY - 10), in: capture))
            XCTAssertTrue(TileGeometry.matchesGlass(sample, fill, heightFraction: 1 - 10 / frame.height),
                          "\(key) is \(sample), expected \(String(fill, radix: 16)) under tinted glass")
            let chevron = try XCTUnwrap(TileGeometry.chevron(in: frame, capture: capture), "\(key): no chevron")
            XCTAssertEqual(chevron.midY, frame.midY, accuracy: 3, "\(key) chevron is vertically centred")
        }
    }

    /// A room shows its subtitle, opens its dial, vents and Back returns to Rooms.
    func testRoomDetailShowsDialAndVents() {
        let app = launch(open: "rooms")
        let living = element("climate.room.living_room", in: app)
        XCTAssertTrue(living.waitForExistence(timeout: 5))
        XCTAssertEqual(living.label, "Living Room")
        XCTAssertEqual(value(living), "70.9°F\nOccupied")
        living.tap()
        XCTAssertTrue(heading("Living Room", in: app).waitForExistence(timeout: 5))
        let dial = element("climate.roomDial", in: app)
        XCTAssertTrue(dial.waitForExistence(timeout: 5))
        XCTAssertEqual(dial.descendants(matching: .any)["thermostatDial.handle.low"].firstMatch.label, "Living Room heat to")
        let vent = reveal(element("climate.vent.cover.living_room_vent_2_vent", in: app), in: app)
        XCTAssertNotEqual(vent.elementType, .button, "Vents are read-only")
        XCTAssertEqual(vent.label, "Vent 2")
        XCTAssertEqual(value(vent), "Open · 50%", "A vent tile shows how far it is open")
        XCTAssertEqual(value(element("climate.vent.cover.living_room_vent_1_vent", in: app)), "Open · 100%")
        XCTAssertTrue(header("Living Room Vents", in: app).exists)
        back(app)
        XCTAssertTrue(element("climate.sheet.rooms", in: app).waitForExistence(timeout: 5))
    }

    /// Automation: toggles are system switches that send `homeassistant.toggle`; an Eco option page selects with
    /// `select.select_option` and its row shows the new value.
    func testAutomationTogglesAndEcoOptionPage() {
        let app = launch(open: "automation")
        let eco = reveal(element("climate.toggle.switch.thermostat_contact_sensors_eco_mode", in: app), in: app)
        XCTAssertEqual(eco.label, "Eco Mode")
        XCTAssertEqual(value(eco), "1")
        flip(eco)
        XCTAssertTrue(hasValue(eco, "0"))
        waitForCall("homeassistant.toggle entity_id=switch.thermostat_contact_sensors_eco_mode", in: app)

        let opener = reveal(element("climate.eco.eco-away", in: app), in: app)
        XCTAssertEqual(opener.label, "Eco Behavior When Away")
        XCTAssertEqual(value(opener), "Keep Eco Active")
        opener.tap()
        XCTAssertTrue(heading("Eco Behavior When Away", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("climate.option.Keep Eco Active", in: app).isSelected)
        let targets = reveal(element("climate.option.Use Eco Away Targets", in: app), in: app)
        XCTAssertTrue(targets.label.hasSuffix("Use the wider away temperature range while everyone is away."), targets.label)
        targets.tap()
        XCTAssertTrue(targets.wait(for: \.isSelected, toEqual: true, timeout: 3))
        waitForCall("select.select_option entity_id=select.thermostat_contact_sensors_eco_behavior_when_away option=Use Eco Away Targets", in: app)
        back(app)
        XCTAssertTrue(hasValue(reveal(element("climate.eco.eco-away", in: app), in: app), "Use Eco Away Targets"))
    }

    /// Predictive Comfort is a switch (`switch.turn_on` / `turn_off`); while on, Current Prediction opens the detail.
    func testPredictiveComfortSwitchAndDetail() {
        let app = launch(open: "automation")
        let predictive = reveal(element("climate.predictive", in: app), in: app)
        XCTAssertEqual(predictive.label, "Predictive Comfort, On · Pre-Cool")
        XCTAssertEqual(value(predictive), "1")
        reveal(element("climate.predictive.open", in: app), in: app).tap()
        XCTAssertTrue(heading("Predictive Comfort", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(element("climate.predictive.recommendation", in: app).label, "Recommendation: Pre-Cool")
        XCTAssertEqual(element("climate.metric.Comfort Band", in: app).label, "Comfort Band, 71.0°F - 74.0°F")
        reveal(element("climate.predictive.reasons", in: app), in: app)
        XCTAssertTrue(header("Why This Prediction", in: app).exists)
        XCTAssertTrue(app.staticTexts["Predicted indoor temperature is 75.1°F, above your 71.0°F - 74.0°F comfort band."].exists)
        let allowAway = reveal(element("climate.toggle.switch.thermostat_contact_sensors_predictive_allow_away", in: app), in: app)
        XCTAssertEqual(allowAway.label, "Predictive Comfort While Away")
        XCTAssertEqual(value(allowAway), "0")
        back(app)

        let power = reveal(element("climate.predictive", in: app), in: app)
        flip(power)
        waitForCall("switch.turn_off entity_id=switch.thermostat_contact_sensors_predictive_comfort_mode", in: app)
        XCTAssertTrue(hasValue(power, "0"))
        XCTAssertFalse(element("climate.predictive.open", in: app).exists, "Current Prediction hides while off")
        flip(power)
        waitForCall("switch.turn_on entity_id=switch.thermostat_contact_sensors_predictive_comfort_mode", in: app)
    }

    /// Tracking: counts in the openers follow the room switches; turning off Track Selected Rooms disables the
    /// Selected Rooms and Critical Protection openers.
    func testTrackingCountsAndRoomPages() {
        let app = launch(open: "tracking")
        let selected = reveal(element("climate.tracking.selected-rooms", in: app), in: app)
        XCTAssertEqual(value(selected), "3 of 11 selected")
        XCTAssertEqual(value(element("climate.tracking.critical-protection", in: app)), "1 rooms forced")
        XCTAssertEqual(value(element("climate.tracking.occupied-only", in: app)), "2 of 11 occupied only")
        selected.tap()
        XCTAssertTrue(heading("Selected Rooms", in: app).waitForExistence(timeout: 5))
        let kitchen = reveal(element("climate.track.selected-rooms.kitchen", in: app), in: app)
        XCTAssertEqual(kitchen.label, "Kitchen")
        XCTAssertEqual(value(kitchen), "Off")
        kitchen.tap()
        XCTAssertTrue(hasValue(kitchen, "On"))
        waitForCall("homeassistant.toggle entity_id=switch.thermostat_contact_sensors_track_kitchen", in: app)
        back(app)
        XCTAssertTrue(hasValue(reveal(element("climate.tracking.selected-rooms", in: app), in: app), "4 of 11 selected"))

        reveal(element("climate.tracking.critical-protection", in: app), in: app).tap()
        XCTAssertTrue(heading("Critical Protection", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("climate.track.critical-protection.office", in: app).exists, "Tracked rooms are not listed")
        XCTAssertTrue(hasValue(reveal(element("climate.track.critical-protection.guest_room", in: app), in: app), "On"))
        back(app)

        let track = reveal(element("climate.toggle.switch.thermostat_contact_sensors_only_track_selected_rooms", in: app), in: app)
        flip(track)
        XCTAssertTrue(hasValue(track, "0"))
        let disabled = reveal(element("climate.tracking.selected-rooms", in: app), in: app)
        XCTAssertFalse(disabled.isEnabled)
        XCTAssertEqual(value(disabled), "Enable Track Selected Rooms first")
        XCTAssertFalse(element("climate.tracking.critical-protection", in: app).isEnabled)
    }

    // MARK: - Live server (read-only)

    /// Signed in against the house: the Climate tab shows the Whole Home dial and a room's reading; audits the
    /// live page. Nothing is tapped that changes a setting.
    func testLiveClimatePageReadsTheHouse() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openClimateTab(app)
        XCTAssertTrue(element("thermostatDial.readout", in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(element("thermostatDial.readout", in: app).label.hasPrefix("Whole Home thermostat"))
        XCTAssertTrue(hubRow(in: app).exists)
        // The AX5 relaunch confirms iPad's "partially unsupported" Dynamic Type report (a known false positive).
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            self.openClimateTab(large)
            sleep(1)
            return large
        }
        reveal(element("climate.entry.rooms", in: app), in: app).tap()
        XCTAssertTrue(element("climate.sheet.rooms", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(value(reveal(element("climate.room.office", in: app), in: app)).contains("°F\n"))
    }

    private func openClimateTab(_ app: XCUIApplication) {
        // Regular width (iPad, unfolded Duo) navigates through the flyout; compact width through the tab bar.
        if app.buttons["nav.open"].waitForExistence(timeout: 3) {
            app.buttons["nav.open"].tap()
            XCTAssertTrue(app.buttons["nav.climate"].waitForExistence(timeout: 3), "Flyout did not open")
            app.buttons["nav.climate"].tap()
        } else {
            let tab = app.tabBars.buttons["Climate"]
            if tab.waitForExistence(timeout: 5) { tab.tap() } else { app.buttons["Climate"].firstMatch.tap() }
        }
        XCTAssertTrue(element("climate.wholeHome", in: app).waitForExistence(timeout: 15), "Climate tab did not open")
    }

    // MARK: - Audits

    private func audit(open: String? = nil, scenario: String? = nil, prepare: ((XCUIApplication) -> Void)? = nil) throws {
        // Clean: the gallery's debug line is not part of the product and covers content under it.
        let app = launch(open: open, scenario: scenario, clean: true)
        prepare?(app)
        try FentonHomeApp.audit(app) {
            let large = self.launch(open: open, scenario: scenario, clean: true, arguments: FentonHomeApp.ax5)
            prepare?(large)
            sleep(1)
            return large
        }
    }

    func testPagePassesAudit() throws {
        try audit()
        guard FentonHomeApp.family == .iPad else { return }
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        try audit()
    }

    func testAwayPagePassesAudit() throws { try audit(scenario: "away") }
    func testRoomsTabPassesAudit() throws { try audit(open: "rooms") }
    func testAutomationTabPassesAudit() throws { try audit(open: "automation") }
    func testTrackingTabPassesAudit() throws { try audit(open: "tracking") }
    func testRoomDetailPassesAudit() throws { try audit(open: "room:master_bedroom") }
    func testPredictiveDetailPassesAudit() throws { try audit(open: "predictive") }
    func testEcoOptionPagePassesAudit() throws { try audit(open: "eco-critical") }
    func testTrackingDetailPassesAudit() throws { try audit(open: "selected-rooms") }

    func testHubPickerPassesAudit() throws {
        try audit { app in
            self.element("climate.hub.mode", in: app).tap()
            XCTAssertTrue(self.menuItem("Cool", in: app).waitForExistence(timeout: 5))
        }
    }

    /// iPad landscape: the sheet tabs and a detail page audit too.
    func testSheetPassesAuditInIPadLandscape() throws {
        guard FentonHomeApp.family == .iPad else { throw XCTSkip("iPad only") }
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        try audit(open: "automation")
        try audit(open: "room:living_room")
    }

    /// At AX5 every entry and the tab control stay reachable.
    func testLargestTextKeepsEntriesReachable() {
        let app = launch(arguments: FentonHomeApp.ax5)
        for tab in ["rooms", "automation", "tracking"] {
            XCTAssertTrue(reveal(element("climate.entry.\(tab)", in: app), in: app).isHittable)
        }
        element("climate.entry.tracking", in: app).tap()
        XCTAssertTrue(element("climate.sheet.tabs", in: app).waitForExistence(timeout: 5), "The tab control becomes a menu at AX5")
    }

    // MARK: - Screenshots

    /// A host capture named `name` already exists (a rerun after a simulator crash resumes where it stopped).
    private func captured(_ name: String) -> Bool {
        guard let folder = ProcessInfo.processInfo.environment["FENTON_CAPTURE_DIR"], !folder.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png").path)
    }

    /// The page, hub picker, each sheet tab and every detail kind, named `climate-<view>-<orientation>`
    /// (iPad: portrait and landscape).
    func testCaptureClimateScreens() {
        let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]
        let views: [(name: String, open: String?)] = [
            ("page", nil), ("rooms", "rooms"), ("automation", "automation"), ("tracking", "tracking"),
            ("room", "room:living_room"), ("predictive", "predictive"), ("eco-option", "eco-away"), ("tracking-detail", "selected-rooms"),
        ]
        for orientation in orientations {
            if orientation != .unknown { XCUIDevice.shared.orientation = orientation }
            let suffix = orientation == .landscapeLeft ? "landscape" : orientation == .portrait ? "portrait" : "current"
            for view in views where !captured("climate-\(view.name)-\(suffix)")
                || (view.name == "page" && !captured("climate-hub-picker-\(suffix)")) {
                let app = launch(open: view.open, clean: true)
                sleep(1)
                keepScreenshot(app, "climate-\(view.name)-\(suffix)")
                if view.name == "page" {
                    element("climate.hub.mode", in: app).tap()
                    XCTAssertTrue(menuItem("Cool", in: app).waitForExistence(timeout: 5))
                    sleep(1)
                    keepScreenshot(app, "climate-hub-picker-\(suffix)")
                }
            }
            if !captured("climate-page-away-\(suffix)") {
                let away = launch(scenario: "away", clean: true)
                sleep(1)
                keepScreenshot(away, "climate-page-away-\(suffix)")
            }
        }
        if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
    }
}
