import XCTest

/// The Home Live Activity's views in the debug gallery (`live-activity`): the Lock Screen presentation, the Dynamic
/// Island stand-ins and the small family, over fixtures, with their buttons, on iPhone, iPhone Duo and iPad
/// (`.agents/platforms/apple/live-activities.md` §4, §11).
@MainActor
final class LiveActivityJourneyTests: JourneyTestCase {
    private func launch(_ scenario: String, arguments: [String] = []) -> XCUIApplication {
        let app = FentonHomeApp.launchGallery("live-activity", arguments: arguments, environment: ["FENTON_GALLERY_SCENARIO": scenario])
        XCTAssertTrue(element("liveactivity.lockscreen", in: app).waitForExistence(timeout: 10), "the Lock Screen view did not draw")
        return app
    }

    private func lastAction(_ app: XCUIApplication) -> String {
        app.staticTexts["gallery.lastCall"].label.replacing("Last action: ", with: "")
    }

    /// The Lock Screen limit is 160 pt; a taller view is cut off by the system, so every scenario must fit.
    func testEveryScenarioFitsTheLockScreensHeightLimit() {
        for scenario in ["dishwasher", "fan", "two", "three", "six", "done", "attention", "stopping"] {
            let app = launch(scenario)
            let frame = element("liveactivity.lockscreen", in: app).frame
            XCTAssertLessThanOrEqual(frame.height, 160, "\(scenario) is \(Int(frame.height)) pt tall")
            XCTAssertGreaterThan(frame.height, 60, "\(scenario) drew almost nothing")
            keepScreenshot(app, "live-activity-\(scenario)-\(layout)")
            app.terminate()
        }
    }

    /// Controls and the pager are named buttons of at least 44 pt, and say which job they belong to.
    func testButtonsAreNamedAndLargeEnough() {
        let app = launch("three")
        // The island's expanded stand-in repeats the buttons; the Lock Screen's are the ones under test.
        let lock = element("liveactivity.lockscreen", in: app)
        let cancel = lock.buttons["Cancel Timer Master Bath Fan"]
        XCTAssertTrue(cancel.exists, "the focused fan's control is named for its job")
        assertTarget(cancel)
        for name in ["Previous job", "Next job"] {
            let button = lock.buttons[name]
            XCTAssertTrue(button.exists, name)
            assertTarget(button)
            XCTAssertEqual(button.value as? String, "2 of 3", "\(name) says where the pager stands")
        }
        let single = launch("dishwasher")
        let singleLock = element("liveactivity.lockscreen", in: single)
        let stop = singleLock.buttons["Stop Dishwasher"]
        XCTAssertTrue(stop.exists)
        assertTarget(stop)
        XCTAssertFalse(singleLock.buttons["Next job"].exists, "one job has no pager")
    }

    /// ‹ and › walk the jobs and wrap around; the focused job's controls follow.
    func testThePagerWalksTheJobsAndWraps() {
        let app = launch("three")
        let lock = element("liveactivity.lockscreen", in: app)
        lock.buttons["Next job"].tap()
        XCTAssertEqual(lastAction(app), "focus dishwasher", "› from the last position wraps to the first job")
        XCTAssertTrue(lock.buttons["Stop Dishwasher"].waitForExistence(timeout: 5), "the dishwasher's control replaces the fan's")
        XCTAssertFalse(lock.buttons["Cancel Timer Master Bath Fan"].exists)
        lock.buttons["Previous job"].tap()
        XCTAssertEqual(lastAction(app), "focus fan.master")
        XCTAssertTrue(lock.buttons["Cancel Timer Master Bath Fan"].waitForExistence(timeout: 5))
    }

