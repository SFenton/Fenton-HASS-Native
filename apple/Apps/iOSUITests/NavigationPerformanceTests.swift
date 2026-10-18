import XCTest

/// What navigation costs: tab switches, pushes and pops of a room page, sheets and zooms, measured by the app itself
/// (`NavigationTelemetry`, `NavigationMeasurement`) and read back through its `diagnostics.navperf` element
/// (`.agents/design/motion.md` §10, `.agents/testing/apple/performance.md`, "Navigation").
///
/// **Simulator** tests assert the CPU budgets: the transition's 95th-percentile run-loop turn at most 8 ms, none over 16 ms, a tab
/// tap to its first frame at most 50 ms at the 95th percentile. Simulator hitch ratios and GPU cost are false and not asserted.
/// They run only with `TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1` (`tools/ios_navperf.sh` sets it), so the normal journeys skip them.
/// **Device** tests (`testDevice...`) measure with `XCTOSSignpostMetric.navigationTransitionMetric` and the app's own signposts,
/// and skip on a simulator; they need the owner's say-so before a planner runs them.
@MainActor
final class NavigationPerformanceTests: JourneyTestCase {
    enum Budget {
        /// The 95th percentile of a transition's run-loop turn, in ms (a 120 Hz frame is 8.3).
        static let turnP95 = 8.0
        /// The longest turn of any transition.
        static let worstTurn = 16.0
        /// Tab tap to the destination's first frame, 95th percentile.
        static let tabFirstFrameP95 = 50.0
        /// Push or sheet tap to settled (the system transition plus the page).
        static let settled = 600.0
    }

    static let repeats = 10

    // MARK: - Running

    private func requireSimulatorOptIn() throws {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["FENTON_PERF_ON_SIMULATOR"] != "1" {
            throw XCTSkip("Set TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1 to measure navigation cost on a simulator.")
        }
        #endif
    }

