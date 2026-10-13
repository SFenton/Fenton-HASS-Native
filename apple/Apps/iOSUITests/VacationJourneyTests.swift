import XCTest

/// Vacation and Solo Trip in the debug gallery (fixture house, no server): the chooser, enabling and
/// disabling Vacation Mode, scheduling and ending a Solo Trip, the restore choice, audits on every page and
/// screenshots, on iPhone, iPhone Duo and iPad.
@MainActor
final class VacationJourneyTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        if FentonHomeApp.family == .iPad, ProcessInfo.processInfo.environment["FENTON_UITEST_ORIENTATION"] == "landscape" {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated { if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait } }
    }

    /// A page of the feature, reached the way a person would.
    enum Page: String, CaseIterable {
        case chooser, vacationChecklist, vacationDates, confirmSheet, soloTripIdle, soloTripEditor, soloTripActive, soloTripRestore
    }

    // MARK: - Helpers

    private func launch(_ scenario: String = "idle", clean: Bool = false, arguments: [String] = []) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "vacation"
        app.launchEnvironment["FENTON_GALLERY_AWAY"] = scenario
        if clean { app.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1" }
        app.launchArguments += arguments
        app.launch()
        return app
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func lastCall(_ app: XCUIApplication) -> String { app.staticTexts["gallery.lastCall"].label }

    /// Waits until the last recorded call contains `text`.
    private func waitForCall(_ text: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let found = expectation(for: predicate, evaluatedWith: app.staticTexts["gallery.lastCall"])
        // Up to 10 s: turning Vacation Mode off sends seven calls one after another.
        if XCTWaiter().wait(for: [found], timeout: 10) != .completed {
            XCTFail("Expected a call containing \(text); last: \(lastCall(app))", file: file, line: line)
        }
    }

    /// Waits until `element`'s accessibility value is `value` (an empty string also matches no value).
    private func waitForValue(_ value: String, of element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if (element.value as? String ?? "") == value { return true }
            usleep(200_000)
        } while Date() < deadline
        return false
    }

    /// Scrolls the page until `target` can be tapped.
    @discardableResult
    private func reveal(_ target: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        // Toward the target, until it sits inside the content area: at AX5 a control can sit above the screen
        // after an earlier reveal, and a partly visible one is "hittable" while its center is under the
        // status bar (the tap then scrolls to the top instead).
        let window = app.windows.firstMatch.frame
        let content = CGRect(x: window.minX, y: window.minY + 90, width: window.width, height: window.height - 120)
        func inView() -> Bool {
            guard target.exists, target.isHittable else { return false }
            let frame = target.frame
            return frame.height > content.height ? content.contains(CGPoint(x: frame.midX, y: frame.midY))
                : content.contains(frame)
        }
        for _ in 0..<8 where !inView() {
            if target.exists, target.frame.midY < content.midY { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(target.isHittable, "\(target) never came into view")
        return target
    }

    private func tap(_ id: String, in app: XCUIApplication) {
        let target = element(id, in: app)
        // A List only exposes rows it has laid out: at AX5 on the folded iPhone Duo the second chooser row
        // starts below the screen.
        if !target.waitForExistence(timeout: 10) {
            for _ in 0..<6 where !target.exists { app.swipeUp() }
        }
        XCTAssertTrue(target.exists, "\(id) not found")
        reveal(target, in: app).tap()
    }

    private func assertTarget(_ id: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(id, in: app)
        XCTAssertTrue(target.waitForExistence(timeout: 10), "\(id) not found", file: file, line: line)
        XCTAssertGreaterThanOrEqual(target.frame.height, 43, "\(id) is shorter than 44 pt", file: file, line: line)
    }

    /// Launches and navigates to `page`.
    @discardableResult
    private func open(_ page: Page, clean: Bool = false, arguments: [String] = []) -> XCUIApplication {
        switch page {
        case .chooser:
            let app = launch(clean: clean, arguments: arguments)
            XCTAssertTrue(element("vacation.chooser.vacationMode", in: app).waitForExistence(timeout: 15))
            return app
        case .vacationChecklist:
            let app = launch(clean: clean, arguments: arguments)
            tap("vacation.chooser.vacationMode", in: app)
            XCTAssertTrue(element("vacation.checklist.0", in: app).waitForExistence(timeout: 5))
            return app
        case .vacationDates:
            let app = launch("vacation", clean: clean, arguments: arguments)
            XCTAssertTrue(element("vacation.dates.startDate", in: app).waitForExistence(timeout: 15))
            return app
        case .confirmSheet:
            let app = launch("ready", clean: clean, arguments: arguments)
            tap("vacation.chooser.vacationMode", in: app)
            tap("vacation.modeCard", in: app)
            XCTAssertTrue(element("vacation.confirm.action", in: app).waitForExistence(timeout: 5))
            sleep(1) // Let the sheet finish presenting.
            return app
        case .soloTripIdle:
            let app = launch(clean: clean, arguments: arguments)
            tap("vacation.chooser.soloTrip", in: app)
            XCTAssertTrue(element("soloTrip.toggle", in: app).waitForExistence(timeout: 5))
            return app
        case .soloTripEditor:
            let app = open(.soloTripIdle, clean: clean, arguments: arguments)
            tap("soloTrip.traveler.stephen", in: app)
            tap("soloTrip.toggle", in: app)
            XCTAssertTrue(element("soloTrip.editor.confirm", in: app).waitForExistence(timeout: 5))
            sleep(1)
            return app
        case .soloTripActive:
            let app = launch("solo-active", clean: clean, arguments: arguments)
            XCTAssertTrue(element("soloTrip.toggle", in: app).waitForExistence(timeout: 15))
            return app
        case .soloTripRestore:
            let app = launch("solo-restore", clean: clean, arguments: arguments)
            XCTAssertTrue(element("soloTrip.status.keepCurrent", in: app).waitForExistence(timeout: 15))
            return app
        }
    }

    // MARK: - Journeys

    /// The chooser offers both modes as 44 pt rows and each opens its page.
    func testChooserOpensBothPages() {
        let app = open(.chooser)
        assertTarget("vacation.chooser.vacationMode", in: app)
        assertTarget("vacation.chooser.soloTrip", in: app)
        XCTAssertTrue(app.staticTexts["One traveler, one home resident"].exists)
        tap("vacation.chooser.vacationMode", in: app)
        XCTAssertTrue(element("vacation.modeCard", in: app).waitForExistence(timeout: 5))
        // The folded iPhone Duo moves the back button from the bar to its rail.
        app.buttons["BackButton"].firstMatch.tap()
        tap("vacation.chooser.soloTrip", in: app)
        XCTAssertTrue(element("soloTrip.toggle", in: app).waitForExistence(timeout: 5))
    }

    /// An unfinished checklist blocks enabling; finishing it and confirming the dates turns Vacation Mode on.
    func testChecklistThenConfirmEnablesVacation() {
        let app = open(.vacationChecklist)
        let card = element("vacation.modeCard", in: app)
        XCTAssertEqual(card.value as? String, "Off")
        card.tap()
        XCTAssertTrue(app.staticTexts["Error: All pre-vacation tasks must be checked off before Vacation Mode can be enabled."].waitForExistence(timeout: 3)
            || app.descendants(matching: .any)["Error: All pre-vacation tasks must be checked off before Vacation Mode can be enabled."].exists)
        for index in 2..<5 {
            let row = element("vacation.checklist.\(index)", in: app)
            assertTarget("vacation.checklist.\(index)", in: app)
            XCTAssertEqual(row.value as? String, "Not checked")
            reveal(row, in: app).tap()
            XCTAssertEqual(row.value as? String, "Checked")
            waitForCall("input_boolean.turn_on", in: app)
        }
        app.swipeDown()
        tap("vacation.modeCard", in: app)
        XCTAssertTrue(element("vacation.confirm.action", in: app).waitForExistence(timeout: 5))
        tap("vacation.confirm.action", in: app)
        waitForCall("input_boolean.turn_on entity_id=input_boolean.vacation_mode", in: app)
        XCTAssertTrue(element("vacation.dates.startDate", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(element("vacation.modeCard", in: app).value as? String, "On")
    }

    /// Cancelling the confirmation leaves Vacation Mode off.
    func testCancellingTheConfirmationKeepsItOff() {
        let app = open(.confirmSheet)
        tap("vacation.confirm.cancel", in: app)
        XCTAssertTrue(element("vacation.modeCard", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(element("vacation.modeCard", in: app).value as? String, "Off")
        XCTAssertEqual(lastCall(app), "Last call: None")
    }

    /// Turning Vacation Mode off resets the checklist and shows it again.
    func testDisablingVacationResetsTheChecklist() {
        let app = open(.vacationDates)
        let card = element("vacation.modeCard", in: app)
        XCTAssertEqual(card.value as? String, "On")
        card.tap()
        waitForCall("vacation_checklist_trash_and_recycles_taken_out", in: app)
        XCTAssertTrue(element("vacation.checklist.0", in: app).waitForExistence(timeout: 5))
    }

    /// Scheduling a trip for Stephen starts it; turning the toggle off ends it.
    func testScheduleAndEndASoloTrip() {
        let app = open(.soloTripIdle)
        let toggle = element("soloTrip.toggle", in: app)
        XCTAssertFalse(toggle.isEnabled, "The toggle needs a traveler first")
        let stephen = element("soloTrip.traveler.stephen", in: app)
        stephen.tap()
        XCTAssertTrue(stephen.isSelected)
        XCTAssertTrue(toggle.isEnabled)
        toggle.tap()
        tap("soloTrip.editor.confirm", in: app)
        waitForCall("operation=schedule", in: app)
        XCTAssertTrue(lastCall(app).contains("traveler=stephen"))
        XCTAssertTrue(element("soloTrip.editor.confirm", in: app).waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitForValue("On", of: toggle), "Solo Trip never turned on")
        XCTAssertEqual(stephen.value as? String, "Away")
        XCTAssertEqual(element("soloTrip.traveler.steph", in: app).value as? String, "Home")
        XCTAssertTrue(element("soloTrip.return.date", in: app).exists)
        toggle.tap()
        waitForCall("operation=end_now", in: app)
        XCTAssertTrue(waitForValue("", of: stephen), "Stephen still shows \(stephen.value ?? "nil")")
    }

    /// An active trip skips the chooser and can be ended from there; a trip needing attention offers the restore choice.
    func testEngagedTripsOpenDirectly() {
        let active = open(.soloTripActive)
        XCTAssertTrue(element("soloTrip.notice", in: active).exists)
        active.terminate()
        let restore = open(.soloTripRestore)
        assertTarget("soloTrip.status.keepCurrent", in: restore)
        assertTarget("soloTrip.status.restoreSaved", in: restore)
        tap("soloTrip.status.keepCurrent", in: restore)
        waitForCall("resolve_action=keep_current", in: restore)
    }

    /// Signed in to the real server, Settings → Vacation opens whichever page the house's state calls for.
    /// Read-only: nothing is tapped on the page, so the house is never changed.
    func testSettingsOpensVacationOnTheLiveServer() throws {
        let app = try FentonHomeApp.launchSignedIn()
        // Regular width (iPad, unfolded Duo) reaches Settings through the navigation flyout, else the tab.
        let open = app.buttons["nav.open"]
        if open.waitForExistence(timeout: 5) {
            open.tap()
            let row = app.buttons["nav.settings"]
            XCTAssertTrue(row.waitForExistence(timeout: 5), "Flyout Settings row not found")
            row.tap()
        } else {
            let tab = app.tabBars.buttons["Settings"].exists
                ? app.tabBars.buttons["Settings"]
                : app.buttons.matching(NSPredicate(format: "label == 'Settings' AND (identifier == 'gearshape' OR identifier == '')")).firstMatch
            XCTAssertTrue(tab.waitForExistence(timeout: 15), "Settings tab not found")
            tab.tap()
        }
        assertTarget("settings.vacation", in: app)
        element("settings.vacation", in: app).tap()
        let landed = ["vacation.chooser.vacationMode", "vacation.modeCard", "soloTrip.toggle"].map { element($0, in: app) }
        let deadline = Date().addingTimeInterval(10)
        while !landed.contains(where: \.exists), Date() < deadline { usleep(200_000) }
        XCTAssertTrue(landed.contains(where: \.exists), "Vacation did not open")
    }

    // MARK: - Audits

    /// Audits `page` without the gallery's debug line, which is not product UI (behind an iPad form sheet it
    /// is dimmed by the modal).
    private func audit(_ page: Page) throws {
        let app = open(page, clean: true)
        let presenter: XCUIElement? = switch page {
        case .confirmSheet: element("vacation.modeCard", in: app)
        case .soloTripEditor: element("soloTrip.toggle", in: app)
        default: nil
        }
        try FentonHomeApp.audit(app, ax5Page: { self.open(page, clean: true, arguments: FentonHomeApp.ax5) }, presenter: presenter)
    }

    func testChooserPassesAudit() throws { try audit(.chooser) }
    func testChecklistPassesAudit() throws { try audit(.vacationChecklist) }
    func testDatesPassAudit() throws { try audit(.vacationDates) }
    func testConfirmSheetPassesAudit() throws { try audit(.confirmSheet) }
    func testSoloTripPassesAudit() throws { try audit(.soloTripIdle) }
    func testSoloTripEditorPassesAudit() throws { try audit(.soloTripEditor) }
    func testActiveSoloTripPassesAudit() throws { try audit(.soloTripActive) }
    func testRestoreChoicePassesAudit() throws { try audit(.soloTripRestore) }

    /// At AX5 every page's main action can still be reached.
    func testLargestTextKeepsActionsReachable() {
        let checks: [(Page, String)] = [
            (.vacationChecklist, "vacation.checklist.4"), (.confirmSheet, "vacation.confirm.action"),
            (.soloTripIdle, "soloTrip.traveler.steph"), (.soloTripEditor, "soloTrip.editor.confirm"),
        ]
        for (page, id) in checks {
            // Clean: at AX5 the debug last-call bar grows over the bottom of the page and takes the taps.
            let app = open(page, clean: true, arguments: FentonHomeApp.ax5)
            reveal(element(id, in: app), in: app)
            app.terminate()
        }
    }

    // MARK: - Screenshots

    /// Every page and sheet in the current pose (iPad: both orientations), named `vacation-<page>-<orientation>`.
    func testCapturePages() {
        let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]
        for orientation in orientations {
            if orientation != .unknown { XCUIDevice.shared.orientation = orientation }
            let suffix = orientation == .landscapeLeft ? "landscape" : orientation == .portrait ? "portrait" : "current"
            for page in Page.allCases {
                let app = open(page, clean: true)
                sleep(1)
                keep("vacation-\(page.rawValue)-\(suffix)")
                app.terminate()
            }
        }
    }

    private func keep(_ name: String) {
        // Upright: the raw capture stays portrait in landscape (see RenderedContrast).
        let shot = XCUIScreen.main.screenshot().image
        let format = UIGraphicsImageRendererFormat()
        format.scale = shot.scale
        let upright = UIGraphicsImageRenderer(size: shot.size, format: format).image { _ in shot.draw(at: .zero) }
        let attachment = XCTAttachment(image: upright)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        // The host captures the lit panel of an unfolded iPhone Duo (`<name>.ready` asks, `<name>.done` answers).
        guard let folder = ProcessInfo.processInfo.environment["FENTON_CAPTURE_DIR"], !folder.isEmpty else { return }
        let ready = URL(fileURLWithPath: folder).appendingPathComponent("\(name).ready")
        let done = URL(fileURLWithPath: folder).appendingPathComponent("\(name).done")
        FileManager.default.createFile(atPath: ready.path, contents: nil)
        let deadline = Date().addingTimeInterval(30)
        while !FileManager.default.fileExists(atPath: done.path), Date() < deadline { usleep(200_000) }
    }
}
