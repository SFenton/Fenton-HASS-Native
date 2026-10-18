import XCTest

/// The Home weather card and the Weather sheet (`.agents/pages/home/ios.md`, `.agents/patterns/weather.md`):
/// the card's hours and Today row, a carousel that scrolls without opening the sheet, the sheet's three modes, its
/// loading and error states, and accessibility audits at the default and AX5 text sizes. Every journey runs on the
/// gallery's fixture forecasts (`FENTON_GALLERY=weather`), so nothing needs the live server.
@MainActor
final class WeatherJourneyTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    // MARK: - Helpers

    private func launch(
        open: Bool = false, state: String? = nil, condition: String? = nil, night: Bool = false, arguments: [String] = []
    ) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "weather"
        if open { app.launchEnvironment["FENTON_GALLERY_WEATHER_OPEN"] = "1" }
        if let state { app.launchEnvironment["FENTON_GALLERY_WEATHER_STATE"] = state }
        if let condition { app.launchEnvironment["FENTON_GALLERY_WEATHER_CONDITION"] = condition }
        if night { app.launchEnvironment["FENTON_GALLERY_WEATHER_NIGHT"] = "1" }
        app.launchArguments += arguments
        app.launch()
        return app
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// The accessibility audit, unless `TEST_RUNNER_FENTON_SKIP_AUDIT=1` (screenshot-only passes).
    private func audit(_ app: XCUIApplication, presenter: XCUIElement? = nil, ax5Page: (() throws -> XCUIApplication)? = nil) throws {
        guard ProcessInfo.processInfo.environment["FENTON_SKIP_AUDIT"] != "1" else { return }
        try FentonHomeApp.audit(app, ax5Page: ax5Page, presenter: presenter)
    }

    /// Waits on the state, up to 15 s: a mode switch on the folded Duo under load took longer than the 5 s this allowed
    /// (the label read "Now wind 8 mph gusts 14 mph" a moment after the wait gave up, 2026-10-17).
    private func waitFor(_ element: XCUIElement, _ format: String, _ argument: String, timeout: TimeInterval = 15) -> Bool {
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate(format: format, argument), object: element)
        return XCTWaiter().wait(for: [matches], timeout: timeout) == .completed
    }

    /// Scrolls the sheet, up or down, until `element` is hittable and clear of the bars.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch
        for _ in 0..<60 {
            let top = window.frame.minY + window.frame.height * 0.14
            let bottom = window.frame.maxY - window.frame.height * 0.08
            if element.exists, element.isHittable {
                // A tile taller than the clear band can never fit inside it; on screen is enough.
                let fits = element.frame.minY >= top && element.frame.maxY <= bottom
                if fits || element.frame.height > bottom - top { break }
            }
            // Below or not laid out yet: drag up (scroll down); above: drag down.
            let above = element.exists && element.frame.maxY < top
            // Mid-window: on iPad the sheet is a centered form sheet, so the window's edge is the dimmed page.
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.35 : 0.7))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: (above ? 1 : -1) * window.frame.height * 0.25)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(element.isHittable, "\(element) never came into view", file: file, line: line)
    }

    private func openSheet(_ app: XCUIApplication) {
        app.buttons["home.weather.card"].tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 8), "The Weather sheet did not open")
    }

    // MARK: - Card

    /// The card button is named like the web's, the Today row and every hour speak their values, and the page
    /// indicator reports its page.
    func testCardSemantics() throws {
        let app = launch(condition: "rainy")
        let card = app.buttons["home.weather.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        XCTAssertEqual(card.label, "Open seven-day weather forecast. Rain, 72°F")
        XCTAssertTrue(card.isHittable)
        XCTAssertGreaterThanOrEqual(card.frame.height, 44)

        let today = element("home.weather.today", in: app)
        XCTAssertTrue(today.waitForExistence(timeout: 8))
        XCTAssertTrue(today.label.hasPrefix("Today "), today.label)
        XCTAssertTrue(today.label.contains("H:"), today.label)

        let now = element("home.weather.hour.0", in: app)
        XCTAssertTrue(now.waitForExistence(timeout: 8))
        XCTAssertTrue(now.label.hasPrefix("Now "), now.label)
        XCTAssertTrue(now.label.hasSuffix("°F"), now.label)
        // VoiceOver reads only the page on screen: the hosted row (`PagedRow`) exposes the cells that overlap its viewport, and
        // the next page's after paging (Next on wide layouts, a swipe otherwise).
        XCTAssertFalse(element("home.weather.hour.23", in: app).exists, "Hours on other pages are not accessibility elements")
        let visibleBefore = (0..<24).filter { element("home.weather.hour.\($0)", in: app).exists }
        XCTAssertEqual(visibleBefore, Array(0..<visibleBefore.count), "The first page's hours are consecutive from the first")
        XCTAssertTrue((2..<24).contains(visibleBefore.count), "A page holds a few hours, not all: \(visibleBefore)")
        let next = app.buttons["home.weather.next"]
        if next.exists {
            next.tap()
        } else {
            element("home.weather.carousel", in: app).swipeLeft()
        }
        XCTAssertTrue(waitFor(element("home.weather.pages", in: app), "value BEGINSWITH %@", "Page 2"))
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: now)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "The first page's hours leave the tree after paging")
        XCTAssertTrue(element("home.weather.hour.\(visibleBefore.count)", in: app).waitForExistence(timeout: 5),
                      "The next page's hours are accessibility elements")

        let pages = element("home.weather.pages", in: app)
        XCTAssertTrue(pages.exists)
        XCTAssertTrue((pages.value as? String ?? "").hasPrefix("Page 2 of"), "\(String(describing: pages.value))")
    }

    /// Swiping the hours scrolls them and never opens the sheet; the indicator follows.
    func testCarouselScrollsWithoutOpeningTheSheet() throws {
        let app = launch()
        let carousel = element("home.weather.carousel", in: app)
        XCTAssertTrue(carousel.waitForExistence(timeout: 15))
        XCTAssertTrue(element("home.weather.hour.0", in: app).waitForExistence(timeout: 8))
        let pages = element("home.weather.pages", in: app)
        // A swipe moves one page or more (a fast one under load carried on to page 3), so the journey asks for "off the
        // first page" and then swipes back until the first page shows, instead of assuming exactly one page each way.
        carousel.swipeLeft()
        XCTAssertTrue(waitFor(pages, "NOT (value BEGINSWITH %@)", "Page 1"), "The indicator stayed on \(String(describing: pages.value))")
        XCTAssertFalse(app.buttons["Close"].exists, "Scrolling opened the sheet")
        XCTAssertFalse(element("weather.sheet", in: app).exists)
        for _ in 0..<4 where !waitFor(pages, "value BEGINSWITH %@", "Page 1", timeout: 3) { carousel.swipeRight() }
        XCTAssertTrue(waitFor(pages, "value BEGINSWITH %@", "Page 1"), "The indicator stayed on \(String(describing: pages.value))")
    }

    /// Wide layouts add previous and next buttons; the first page's Previous is disabled.
    func testWideLayoutsShowPreviousAndNext() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["home.weather.card"].waitForExistence(timeout: 15))
        let next = app.buttons["home.weather.next"]
        if FentonHomeApp.family == .iPad {
            XCTAssertTrue(next.waitForExistence(timeout: 8), "iPad should show Next")
            XCTAssertGreaterThanOrEqual(next.frame.width, 43)
            XCTAssertGreaterThanOrEqual(next.frame.height, 43)
            XCTAssertFalse(app.buttons["home.weather.previous"].isEnabled)
            next.tap()
            XCTAssertTrue(waitFor(element("home.weather.pages", in: app), "value BEGINSWITH %@", "Page 2"))
            XCTAssertTrue(app.buttons["home.weather.previous"].isEnabled)
        } else if FentonHomeApp.family == .iPhone {
            XCTAssertFalse(next.exists, "Compact layouts rely on swiping")
        }
    }

    /// Tapping the card, or an hour, opens the sheet.
    func testTappingTheCardOrAnHourOpensTheSheet() throws {
        let app = launch()
        openSheet(app)
        XCTAssertTrue(element("weather.hero.temperature", in: app).exists)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["home.weather.card"].waitForExistence(timeout: 5))
        let hour = element("home.weather.hour.1", in: app)
        XCTAssertTrue(hour.waitForExistence(timeout: 5))
        hour.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 8), "Tapping an hour should open the sheet")
    }

    /// While the service has not answered, the card keeps its height and shows no hours.
    func testLoadingKeepsTheCardsShape() throws {
        let app = launch(state: "loading")
        let card = app.buttons["home.weather.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        XCTAssertFalse(element("home.weather.hour.0", in: app).exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Loading 24-hour weather forecast'")).firstMatch.exists)
        XCTAssertFalse(element("home.weather.today", in: app).exists)
    }

    /// A failing service shows Home Assistant's message in place of the hours.
    func testErrorShowsAMessageInPlaceOfTheHours() throws {
        let app = launch(state: "error")
        let message = element("home.weather.hourlyMessage", in: app)
        XCTAssertTrue(message.waitForExistence(timeout: 15))
        XCTAssertTrue(message.label.contains("Pirate Weather"), message.label)
        XCTAssertTrue(app.buttons["home.weather.card"].isHittable, "The card still opens its sheet")
    }

    // MARK: - Sheet

    /// The sheet shows its sections in reading order, with the web's labels.
    func testSheetSections() throws {
        let app = launch(open: true)
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15))
        XCTAssertTrue(element("weather.hero.temperature", in: app).waitForExistence(timeout: 8))
        XCTAssertEqual(element("weather.hero.temperature", in: app).label, "72°")
        XCTAssertEqual(element("weather.hero.condition", in: app).label, "Rain")
        XCTAssertTrue(element("weather.today.headline", in: app).waitForExistence(timeout: 8), "The Today briefing did not appear")
        XCTAssertTrue(app.staticTexts["Today"].exists)
        XCTAssertTrue(element("weather.hour.0", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(element("weather.hour.0", in: app).label.hasPrefix("Now Rain"), element("weather.hour.0", in: app).label)
        XCTAssertTrue(element("weather.day.0", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(element("weather.day.0", in: app).label.hasPrefix("Today "))
        reveal(element("weather.highlight.aqi", in: app), in: app)
        XCTAssertEqual(element("weather.highlight.aqi", in: app).label, "Outdoor air quality 72, Moderate")
        for kind in ["precipitation", "accumulation", "humidity", "cloud", "feels", "uv", "wind", "visibility", "pressure"] {
            let tile = element("weather.highlight.\(kind)", in: app)
            reveal(tile, in: app)
            XCTAssertFalse(tile.label.isEmpty, kind)
        }
        XCTAssertEqual(element("weather.highlight.pressure", in: app).label, "Pressure 29.92 inHg")
        XCTAssertTrue(element("weather.highlight.wind", in: app).label.hasPrefix("Wind 9 mph; Gusts 14 mph; From "))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["home.weather.card"].waitForExistence(timeout: 5))
    }

    /// The three modes change both the hourly carousel and the seven-day rows, and name their state.
    func testModesSwitchHoursAndDays() throws {
        let app = launch(open: true)
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15))
        let condition = app.buttons["weather.mode.condition"]
        let precipitation = app.buttons["weather.mode.precipitation"]
        let wind = app.buttons["weather.mode.wind"]
        XCTAssertTrue(condition.waitForExistence(timeout: 8))
        for button in [condition, precipitation, wind] {
            XCTAssertGreaterThanOrEqual(button.frame.width, 43)
            XCTAssertGreaterThanOrEqual(button.frame.height, 43)
        }
        XCTAssertTrue(condition.isSelected)
        XCTAssertFalse(precipitation.isSelected)

        precipitation.tap()
        XCTAssertTrue(precipitation.isSelected)
        XCTAssertTrue(waitFor(element("weather.hour.0", in: app), "label CONTAINS %@", "precipitation"), element("weather.hour.0", in: app).label)
        XCTAssertTrue(app.staticTexts["Precipitation chance (%)"].exists)
        XCTAssertTrue(waitFor(element("weather.day.0", in: app), "label CONTAINS %@", "precipitation"))

        wind.tap()
        XCTAssertTrue(wind.isSelected)
        XCTAssertFalse(precipitation.isSelected)
        XCTAssertTrue(waitFor(element("weather.hour.0", in: app), "label CONTAINS %@", " wind "), element("weather.hour.0", in: app).label)
        XCTAssertTrue(element("weather.hour.0", in: app).label.contains("gusts"))
        XCTAssertTrue(waitFor(element("weather.day.0", in: app), "label CONTAINS %@", " wind "))
        XCTAssertTrue(app.staticTexts["Speed (mph) · Gusts"].exists)

        condition.tap()
        XCTAssertTrue(waitFor(element("weather.hour.0", in: app), "label BEGINSWITH %@", "Now Rain"))
    }

    /// The sheet's hours scroll on their own, and Done returns to Home.
    func testSheetCarouselScrolls() throws {
        let app = launch(open: true)
        let carousel = element("weather.hour.carousel", in: app)
        XCTAssertTrue(carousel.waitForExistence(timeout: 15))
        reveal(carousel, in: app)
        let pages = element("weather.hour.pages", in: app)
        carousel.swipeLeft()
        XCTAssertTrue(waitFor(pages, "value BEGINSWITH %@", "Page 2"), "\(String(describing: pages.value))")
        XCTAssertTrue(app.buttons["Close"].exists)
    }

    /// Without forecasts the sheet explains instead of showing blanks.
    func testSheetStatesWithoutForecasts() throws {
        let failing = launch(open: true, state: "error")
        XCTAssertTrue(failing.buttons["Close"].waitForExistence(timeout: 15))
        XCTAssertTrue(element("weather.hourly.message", in: failing).waitForExistence(timeout: 8))
        XCTAssertTrue(element("weather.daily.message", in: failing).exists)
        failing.terminate()
        let empty = launch(open: true, state: "empty")
        XCTAssertTrue(empty.buttons["Close"].waitForExistence(timeout: 15))
        XCTAssertEqual(element("weather.hourly.message", in: empty).label, "No hourly forecast data returned by Pirate Weather.")
    }

    // MARK: - Accessibility

    /// The card at the default size and at AX5: every hour grows with text, nothing clips, targets stay 44 pt.
    func testCardAudit() throws {
        let app = launch()
        XCTAssertTrue(element("home.weather.hour.0", in: app).waitForExistence(timeout: 15))
        try audit(app, ax5Page: { self.launchSettled(arguments: FentonHomeApp.ax5) })
    }

    func testCardAtAX5() throws {
        let app = launch(arguments: FentonHomeApp.ax5)
        let card = app.buttons["home.weather.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        XCTAssertTrue(card.isHittable)
        XCTAssertGreaterThanOrEqual(card.frame.height, 44)
        XCTAssertTrue(element("home.weather.hour.0", in: app).waitForExistence(timeout: 8))
        let pages = element("home.weather.pages", in: app)
        XCTAssertTrue((pages.value as? String ?? "").hasPrefix("Page 1 of"), "AX5 holds fewer hours per page, so there are more pages")
        // The AX5 audit runs as `testCardAudit`'s AX5 page, where partial Dynamic Type issues are checked against the
        // default size (Festival's dynamic-type-grows waiver); alone it reports them as false positives.
    }

    /// The sheet at the default size and at AX5, scrolled to its top.
    func testSheetAudit() throws {
        let app = launch(open: true)
        XCTAssertTrue(element("weather.today.headline", in: app).waitForExistence(timeout: 15))
        try audit(app, presenter: app.buttons["home.weather.card"], ax5Page: { self.launchSettled(open: true, arguments: FentonHomeApp.ax5) })
    }

    func testSheetAtAX5() throws {
        let app = launch(open: true, arguments: FentonHomeApp.ax5)
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15))
        XCTAssertTrue(element("weather.hero.temperature", in: app).waitForExistence(timeout: 8))
        // At AX5 the tiles drop to one column instead of clipping.
        let feels = element("weather.highlight.feels", in: app)
        reveal(feels, in: app)
        let uv = element("weather.highlight.uv", in: app)
        reveal(uv, in: app)
        XCTAssertGreaterThan(feels.frame.width, app.windows.firstMatch.frame.width * 0.6, "Tiles should reflow to a single column")
        // Audited alone, AX5 reports partial Dynamic Type on texts that do grow ('Now', the briefing's bullet, the
        // hourly subhead, iPhone 2026-10-15), so the AX5 page is the evidence in `testSheetAudit` and
        // `testSheetHighlightsAudit`, measured against the default size (Festival's dynamic-type-grows waiver).
    }

    /// The sheet scrolled to its highlights at the default size, with the AX5 page as the Dynamic Type evidence.
    func testSheetHighlightsAudit() throws {
        let app = launch(open: true)
        XCTAssertTrue(element("weather.hero.temperature", in: app).waitForExistence(timeout: 15))
        reveal(element("weather.highlight.uv", in: app), in: app)
        try audit(app, presenter: app.buttons["home.weather.card"], ax5Page: { self.launchSettled(open: true, arguments: FentonHomeApp.ax5) })
    }

    /// Night and storm scenes keep text legible.
    func testNightSceneAudit() throws {
        let app = launch(open: true, condition: "clear-night", night: true)
        XCTAssertTrue(element("weather.today.headline", in: app).waitForExistence(timeout: 15))
        try audit(app, presenter: app.buttons["home.weather.card"])
    }

    private func launchSettled(open: Bool = false, arguments: [String] = []) -> XCUIApplication {
        let app = launch(open: open, arguments: arguments)
        _ = element(open ? "weather.today.headline" : "home.weather.hour.0", in: app).waitForExistence(timeout: 15)
        return app
    }
}
