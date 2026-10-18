import XCTest

/// The Live Activity cards in the debug gallery (`live-activity`): the Lock Screen card (L4), the Dynamic Island stand-ins
/// (compact, minimal, expanded E2c) and the small family, over fixtures, with their buttons, on iPhone, iPhone Duo and iPad
/// (`.agents/platforms/apple/live-activities-per-job.md` §8, §8a, §12). Names, roles, reading order, 44 pt targets, AX5 layout,
/// the 160 pt height limit with two-line titles, the vacuum's round buttons, the compact island's rigid width and the expanded
/// island's clipping check.
@MainActor
final class LiveActivityJourneyTests: JourneyTestCase {
    private func launch(_ scenario: String, arguments: [String] = [], identifier: String? = nil) -> XCUIApplication {
        // The first launch after a simulator boots can stall; one relaunch separates that from a card that really did not draw.
        var app = FentonHomeApp.launchGallery("live-activity", arguments: arguments, environment: ["FENTON_GALLERY_SCENARIO": scenario])
        func first(_ app: XCUIApplication) -> XCUIElement {
            identifier.map { element($0, in: app) } ?? app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'liveactivity.'")).firstMatch
        }
        if !first(app).waitForExistence(timeout: 20) {
            app.terminate()
            app = FentonHomeApp.launchGallery("live-activity", arguments: arguments, environment: ["FENTON_GALLERY_SCENARIO": scenario])
        }
        XCTAssertTrue(first(app).waitForExistence(timeout: 30), "\(scenario) did not draw")
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
        for group in ["jobs", "complete", "vacuums", "hotflash", "states", "stack", "problems", "problems-flipped"] {
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

    /// Long titles wrap to two lines (a card cannot scroll its title), still inside the 160 pt limit; the vacuum's long headline
    /// wraps too.
    func testLongTitlesWrapToTwoLinesAndStillFit() {
        let short = launch("fan", identifier: "liveactivity.lockscreen")
        let shortCard = element("liveactivity.lockscreen", in: short)
        let shortTitle = shortCard.descendants(matching: .any).matching(identifier: "liveactivity.title").firstMatch
        XCTAssertTrue(shortTitle.exists)
        let oneLine = shortTitle.frame.height
        for (scenario, label) in [("fan-xlong", "Master Bedroom Closet Exhaust Fan"), ("hotflash-stephen-bysteph", "Hot Flash · Stephen's side · by Steph")] {
            let app = launch(scenario, identifier: "liveactivity.lockscreen")
            let card = element("liveactivity.lockscreen", in: app)
            let title = card.descendants(matching: .any).matching(identifier: "liveactivity.title").firstMatch
            XCTAssertTrue(title.label.hasPrefix(label), "\(scenario): \(title.label)")
            XCTAssertGreaterThan(title.frame.height, oneLine * 1.6, "\(scenario) wraps to a second line instead of truncating")
            XCTAssertLessThanOrEqual(card.frame.height, 160, "\(scenario) is \(Int(card.frame.height)) pt tall")
            // The corner mark stays top-right and the title does not run under it.
            XCTAssertLessThanOrEqual(title.frame.maxX, card.frame.maxX - 16 - 24, scenario)
            keepScreenshot(app, "live-activity-\(scenario)-\(layout)")
            app.terminate()
        }
        let closet = launch("vacuum-long", identifier: "liveactivity.lockscreen")
        let vacuum = element("liveactivity.lockscreen", in: closet)
        let big = vacuum.descendants(matching: .any).matching(identifier: "liveactivity.value").firstMatch
        XCTAssertTrue(big.label.contains("Vacuuming Master Bedroom Closet"), big.label)
        XCTAssertLessThanOrEqual(vacuum.frame.height, 160)
        keepScreenshot(closet, "live-activity-vacuum-long-\(layout)")
    }

    /// Row 1 is the glyph, the title and the mark; row 2 the value with the buttons beside it; row 3 the bar only with progress.
    func testTheLockScreenRowsAreInOrderAndTheBarNeedsProgress() {
        let fan = launch("fan", identifier: "liveactivity.lockscreen")
        let lock = element("liveactivity.lockscreen", in: fan)
        let title = lock.descendants(matching: .any).matching(identifier: "liveactivity.title").firstMatch
        let value = lock.descendants(matching: .any).matching(identifier: "liveactivity.value").firstMatch
        let stop = lock.buttons["Stop Guest Bath Fan"]
        let bar = lock.descendants(matching: .any).matching(identifier: "liveactivity.bar").firstMatch
        XCTAssertTrue(title.exists && value.exists && stop.exists && bar.exists)
        XCTAssertLessThanOrEqual(title.frame.maxY, value.frame.minY + 1, "the title is row 1, the value row 2")
        XCTAssertLessThan(value.frame.minX, stop.frame.minX, "the button sits right of the value")
        XCTAssertLessThanOrEqual(abs(stop.frame.midY - value.frame.midY), 12, "the button is in the value's row")
        XCTAssertGreaterThanOrEqual(bar.frame.minY, max(value.frame.maxY, stop.frame.maxY) - 8, "the bar is row 3")
        let laundry = launch("dryer", identifier: "liveactivity.lockscreen")
        XCTAssertFalse(element("liveactivity.lockscreen", in: laundry).descendants(matching: .any).matching(identifier: "liveactivity.bar").firstMatch.exists,
                       "a count-up has no progress, so no bar")
    }

    // MARK: Vacuum

    /// A vacuum has no time and no bar anywhere, and its Pause, Resume and Dock are 44 pt round icon buttons with spoken labels.
    func testAVacuumHasNoTimeAndNoBarAndRoundNamedButtons() {
        for (scenario, primary, big) in [("vacuum", "Pause", "Vacuuming Kitchen"), ("vacuum-paused", "Resume", "Paused in Kitchen")] {
            let app = launch(scenario, identifier: "liveactivity.lockscreen")
            let lock = element("liveactivity.lockscreen", in: app)
            let first = lock.buttons["\(primary) Main Floor Vacuum"], dock = lock.buttons["Dock Main Floor Vacuum"]
            XCTAssertTrue(first.exists && dock.exists, scenario)
            for button in [first, dock] {
                assertTarget(button)
                XCTAssertEqual(button.frame.width, button.frame.height, accuracy: 1, "\(button.label) is round (a square target)")
            }
            XCTAssertLessThan(first.frame.minX, dock.frame.minX, "\(primary) reads first")
            XCTAssertFalse(lock.staticTexts[primary].exists, "an icon button has no text pill")
            let value = lock.descendants(matching: .any).matching(identifier: "liveactivity.value").firstMatch
            XCTAssertEqual(value.label, big, scenario)
            let times = lock.staticTexts.matching(NSPredicate(format: "label MATCHES '.*\\d+:\\d\\d.*'"))
            XCTAssertEqual(times.count, 0, "\(scenario) shows no time")
            XCTAssertFalse(lock.descendants(matching: .any).matching(identifier: "liveactivity.bar").firstMatch.exists, "\(scenario) shows no bar")
            XCTAssertLessThan(lock.frame.height, 125, "\(scenario) is \(Int(lock.frame.height)) pt tall")
            keepScreenshot(app, "live-activity-\(scenario)-\(layout)")
            app.terminate()
        }
        // A press still reaches the control map by id.
        let app = launch("vacuum", identifier: "liveactivity.lockscreen")
        element("liveactivity.lockscreen", in: app).buttons["Pause Main Floor Vacuum"].tap()
        XCTAssertEqual(lastAction(app), "pause job.vacuum.main_floor")
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
        XCTAssertGreaterThan(vacuum.descendants(matching: .any).matching(NSPredicate(format: "label == 'Main Floor Vacuum'")).count, 0, "the device is the title")
        XCTAssertGreaterThan(vacuum.descendants(matching: .any).matching(NSPredicate(format: "label == 'Paused in Kitchen'")).count, 0, "the headline is the big line")
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
        for scenario in ["fan", "vacuum", "vacuum-long", "fan-xlong", "dishwasher-long", "hotflash-stephen-bysteph", "hotflash-cooling",
                         "problem-navigation-stuck", "problem-vendor-unknown_error_88"] {
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

    /// The expanded island (E2c) on the smallest, a standard and the largest camera region with an `H:MM:SS` value: only the glyph
    /// and the corner mark sit beside the camera, the value sits below it in the full width beside the buttons without being
    /// clipped, and the bar spans the block.
    func testTheExpandedIslandNeverClipsALongTimeOnEveryCameraWidth() {
        let app = launch("island-widths", identifier: "liveactivity.islandsize.older-pro")
        let expected: [String: CGFloat] = ["older-pro": 104.5, "narrow-camera": 120, "pro-max": 128]
        for (size, regionWidth) in expected {
            let island = element("liveactivity.islandsize.\(size)", in: app)
            XCTAssertTrue(island.exists, size)
            let trailing = island.descendants(matching: .any).matching(identifier: "liveactivity.island.trailing.bounds").firstMatch
            let leading = island.descendants(matching: .any).matching(identifier: "liveactivity.island.leading.bounds").firstMatch
            let shape = island.descendants(matching: .any).matching(identifier: "liveactivity.island.shape").firstMatch
            XCTAssertTrue(trailing.exists && leading.exists && shape.exists, "\(size) draws both regions")
            XCTAssertEqual(trailing.frame.width, regionWidth, accuracy: 1, "\(size) trailing region")
            XCTAssertEqual(leading.frame.width, regionWidth, accuracy: 1, "\(size) leading region")
            XCTAssertLessThanOrEqual(trailing.frame.maxX, shape.frame.maxX - 17, "\(size) the region stays inside the island")
            // Beside the camera: the glyph and the mark only, no text.
            let beside = island.descendants(matching: .any).matching(identifier: "liveactivity.island.trailing").staticTexts
            XCTAssertEqual(beside.count, 0, "\(size) nothing but the corner mark beside the camera on the right")
            XCTAssertEqual(island.descendants(matching: .any).matching(identifier: "liveactivity.island.leading").staticTexts.count, 0, "\(size) nor on the left")
            // Below the camera: title over value, buttons on the right, bar under both.
            let bottom = island.descendants(matching: .any).matching(identifier: "liveactivity.island.bottom").firstMatch
            XCTAssertTrue(bottom.exists)
            XCTAssertGreaterThan(bottom.frame.minY, trailing.frame.maxY - 1, "\(size) the bottom region sits under the camera row")
            let value = bottom.descendants(matching: .any).matching(identifier: "liveactivity.value").firstMatch
            let title = bottom.descendants(matching: .any).matching(identifier: "liveactivity.title").firstMatch
            let stop = bottom.buttons.firstMatch
            XCTAssertTrue(value.exists && title.exists && stop.exists, size)
            XCTAssertLessThanOrEqual(title.frame.maxY, value.frame.minY + 1, "\(size) the title is over the value")
            XCTAssertLessThanOrEqual(value.frame.maxX, stop.frame.minX + 0.5, "\(size) the value stops before the buttons")
            XCTAssertGreaterThanOrEqual(value.frame.minX, shape.frame.minX, size)
            XCTAssertLessThanOrEqual(stop.frame.maxX, shape.frame.maxX - 17, "\(size) the buttons stay inside the island")
            XCTAssertLessThanOrEqual(abs(stop.frame.midY - value.frame.midY), 30, "\(size) the buttons are in line with the title-and-value block")
            // The value at its natural 32 pt width fits the room beside the buttons before any scaling.
            let probe = element("liveactivity.probe.\(size)", in: app)
            XCTAssertTrue(probe.exists, "\(size) probe")
            XCTAssertLessThanOrEqual(probe.frame.width, value.frame.width, "\(size): \"1:04:42\" at 32 pt is \(Int(probe.frame.width)) pt, the room \(Int(value.frame.width))")
            let bar = bottom.descendants(matching: .any).matching(identifier: "liveactivity.bar").firstMatch
            XCTAssertTrue(bar.exists, "\(size) a countdown has a bar")
            XCTAssertGreaterThanOrEqual(bar.frame.minY, value.frame.maxY - 8, "\(size) the bar is under the block")
            for button in bottom.buttons.allElementsBoundByIndex { assertTarget(button) }
        }
        keepScreenshot(app, "live-activity-island-widths-\(layout)")
    }

    /// The compact island's time is as wide as its hidden template ("00:00", or "0:00:00" from an hour), not as wide as the room
    /// the island offers, and a vacuum's word is capped at 56 pt.
    func testTheCompactTimeHasTheWidthOfItsTemplateNotTheRoomTheIslandOffers() {
        let app = launch("compact-widths", identifier: "liveactivity.probe.compact.short")
        let short = element("liveactivity.probe.compact.short", in: app).frame.width
        let hours = element("liveactivity.probe.compact.hours", in: app).frame.width
        XCTAssertGreaterThan(hours, short + 4, "the H:MM:SS template is wider")
        let trailing = app.descendants(matching: .any).matching(identifier: "liveactivity.compact.trailing.bounds").allElementsBoundByIndex
        XCTAssertEqual(trailing.count, 4, "MM:SS, H:MM:SS, and two vacuum words")
        guard trailing.count == 4 else { return }
        XCTAssertEqual(trailing[0].frame.width, short, accuracy: 1, "42:00 takes the 00:00 template width")
        XCTAssertEqual(trailing[1].frame.width, hours, accuracy: 1, "1:04:42 takes the 0:00:00 template width")
        // The stand-in leaves 112 pt beside its ring; a time that reported its widest possible width would take all of it.
        XCTAssertLessThan(trailing[0].frame.width, 60)
        XCTAssertLessThan(trailing[1].frame.width, 70)
        for index in [2, 3] {
            XCTAssertLessThanOrEqual(trailing[index].frame.width, 56.5, "a word is capped at 56 pt")
            XCTAssertGreaterThan(trailing[index].frame.width, 20)
        }
        keepScreenshot(app, "live-activity-compact-widths-\(layout)")
    }

    /// A vacuum in the expanded island: glyph and mark beside the camera, the headline as the big line, round buttons, no bar.
    func testTheExpandedVacuumHasRoundButtonsAndNoBar() {
        let app = launch("vacuum", identifier: "liveactivity.lockscreen")
        let expanded = element("liveactivity.island.expanded", in: app)
        XCTAssertTrue(expanded.exists)
        let pause = expanded.buttons["Pause Main Floor Vacuum"], dock = expanded.buttons["Dock Main Floor Vacuum"]
        XCTAssertTrue(pause.exists && dock.exists)
        for button in [pause, dock] {
            assertTarget(button)
            XCTAssertEqual(button.frame.width, button.frame.height, accuracy: 1, button.label)
        }
        XCTAssertEqual(expanded.descendants(matching: .any).matching(identifier: "liveactivity.value").firstMatch.label, "Vacuuming Kitchen")
        XCTAssertFalse(expanded.descendants(matching: .any).matching(identifier: "liveactivity.bar").firstMatch.exists)
        let compact = element("liveactivity.island.compact", in: app)
        XCTAssertTrue(compact.exists)
        XCTAssertGreaterThan(compact.staticTexts["Kitchen"].frame.width, 0, "the compact island says the room")
        app.swipeUp()
        keepScreenshot(app, "live-activity-vacuum-island-\(layout)")
    }

    // MARK: Accessibility audit

    func testStackPassesAccessibilityAudit() throws {
        let app = launch("stack")
        try FentonHomeApp.audit(app) { self.launch("stack", arguments: FentonHomeApp.ax5) }
    }

    func testProblemCardsPassAccessibilityAudit() throws {
        let app = launch("vacuums")
        try FentonHomeApp.audit(app) { self.launch("vacuums", arguments: FentonHomeApp.ax5) }
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