    private func requireDevice() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Navigation transition metrics are only meaningful on a physical device.")
        #endif
    }

    private func post(_ name: String) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }

    /// The probe's numbers as `key=value`.
    struct Reading {
        var values: [String: Double] = [:]
        init(_ line: String) {
            for pair in line.split(separator: " ") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2, let number = Double(parts[1]) { values[String(parts[0])] = number }
            }
        }
        subscript(key: String) -> Double? { values[key] }
    }

    private func report(_ app: XCUIApplication) -> Reading {
        post("com.sfenton.home.navperf.report")
        let element = app.descendants(matching: .any)["diagnostics.navperf"].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 10), "The navigation probe is not in the app")
        let predicate = NSPredicate(format: "label != 'ready' AND label != 'reset'")
        _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5)
        return Reading(element.label)
    }

    /// Prints and attaches one `NAVPERF` row per surface for `tools/ios_navperf.sh`.
    private func record(_ scenario: String, _ reading: Reading) {
        for key in reading.values.keys.sorted() where key.hasSuffix(".n") {
            let surface = String(key.dropLast(2))
            func value(_ suffix: String) -> String { reading["\(surface).\(suffix)"].map { String(format: "%.2f", $0) } ?? "-" }
            let row = "NAVPERF\t\(FentonHomeApp.family)\t\(scenario)\t\(surface)\tn=\(value("n"))\tfirst.p50=\(value("first.p50"))\tfirst.p95=\(value("first.p95"))"
                + "\tsettled.p50=\(value("settled.p50"))\tsettled.p95=\(value("settled.p95"))\tturn.p95=\(value("turn.p95"))\tturn.worst=\(value("turn.worst"))"
            print(row)
            add(XCTAttachment(string: row))
            append(row + "\n")
        }
    }

    /// Appends to the TSV `tools/ios_navperf.sh` reads (`TEST_RUNNER_FENTON_NAVPERF_OUT`, default `/tmp/fenton-navperf.tsv`).
    private func append(_ text: String) {
        let path = ProcessInfo.processInfo.environment["FENTON_NAVPERF_OUT"] ?? "/tmp/fenton-navperf.tsv"
        guard let data = text.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }

    private func assertWithinCPUBudget(_ reading: Reading, surfaces: [String], scenario: String) {
        for surface in surfaces {
            XCTAssertGreaterThan(reading["\(surface).n"] ?? 0, 0, "\(scenario): no \(surface) was measured")
            if let turn = reading["\(surface).turn.p95"] {
                XCTAssertLessThanOrEqual(turn, Budget.turnP95, "\(scenario): \(surface) p95 run-loop turn")
            }
            if let worst = reading["\(surface).turn.worst"] {
                XCTAssertLessThanOrEqual(worst, Budget.worstTurn, "\(scenario): \(surface) longest run-loop turn")
            }
        }
    }

    private func launchGallery(_ page: String, environment: [String: String] = [:]) -> XCUIApplication {
        let app = FentonHomeApp.launchGallery(page, environment: environment.merging(["FENTON_TELEMETRY": "1", "FENTON_NAVPERF": "1"]) { $1 })
        return app
    }

    private func launchLive() throws -> XCUIApplication {
        try requireSimulatorOptIn()
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_TELEMETRY": "1", "FENTON_NAVPERF": "1"])
        sleep(10) // The first states, the weather and the images settle.
        return app
    }

    private func tab(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.tabBars.buttons[title].exists ? app.tabBars.buttons[title] : app.toolbars.buttons[title]
    }

    // MARK: - Simulator (CPU budgets)

    /// Every tab three times, then back to Home: a cut each time.
    func testTabCycleStaysWithinBudget() throws {
        let app = try launchLive()
        guard tab("Climate", in: app).exists else { throw XCTSkip("This window navigates with the flyout, not tabs") }
        post("com.sfenton.home.navperf.reset")
        for _ in 0..<3 {
            for (section, title) in [("security", "Security"), ("climate", "Climate"), ("chores", "Chores"), ("settings", "Settings"), ("home", "Home")] {
                openSection(section, title: title, in: app)
                usleep(400_000)
            }
        }
        let reading = report(app)
        record("tab cycle", reading)
        assertWithinCPUBudget(reading, surfaces: ["tabSwitch"], scenario: "tab cycle")
        if let first = reading["tabSwitch.first.p95"] {
            XCTAssertLessThanOrEqual(first, Budget.tabFirstFrameP95, "Tab tap to the destination's first frame, p95")
        }
    }

    /// Home, away and back to Home again: the revisit is instant, and costs what a cut costs.
    func testHomeRevisitStaysWithinBudget() throws {
        let app = try launchLive()
        guard tab("Climate", in: app).exists else { throw XCTSkip("This window navigates with the flyout, not tabs") }
        post("com.sfenton.home.navperf.reset")
        for _ in 0..<Self.repeats {
            openSection("climate", title: "Climate", in: app)
            openSection("home", title: "Home", in: app)
            XCTAssertTrue(app.buttons["home.chip.lights"].exists, "Home was not there on the revisit")
        }
        let reading = report(app)
        record("home revisit", reading)
        assertWithinCPUBudget(reading, surfaces: ["tabSwitch"], scenario: "home revisit")
        if let first = reading["tabSwitch.first.p95"] {
            XCTAssertLessThanOrEqual(first, Budget.tabFirstFrameP95, "Home revisit first frame, p95")
        }
    }

    /// A room page pushed and popped ten times from the Rooms gallery (fixtures, no house).
    func testPushAndPopRoomStaysWithinBudget() throws {
        try requireSimulatorOptIn()
        let app = launchGallery("rooms")
        let living = app.buttons["gallery.room.living-room"]
        XCTAssertTrue(living.waitForExistence(timeout: 30))
        sleep(2)
        post("com.sfenton.home.navperf.reset")
        for _ in 0..<Self.repeats {
            living.tap()
            XCTAssertTrue(element("room.scroll.living-room", in: app).waitForExistence(timeout: 10))
            let back = app.buttons["BackButton"]
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            back.tap()
            XCTAssertTrue(living.waitForExistence(timeout: 5))
        }
        let reading = report(app)
        record("push/pop room", reading)
        assertWithinCPUBudget(reading, surfaces: ["push", "pop"], scenario: "push/pop room")
        if let settled = reading["push.settled.p95"] { XCTAssertLessThanOrEqual(settled, Budget.settled, "Push tap to settled, p95") }
    }

    /// A sheet opened and closed ten times (Quick Links, from the Rooms gallery).
    func testSheetOpenAndCloseStaysWithinBudget() throws {
        try requireSimulatorOptIn()
        let app = launchGallery("rooms")
        let open = app.buttons["gallery.quickLinks"]
        XCTAssertTrue(open.waitForExistence(timeout: 30))
        sleep(2)
        post("com.sfenton.home.navperf.reset")
        for _ in 0..<Self.repeats {
            open.tap()
            let close = app.buttons["sheet.close"]
            XCTAssertTrue(close.waitForExistence(timeout: 10))
            XCTAssertTrue(close.wait(for: \.isHittable, toEqual: true, timeout: 5))
            close.tap()
            XCTAssertTrue(open.waitForExistence(timeout: 5))
            XCTAssertTrue(open.wait(for: \.isHittable, toEqual: true, timeout: 5))
        }
        let reading = report(app)
        record("sheet open/close", reading)
        assertWithinCPUBudget(reading, surfaces: ["sheetPresent", "sheetDismiss"], scenario: "sheet open/close")
        if let settled = reading["sheetPresent.settled.p95"] { XCTAssertLessThanOrEqual(settled, Budget.settled, "Sheet present to settled, p95") }
    }

    /// A room tile zooming into its page and back ten times (iOS 18 and later; before it, a push, recorded as one).
    func testZoomOpenAndCloseStaysWithinBudget() throws {
        let app = try launchLive()
        app.buttons["home.chip.lights"].tap()
        let room = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'overview.lights.room.'")).firstMatch
        XCTAssertTrue(room.waitForExistence(timeout: 10))
        XCTAssertTrue(room.wait(for: \.isHittable, toEqual: true, timeout: 5))
        let identifier = room.identifier
        post("com.sfenton.home.navperf.reset")
        for _ in 0..<Self.repeats {
            app.buttons[identifier].tap()
            XCTAssertTrue(element("overview.detail.subtitle", in: app).waitForExistence(timeout: 10))
            app.buttons["BackButton"].tap()
            XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons[identifier].wait(for: \.isHittable, toEqual: true, timeout: 5))
        }
        let reading = report(app)
        record("zoom room", reading)
        if #available(iOS 18, *) {
            assertWithinCPUBudget(reading, surfaces: ["zoomOpen", "zoomClose"], scenario: "zoom room")
        } else {
            assertWithinCPUBudget(reading, surfaces: ["push", "pop"], scenario: "zoom room (push fallback)")
        }
    }

    // MARK: - Device (signposts and Apple's transition metric)

    /// Tab switches, pushes and sheets on a phone, with Apple's navigation transition metric and the app's own signposts.
    func testDeviceNavigationTransitionMetrics() throws {
        try requireDevice()
        let app = launchGallery("rooms")
        let living = app.buttons["gallery.room.living-room"]
        XCTAssertTrue(living.waitForExistence(timeout: 30))
        var metrics: [XCTMetric] = [XCTOSSignpostMetric.navigationTransitionMetric]
        for name in ["Push", "Pop", "SheetPresent", "SheetDismiss"] {
            metrics.append(XCTOSSignpostMetric(subsystem: "com.sfenton.home", category: "Performance", name: name))
        }
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        measure(metrics: metrics, options: options) {
            living.tap()
            _ = element("room.scroll.living-room", in: app).waitForExistence(timeout: 10)
            app.buttons["BackButton"].tap()
            let open = app.buttons["gallery.quickLinks"]
            open.tap()
            let close = app.buttons["sheet.close"]
            _ = close.waitForExistence(timeout: 10)
            close.tap()
        }
    }

    /// The zoom into a room tile on a phone (iOS 18 and later).
    func testDeviceZoomTransitionMetrics() throws {
        try requireDevice()
        guard #available(iOS 18, *) else { throw XCTSkip("The zoom transition needs iOS 18") }
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_TELEMETRY": "1"])
        app.buttons["home.chip.lights"].tap()
        let room = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'overview.lights.room.'")).firstMatch
        XCTAssertTrue(room.waitForExistence(timeout: 10))
        let identifier = room.identifier
        let metrics: [XCTMetric] = [
            XCTOSSignpostMetric.navigationTransitionMetric,
            XCTOSSignpostMetric(subsystem: "com.sfenton.home", category: "Performance", name: "ZoomOpen"),
            XCTOSSignpostMetric(subsystem: "com.sfenton.home", category: "Performance", name: "ZoomClose"),
        ]
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        measure(metrics: metrics, options: options) {
            app.buttons[identifier].tap()
            _ = element("overview.detail.subtitle", in: app).waitForExistence(timeout: 10)
            app.buttons["BackButton"].tap()
            _ = app.buttons[identifier].waitForExistence(timeout: 5)
        }
    }
}