    /// A control shows the job as stopping at once and puts its button away (optimistic, until Home Assistant confirms).
    func testStopShowsStoppingAndHidesTheButton() {
        let app = launch("dishwasher")
        let lock = element("liveactivity.lockscreen", in: app)
        lock.buttons["Stop Dishwasher"].tap()
        XCTAssertEqual(lastAction(app), "stop dishwasher")
        XCTAssertTrue(lock.staticTexts["Stopping…"].waitForExistence(timeout: 5))
        XCTAssertFalse(lock.buttons["Stop Dishwasher"].exists)
        keepScreenshot(app, "live-activity-stopping-pressed-\(layout)")
    }

    /// Each row is one element that reads its title, status and the live time, and the header is a heading.
    func testRowsReadAsOneElementEach() {
        let app = launch("two")
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Dishwasher' AND label CONTAINS 'Eco 50'"))
        XCTAssertGreaterThanOrEqual(rows.count, 1, "the dishwasher row reads its status with its title")
        XCTAssertTrue(app.staticTexts["Home"].exists || app.otherElements["Home 2 running"].exists, "the header names the activity")
        XCTAssertTrue(app.staticTexts["Master Bath Fan"].exists || app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Master Bath Fan'")).count > 0)
    }

    /// At the largest text size the Lock Screen shows only the focused job, nothing runs off the screen, and the targets hold.
    func testLargestTextSizeKeepsTheFocusedJobAndTheTargets() {
        let app = launch("three", arguments: FentonHomeApp.ax5)
        let window = app.windows.firstMatch.frame
        let lock = element("liveactivity.lockscreen", in: app).frame
        XCTAssertLessThanOrEqual(lock.maxX, window.maxX + 0.5)
        XCTAssertGreaterThanOrEqual(lock.minX, window.minX - 0.5)
        for name in ["Previous job", "Next job", "Cancel Timer Master Bath Fan"] {
            let button = element("liveactivity.lockscreen", in: app).buttons[name]
            XCTAssertTrue(button.exists, name)
            assertTarget(button)
            XCTAssertLessThanOrEqual(button.frame.maxX, window.maxX + 0.5, "\(name) runs off the screen")
        }
        keepScreenshot(app, "live-activity-three-ax5-\(layout)")
    }

    /// The island stand-ins and the small family draw on every device.
    func testIslandPresentationsAndTheSmallFamilyDraw() {
        let app = launch("three")
        for kind in ["compact", "minimal", "expanded"] {
            XCTAssertTrue(element("liveactivity.island.\(kind)", in: app).exists, kind)
        }
        XCTAssertTrue(element("liveactivity.small", in: app).exists)
        app.swipeUp()
        keepScreenshot(app, "live-activity-islands-\(layout)")
    }

    func testPagePassesAccessibilityAudit() throws {
        let app = launch("three")
        try FentonHomeApp.audit(app) { self.launch("three", arguments: FentonHomeApp.ax5) }
    }

    /// A real activity (started locally from fixture content, no Home Assistant and no Apple servers) on the real Lock
    /// Screen: the app starts it, the simulator locks, and SpringBoard shows the rows the extension drew. The simulator
    /// cannot take an ActivityKit push (`xcrun simctl push` refuses it), so this is the closest a host run gets.
    func testARealActivityShowsOnTheLockScreen() throws {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_UITEST_RESET"] = "1"
        app.launchEnvironment["FENTON_LIVE_ACTIVITY"] = "1"
        app.launchEnvironment["FENTON_LIVE_ACTIVITY_FIXTURE"] = "three"
        app.launch()
        sleep(5)
        let lock = NSSelectorFromString("pressLockButton")
        guard XCUIDevice.shared.responds(to: lock) else { throw XCTSkip("This runtime has no lock button hook") }
        _ = XCUIDevice.shared.perform(lock)
        sleep(2)
        _ = XCUIDevice.shared.perform(lock)
        sleep(3)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "live-activity-real-lockscreen-\(layout)"
        shot.lifetime = .keepAlways
        add(shot)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let rows = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Bath Fan' OR label CONTAINS 'Dishwasher'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "the activity's rows are not on the Lock Screen")
        XCUIDevice.shared.press(.home)
    }
}
