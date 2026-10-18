import XCTest

/// The Live Activity cards in the debug gallery (`live-activity`): the Lock Screen card, the Dynamic Island stand-ins and
/// the small family, over fixtures, with their buttons, on iPhone, iPhone Duo and iPad
/// (`.agents/platforms/apple/live-activities-per-job.md` §8, §12). Names, roles, reading order, 44 pt targets, AX5 layout,
/// the 160 pt height limit and the expanded island's clipping check.
@MainActor
final class LiveActivityJourneyTests: JourneyTestCase {
    private func launch(_ scenario: String, arguments: [String] = [], identifier: String? = nil) -> XCUIApplication {
        let app = FentonHomeApp.launchGallery("live-activity", arguments: arguments, environment: ["FENTON_GALLERY_SCENARIO": scenario])
        let first = identifier.map { element($0, in: app) } ?? app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'liveactivity.'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), "\(scenario) did not draw")
        return app
    }

    private func lastAction(_ app: XCUIApplication) -> String {
        app.staticTexts["gallery.lastCall"].label.replacing("Last action: ", with: "")
    }

    /// The identifiers of every card a group draws.
    private func cards(in app: XCUIApplication) -> [XCUIElement] {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'liveactivity.card.'")).allElementsBoundByIndex
    }

    // MARK: Size

    /// The Lock Screen limit is 160 pt; a taller view is cut off by the system, so every card must fit.
    func testEveryCardFitsTheLockScreensHeightLimit() {
        var count = 0
        for group in ["jobs", "complete", "vacuum", "hotflash", "states", "stack", "problems", "problems-flipped"] {
            let app = launch(group, identifier: nil)
            let found = cards(in: app)
            XCTAssertFalse(found.isEmpty, "\(group) drew no cards")
            for card in found {
                let frame = card.frame
                XCTAssertLessThanOrEqual(frame.height, 160, "\(card.identifier) is \(Int(frame.height)) pt tall")
                XCTAssertGreaterThan(frame.height, 60, "\(card.identifier) drew almost nothing")
                XCTAssertLessThanOrEqual(frame.width, 371, "\(card.identifier) is wider than a Lock Screen")
                count += 1
            }
            keepScreenshot(app, "live-activity-\(group)-\(layout)")
            app.terminate()
        }
        XCTAssertGreaterThan(count, 60, "every fixture card was measured")
    }

    // MARK: Names, roles and order

    /// Buttons are named for their device, are at least 44 pt, and read in order with Done last.
    func testButtonsAreNamedLargeEnoughAndInReadingOrder() {
        let stack = launch("stack")
        for name in ["Stop Guest Bath Fan", "Stop Dishwasher"] {
            let button = stack.buttons[name]
            XCTAssertTrue(button.exists, name)
            assertTarget(button)
        }
        XCTAssertFalse(stack.buttons["Stop Washing Machine"].exists, "laundry has no buttons")
        XCTAssertFalse(stack.buttons["Stop Dryer"].exists)

        let problem = launch("problem-navigation-stuck", identifier: "liveactivity.lockscreen")
        let lock = element("liveactivity.lockscreen", in: problem)
        let resume = lock.buttons["Resume Main Floor Vacuum"], dock = lock.buttons["Dock Main Floor Vacuum"], done = lock.buttons["Done Main Floor Vacuum"]
        for button in [resume, dock, done] {
            XCTAssertTrue(button.exists, button.label)
            assertTarget(button)
        }
        XCTAssertLessThan(resume.frame.minX, dock.frame.minX, "the primary button reads first")
        XCTAssertLessThan(dock.frame.minX, done.frame.minX, "Done is last")
        let phrase = problem.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Main Floor Vacuum, needs help'")).firstMatch
        XCTAssertEqual(phrase.label, "Main Floor Vacuum, needs help: Stuck in Kitchen. Move it somewhere flat, then tap Resume.")
        XCTAssertLessThan(phrase.frame.minY, resume.frame.minY + 1, "the card is read before its buttons")
    }

    func testAWarningReadsNeedsAttentionAndAChipIsPartOfTheSentence() {
        let warning = launch("problem-mop-clean_water_empty")
        let phrase = warning.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Main Floor Vacuum, needs attention'")).firstMatch
        XCTAssertTrue(phrase.exists)
        XCTAssertTrue(phrase.label.hasPrefix("Main Floor Vacuum, needs attention: Clean water tank empty."))
        let numbered = launch("problem-vendor-unknown_error_88")
        XCTAssertGreaterThan(numbered.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH 'Error 88'")).count, 0)
    }

    /// A job card is a title and a live figure in one element, with the words that make the figure a sentence.
    func testJobCardsReadTheirTitleAndFigure() {
        let dryer = launch("dryer")
        XCTAssertGreaterThan(dryer.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Dryer, running for'")).count, 0,
                             "a count-up reads \"running for\"")
        let vacuum = launch("vacuum-paused")
        XCTAssertGreaterThan(vacuum.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Paused in Kitchen, paused at'")).count, 0)
        XCTAssertTrue(vacuum.buttons["Resume Main Floor Vacuum"].exists && vacuum.buttons["Dock Main Floor Vacuum"].exists)
        let hot = launch("hotflash-bysteph")
        XCTAssertGreaterThan(hot.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Hot Flash' AND label CONTAINS 'Your side · by Steph'")).count, 0)
        let complete = launch("washer-complete")
        XCTAssertGreaterThan(complete.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Complete'")).count, 0)
        XCTAssertEqual(complete.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Stop'")).count, 0, "a finished card has no buttons")
    }

    // MARK: Pending

    /// A button shows the card as pending at once and puts its pill away (optimistic, until Home Assistant confirms).
    func testStopShowsStoppingAndHidesTheButton() {
        let app = launch("fan", identifier: "liveactivity.lockscreen")
        let lock = element("liveactivity.lockscreen", in: app)
        lock.buttons["Stop Guest Bath Fan"].tap()
        XCTAssertEqual(lastAction(app), "stop job.fan.guest")
        XCTAssertTrue(lock.staticTexts["Stopping…"].waitForExistence(timeout: 5))
        XCTAssertFalse(lock.buttons["Stop Guest Bath Fan"].exists)
        keepScreenshot(app, "live-activity-stopping-pressed-\(layout)")
    }

    func testAStalePendingStateGivesTheButtonBackWithNotConfirmed() {
        let app = launch("fan-pending-stale", identifier: "liveactivity.lockscreen")
        let lock = element("liveactivity.lockscreen", in: app)
        XCTAssertTrue(lock.buttons["Stop Guest Bath Fan"].exists, "the controls come back")
        XCTAssertTrue(lock.staticTexts["Not confirmed"].exists)
        XCTAssertFalse(lock.staticTexts["Stopping…"].exists)
        let pending = launch("fan-pending", identifier: "liveactivity.lockscreen")
        XCTAssertTrue(element("liveactivity.lockscreen", in: pending).staticTexts["Stopping…"].exists)
        XCTAssertFalse(element("liveactivity.lockscreen", in: pending).staticTexts["Not confirmed"].exists)
    }

    func testANoticeReplacesTheFigureForOneUpdate() {
        let app = launch("fan-notice", identifier: "liveactivity.lockscreen")
        let lock = element("liveactivity.lockscreen", in: app)
        XCTAssertTrue(lock.staticTexts["Couldn't reach Home"].exists)
        XCTAssertTrue(lock.buttons["Stop Guest Bath Fan"].exists, "the button is back")
    }

    func testDoneOnAProblemShowsCompleting() {
        let app = launch("problem-navigation-stuck", identifier: "liveactivity.lockscreen")
        let lock = element("liveactivity.lockscreen", in: app)
        lock.buttons["Done Main Floor Vacuum"].tap()
        XCTAssertEqual(lastAction(app), "done job.vacuum.main_floor")
        XCTAssertTrue(lock.staticTexts["Completing…"].waitForExistence(timeout: 5))
    }

    // MARK: Large text

    /// At the largest text size nothing runs off the screen, the figure wraps under the title and the targets hold.
    func testLargestTextSizeKeepsEveryCardOnScreenAndTheTargets() {
        for scenario in ["fan", "vacuum", "hotflash-cooling", "problem-navigation-stuck", "problem-vendor-unknown_error_88"] {
            let app = launch(scenario, arguments: FentonHomeApp.ax5, identifier: "liveactivity.lockscreen")
            let window = app.windows.firstMatch.frame
            let lock = element("liveactivity.lockscreen", in: app)
            XCTAssertLessThanOrEqual(lock.frame.maxX, window.maxX + 0.5, scenario)
            XCTAssertGreaterThanOrEqual(lock.frame.minX, window.minX - 0.5, scenario)
            for button in lock.buttons.allElementsBoundByIndex {
                assertTarget(button)
                XCTAssertLessThanOrEqual(button.frame.maxX, window.maxX + 0.5, "\(scenario) \(button.label) runs off the screen")
                XCTAssertGreaterThanOrEqual(button.frame.minX, lock.frame.minX - 0.5, "\(scenario) \(button.label) runs off the card")
            }
            keepScreenshot(app, "live-activity-\(scenario)-ax5-\(layout)")
            app.terminate()
        }
    }

    // MARK: Island

    /// The island stand-ins and the small family draw on every device.
    func testIslandPresentationsAndTheSmallFamilyDraw() {
        for scenario in ["fan", "problem-navigation-stuck"] {
            let app = launch(scenario, identifier: "liveactivity.lockscreen")
            for kind in ["compact", "minimal", "expanded"] {
                XCTAssertTrue(element("liveactivity.island.\(kind)", in: app).exists, "\(scenario) \(kind)")
            }
            XCTAssertTrue(element("liveactivity.small", in: app).exists)
            let expanded = element("liveactivity.island.expanded", in: app)
            XCTAssertTrue(expanded.buttons.firstMatch.exists)
            for button in expanded.buttons.allElementsBoundByIndex { assertTarget(button) }
            app.swipeUp()
            keepScreenshot(app, "live-activity-islands-\(scenario)-\(layout)")
            app.terminate()
        }
    }

    /// The expanded island on the smallest, a standard and the largest camera region with an `H:MM:SS` figure: only the ring
    /// and the figure sit beside the camera, the figure stays inside its region, and its natural width fits the region
    /// without elision.
    func testTheExpandedIslandNeverClipsALongTimeOnEveryCameraWidth() {
        let app = launch("island-widths", identifier: "liveactivity.islandsize.older-pro")
        let expected: [String: CGFloat] = ["older-pro": 104.5, "narrow-camera": 120, "pro-max": 128]
        for (size, regionWidth) in expected {
            let island = element("liveactivity.islandsize.\(size)", in: app)
            XCTAssertTrue(island.exists, size)
            let trailing = island.descendants(matching: .any).matching(identifier: "liveactivity.island.trailing").firstMatch
            let leading = island.descendants(matching: .any).matching(identifier: "liveactivity.island.leading").firstMatch
            XCTAssertTrue(trailing.exists && leading.exists, "\(size) draws both regions")
            XCTAssertEqual(trailing.frame.width, regionWidth, accuracy: 1, "\(size) trailing region")
            XCTAssertEqual(leading.frame.width, regionWidth, accuracy: 1, "\(size) leading region")
            let figure = trailing.staticTexts.firstMatch
            XCTAssertTrue(figure.exists, "\(size) has a figure")
            XCTAssertGreaterThanOrEqual(figure.frame.minX, trailing.frame.minX - 0.5, "\(size) figure leaves its region on the left")
            XCTAssertLessThanOrEqual(figure.frame.maxX, trailing.frame.maxX + 0.5, "\(size) figure leaves its region on the right")
            XCTAssertLessThanOrEqual(trailing.frame.maxX, island.frame.maxX - 17, "\(size) the region stays inside the island")
            // The same figure at its natural 22 pt width fits the region even before the 0.8 scale floor.
            let probe = element("liveactivity.probe.\(size)", in: app)
            XCTAssertTrue(probe.exists, "\(size) probe")
            XCTAssertLessThanOrEqual(probe.frame.width, regionWidth, "\(size): \"1:04:42\" at 22 pt is \(Int(probe.frame.width)) pt, the region \(regionWidth)")
            // The title and buttons are below the camera, not beside it.
            let bottom = island.descendants(matching: .any).matching(identifier: "liveactivity.island.bottom").firstMatch
            XCTAssertTrue(bottom.exists)
            XCTAssertGreaterThan(bottom.frame.minY, trailing.frame.maxY - 1, "\(size) the bottom region sits under the camera row")
            for button in bottom.buttons.allElementsBoundByIndex { assertTarget(button) }
        }
        keepScreenshot(app, "live-activity-island-widths-\(layout)")
    }

    // MARK: Accessibility audit

    func testStackPassesAccessibilityAudit() throws {
        let app = launch("stack")
        try FentonHomeApp.audit(app) { self.launch("stack", arguments: FentonHomeApp.ax5) }
    }

    func testProblemCardsPassAccessibilityAudit() throws {
        let app = launch("vacuum")
        try FentonHomeApp.audit(app) { self.launch("vacuum", arguments: FentonHomeApp.ax5) }
        let problems = launch("problem-navigation-stuck")
        try FentonHomeApp.audit(problems) { self.launch("problem-navigation-stuck", arguments: FentonHomeApp.ax5) }
    }

    // MARK: A real activity

    /// Real activities (started locally from fixture content, no Home Assistant and no Apple servers) on the real Lock
    /// Screen: the app starts them, the simulator locks, and SpringBoard shows the cards the extension drew. The simulator
    /// cannot take an ActivityKit push (`xcrun simctl push` refuses it), so this is the closest a host run gets.
    func testRealActivitiesShowOnTheLockScreen() throws {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_UITEST_RESET"] = "1"
        app.launchEnvironment["FENTON_LIVE_ACTIVITY"] = "1"
        app.launchEnvironment["FENTON_LIVE_ACTIVITY_FIXTURE"] = "stack"
        app.launch()
        sleep(8)
        let lock = NSSelectorFromString("pressLockButton")
        guard XCUIDevice.shared.responds(to: lock) else { throw XCTSkip("This runtime has no lock button hook") }
        _ = XCUIDevice.shared.perform(lock)
        sleep(2)
        _ = XCUIDevice.shared.perform(lock)
        sleep(6)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "live-activity-real-lockscreen-\(layout)"
        shot.lifetime = .keepAlways
        add(shot)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // The first request asks "Allow Live Activities from S+H?" under the activity; allowing keeps it.
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        let tree = XCTAttachment(string: springboard.debugDescription)
        tree.name = "springboard-tree-\(layout)"
        tree.lifetime = .keepAlways
        add(tree)
        let rows = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Guest Bath Fan' OR label CONTAINS 'Dishwasher'"))
        if !rows.firstMatch.waitForExistence(timeout: 10) {
            // A simulator that already answered "Don't Allow" never shows the activity: Settings, S+H, Live Activities.
            throw XCTSkip("Live Activities are off for this app on this simulator; turn them on in Settings and rerun")
        }
        XCUIDevice.shared.press(.home)
    }
}
