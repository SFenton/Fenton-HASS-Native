import XCTest

/// The Home weather card's header, option D (`.agents/design/weather-card-header.md`): the numeral never truncates, the condition
/// stays on one line below accessibility sizes (and scrolls as a ticker only when it overflows), Reduce Motion wraps it, and the
/// card button keeps a 44 pt target. Runs on iPhone, iPhone Duo (folded and unfolded) and iPad, whichever simulator the run is on.
///
/// The ticker's text is hidden from accessibility, so the tests read its state from the invisible `home.weather.condition` element
/// the app adds under `FENTON_TICKER_PROBE=1` (`TickerLabel`'s probe): `overflow`, `running`, `finished`, `wraps`, `lines`.
@MainActor
final class WeatherHeaderJourneyTests: JourneyTestCase {
    /// The Duo unfolded is the one phone family that rotates here (landscape unfolds it to two screens).
    override class var rotatingFamilies: [FentonHomeApp.Family] { [.iPad, .iPhoneDuo] }

    static let large = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
    static let xxxLarge = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"]
    static let ax2 = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]

    /// "Rain": fits every column.
    static let shortCondition = "rainy"
    /// A label far wider than any column on the supported devices (the gallery title-cases an unknown condition).
    static let longCondition = "heavy-thunderstorm-with-hail-and-damaging-wind-gusts-across-the-entire-county-tonight"

    // MARK: - Helpers

    private func launch(condition: String, arguments: [String] = [], settings: [FentonHomeApp.SystemSetting] = []) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "weather"
        app.launchEnvironment["FENTON_GALLERY_WEATHER_CONDITION"] = condition
        app.launchEnvironment["FENTON_TICKER_PROBE"] = "1"
        app.launchEnvironment.merge(FentonHomeApp.SystemSetting.environment(settings)) { _, new in new }
        app.launchArguments += arguments
        app.launch()
        XCTAssertTrue(app.buttons["home.weather.card"].waitForExistence(timeout: 15), "The weather card did not appear")
        return app
    }

    private struct TickerState {
        var values: [String: Int] = [:]
        init(_ label: String) {
            for pair in label.split(separator: " ") {
                let parts = pair.split(separator: "=")
                if parts.count == 2, let number = Int(parts[1]) { values[String(parts[0])] = number }
            }
        }
        subscript(key: String) -> Int { values[key] ?? -1 }
    }

    /// The ticker's state, once its line has been measured (a `lines` count above 0).
    private func state(_ app: XCUIApplication, timeout: TimeInterval = 10) -> TickerState {
        let probe = app.descendants(matching: .any)["home.weather.condition"].firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: timeout), "The ticker probe is missing (FENTON_TICKER_PROBE)")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, TickerState(probe.label)["lines"] < 1 { usleep(100_000) }
        return TickerState(probe.label)
    }

    /// Keeps the card's screenshot, and writes it to `FENTON_WEATHER_HEADER_SHOTS` when that names a folder.
    private func shoot(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["FENTON_WEATHER_HEADER_SHOTS"], !folder.isEmpty {
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(layout)-\(name).png"))
        }
    }

    // MARK: - Numeral

    /// The reading is never cut: the button holds the numeral and chevron at their natural width, so it is wider than it is tall
    /// at the default sizes and never narrower than a short three-character reading would be, and it stays inside the card.
    private func assertNumeralWhole(_ app: XCUIApplication, _ size: String, file: StaticString = #filePath, line: UInt = #line) {
        let card = app.buttons["home.weather.card"]
        let module = app.descendants(matching: .any)["home.weather"].firstMatch
        XCTAssertTrue(module.exists, file: file, line: line)
        XCTAssertGreaterThanOrEqual(card.frame.width, 0.9 * card.frame.height, "The numeral looks cut at \(size): \(card.frame)", file: file, line: line)
        XCTAssertLessThanOrEqual(card.frame.maxX, module.frame.maxX + 0.5, "The numeral leaves the card at \(size)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(card.frame.minX, module.frame.minX, "The numeral leaves the card at \(size)", file: file, line: line)
    }

    func testNumeralIsNeverTruncated() {
        for (size, arguments) in [("Large", Self.large), ("xxxLarge", Self.xxxLarge), ("AX5", FentonHomeApp.ax5)] {
            for condition in [Self.shortCondition, Self.longCondition] {
                let app = launch(condition: condition, arguments: arguments)
                assertNumeralWhole(app, "\(size) \(condition)")
                app.terminate()
            }
        }
    }

    // MARK: - Condition

    func testConditionIsOneLineBelowAccessibilitySizes() {
        for (size, arguments) in [("Large", Self.large), ("xxxLarge", Self.xxxLarge)] {
            let app = launch(condition: Self.longCondition, arguments: arguments)
            let ticker = state(app)
            XCTAssertEqual(ticker["lines"], 1, "The condition wraps at \(size)")
            XCTAssertEqual(ticker["wraps"], 0, size)
            app.terminate()
        }
    }

    func testConditionWrapsAtAccessibilitySizes() {
        let app = launch(condition: Self.longCondition, arguments: FentonHomeApp.ax5)
        let ticker = state(app)
        XCTAssertEqual(ticker["wraps"], 1)
        XCTAssertGreaterThan(ticker["lines"], 1, "A long condition wraps at AX5")
        XCTAssertEqual(ticker["running"], 0)
        assertNumeralWhole(app, "AX5")
    }

    func testTickerStartsOnlyWhenTheConditionOverflows() {
        var app = launch(condition: Self.shortCondition, arguments: Self.large)
        var ticker = state(app)
        XCTAssertEqual(ticker["overflow"], 0, "A short condition fits")
        XCTAssertEqual(ticker["running"], 0, "A short condition does not tick")
        XCTAssertEqual(ticker["lines"], 1)
        app.terminate()

        app = launch(condition: Self.longCondition, arguments: Self.large)
        ticker = state(app)
        XCTAssertEqual(ticker["overflow"], 1, "The long condition overflows its column")
        XCTAssertEqual(ticker["lines"], 1)
        let probe = app.descendants(matching: .any)["home.weather.condition"].firstMatch
        let running = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'running=1'"), object: probe)
        XCTAssertEqual(XCTWaiter().wait(for: [running], timeout: 8), .completed, "The ticker never started: \(probe.label)")
    }

    func testReduceMotionWrapsTheConditionInsteadOfTicking() {
        let app = launch(condition: Self.longCondition, arguments: Self.large, settings: [.reduceMotion])
        let ticker = state(app)
        XCTAssertEqual(ticker["wraps"], 1)
        XCTAssertEqual(ticker["running"], 0)
        XCTAssertGreaterThan(ticker["lines"], 1, "With Reduce Motion the long condition wraps")
        assertNumeralWhole(app, "Large, Reduce Motion")
    }

    // MARK: - Accessibility

    func testCardKeepsItsNameAndA44PointTarget() {
        for (size, arguments) in [("Large", Self.large), ("AX5", FentonHomeApp.ax5)] {
            let app = launch(condition: Self.longCondition, arguments: arguments)
            let card = app.buttons["home.weather.card"]
            XCTAssertTrue(card.label.hasPrefix("Open seven-day weather forecast. "), card.label)
            XCTAssertTrue(card.isHittable, size)
            XCTAssertGreaterThanOrEqual(card.frame.height, 44, size)
            XCTAssertGreaterThanOrEqual(card.frame.width, 44, size)
            // The condition and the range read in order: the range is its own element under the card's button.
            let today = app.descendants(matching: .any)["home.weather.today"].firstMatch
            XCTAssertTrue(today.waitForExistence(timeout: 8), size)
            XCTAssertTrue(today.label.hasPrefix("Today "), today.label)
            app.terminate()
        }
    }

    func testHeaderPassesTheAccessibilityAudit() throws {
        guard ProcessInfo.processInfo.environment["FENTON_SKIP_AUDIT"] != "1" else { return }
        let app = launch(condition: Self.longCondition, arguments: Self.large)
        try FentonHomeApp.audit(app, ax5Page: { self.launch(condition: Self.longCondition, arguments: FentonHomeApp.ax5) }, presenter: nil)
    }

    // MARK: - Evidence

    /// The card at Large, xxxLarge and AX2 with a short and a long label (screenshots for the PR).
    func testCaptureTheHeaderAtThreeSizes() {
        for (size, arguments) in [("large", Self.large), ("xxxlarge", Self.xxxLarge), ("ax2", Self.ax2)] {
            for (name, condition) in [("short", Self.shortCondition), ("long", Self.longCondition)] {
                let app = launch(condition: condition, arguments: arguments)
                _ = state(app)
                shoot(app, "header-\(size)-\(name)")
                app.terminate()
            }
        }
    }
}
