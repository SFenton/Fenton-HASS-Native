import XCTest

/// The shell after the 2026-10-16 owner decisions (`.agents/design/direction-g.md`, Navigation): Settings is the last
/// tab; Quick Links and Profile are header buttons on every page; the Profile sheet is the web's Your Summary; and the
/// page title shares the header row with them where there is no hamburger (`toolbarTitleDisplayMode(.inlineLarge)`).
/// Runs on iPhone, the folded iPhone Duo and iPad (portrait; `FENTON_UITEST_ORIENTATION=landscape` for iPad landscape).
@MainActor
final class ShellJourneyTests: JourneyTestCase {
    // MARK: - Helpers

    /// Saves a screenshot to `FENTON_SHOTS_DIR` (never the repository) and attaches it for the result bundle.
    private func shoot(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(layout)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let folder = ProcessInfo.processInfo.environment["FENTON_SHOTS_DIR"], !folder.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(layout)-\(name).png"))
    }

    /// The window is regular width (iPad, unfolded Duo): the flyout replaces the tab bar and the title stays below the bar.
    private func isRegular(_ app: XCUIApplication) -> Bool { app.windows.firstMatch.frame.width >= 600 }

    private let sections = [("home", "Home"), ("security", "Security"), ("climate", "Climate"), ("chores", "Chores"), ("settings", "Settings")]

    /// Both header buttons: present, named, 44 pt targets, side by side and not overlapping.
    private func assertHeaderButtons(_ app: XCUIApplication, on page: String, file: StaticString = #filePath, line: UInt = #line) {
        let profile = app.buttons["nav.profile"]
        let links = app.buttons["quickLinks.open"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10), "\(page) has no Profile button", file: file, line: line)
        XCTAssertTrue(links.exists, "\(page) has no Quick Links button", file: file, line: line)
        XCTAssertEqual(profile.label, "Profile", file: file, line: line)
        XCTAssertEqual(links.label, "Quick Links", file: file, line: line)
        // XCUITest reports a glass bar item's frame several points inside the 44 pt circle (Quick Links' system glass: 29 x 36
        // measured 2026-10-18; Profile's disc 44 wide and 38 tall); the 44 pt hit area is proven by tapping the circle's edge in
        // ``testHeaderCirclesHaveA44PointHitArea``, and the sizes by pixels in `HeaderButtonsJourneyTests`.
        // The Duo's vertical rail reports Quick Links 27.3 wide (a system rail item).
        let smallest: CGFloat = FentonHomeApp.family == .iPhoneDuo ? 24 : 28
        for button in [profile, links] {
            XCTAssertGreaterThanOrEqual(min(button.frame.width, button.frame.height), smallest, button.label, file: file, line: line)
        }
        XCTAssertFalse(links.frame.intersects(profile.frame.insetBy(dx: 2, dy: 2)), "\(page): the buttons overlap", file: file, line: line)
        // The folded Duo moves bar items into its vertical rail, which takes Quick Links out of the top row (system
        // behaviour); every other window keeps the two circles side by side.
        if FentonHomeApp.family != .iPhoneDuo || abs(links.frame.midY - profile.frame.midY) < 8 {
            XCTAssertLessThan(links.frame.maxX, profile.frame.minX + 1, "\(page): Quick Links is not beside Profile", file: file, line: line)
            XCTAssertLessThan(abs(links.frame.midY - profile.frame.midY), 8, "\(page): the buttons are on different rows", file: file, line: line)
        }
    }

    /// Back one page: the system Back button wherever the bar puts it (the folded Duo moves it to its rail), else the
    /// leading-edge back swipe.
    private func goBack(in app: XCUIApplication) {
        let back = app.buttons["BackButton"]
        if back.exists, back.isHittable {
            back.tap()
            return
        }
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: window.frame.height / 2))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: window.frame.width * 0.7, dy: 0)))
    }

    private func openMasterBedroom(in app: XCUIApplication) {
        app.buttons["quickLinks.open"].tap()
        let rooms = element("quickLinks.rooms", in: app)
        XCTAssertTrue(rooms.waitForExistence(timeout: 10), "Quick Links did not open")
        rooms.tap()
        let tile = element("rooms.master-bedroom", in: app)
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "No Master Bedroom tile")
        tile.tap()
        XCTAssertTrue(element("room.scroll.master-bedroom", in: app).waitForExistence(timeout: 15), "Master Bedroom did not open")
    }

    /// The page title in the header: the static text with its label in the top of the window (a section header or a tab
    /// label of the same name sits lower).
    private func barTitle(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        let top = app.staticTexts.matching(NSPredicate(format: "label == %@", title)).allElementsBoundByIndex
            .first { $0.frame.minY < 150 && $0.frame.minY > 0 }
        return top ?? app.staticTexts["shell.noTitle"]
    }

    // MARK: - Settings tab (decision 1)

    /// Settings is the last tab (or flyout row) and its topics push inside the tab with Back; the Account sheet has no
    /// Settings row any more.
    func testSettingsIsTheLastTabAndTopicsPush() throws {
        let app = try FentonHomeApp.launchSignedIn()
        app.openAccountSettings()
        XCTAssertTrue(element("settings.list", in: app).waitForExistence(timeout: 5), "No Settings list")
        XCTAssertTrue(app.buttons["settings.homeAssistant"].exists || app.descendants(matching: .any)["settings.homeAssistant"].exists
                      || app.buttons["settings.topic.admin"].exists, "Settings rows missing")
        shoot(app, "settings-tab")
        let modes = app.buttons["settings.topic.specialDeviceModes"]
        for _ in 0..<6 where !(modes.exists && modes.isHittable) { app.settingsList.swipeUp() }
        modes.tap()
        XCTAssertTrue(app.navigationBars["Special Device Modes"].waitForExistence(timeout: 5), "The topic did not push")
        XCTAssertFalse(app.buttons["split.close"].exists, "The Settings tab split")
        // The header buttons ride along on the pushed topic.
        XCTAssertTrue(app.buttons["nav.profile"].exists && app.buttons["quickLinks.open"].exists, "No header buttons on a Settings topic")
        shoot(app, "settings-topic")
        goBack(in: app)
        XCTAssertTrue(modes.waitForExistence(timeout: 5), "Back did not return to the Settings list")
        // Settings is no longer in the Account sheet.
        app.openAccountSheet()
        XCTAssertFalse(app.buttons["account.settings"].exists, "The Account sheet still has a Settings row")
    }

    /// Home Assistant Settings, Vacation and Feedback still open from the Settings tab.
    func testSettingsTabKeepsTheOtherEntryPoints() throws {
        let app = try FentonHomeApp.launchSignedIn()
        app.openAccountSettings()
        let vacation = app.buttons["settings.vacation"]
        XCTAssertTrue(vacation.waitForExistence(timeout: 5), "No Vacation row")
        vacation.tap()
        XCTAssertTrue(app.buttons["nav.profile"].waitForExistence(timeout: 5), "No Profile on the Vacation page")
        goBack(in: app)
        let list = app.settingsList
        XCTAssertTrue(list.waitForExistence(timeout: 5), "Back did not return to the Settings list")
        let report = app.buttons["settings.feedback.bug"]
        for _ in 0..<12 where !(report.exists && report.isHittable) { list.swipeUp(velocity: .slow) }
        XCTAssertTrue(report.exists, "No Report an Issue row")
        let homeAssistant = app.buttons["settings.homeAssistant"]
        XCTAssertTrue(homeAssistant.exists, "No Home Assistant Settings row")
    }

    // MARK: - Header buttons (decision 2)

    /// Profile and Quick Links are on every tab root, in every window, with names and 44 pt targets.
    func testHeaderButtonsOnEveryTabRoot() throws {
        let app = try FentonHomeApp.launchSignedIn()
        for (section, title) in sections {
            if section != "home" { openSection(section, title: title, in: app) }
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10), "\(title) did not appear")
            sleep(1)
            assertHeaderButtons(app, on: title)
            shoot(app, "root-\(section)")
        }
        XCTAssertFalse(app.buttons["nav.quickLinks"].exists, "Quick Links is still a flyout row")
    }

    /// Each button is a 44 pt target: a tap 19 pt left of its centre (outside the 29 to 38 pt frame XCUITest reports, inside
    /// the 22 pt radius) still opens its sheet. Profile's frame includes its badge, so its centre is where the frame's
    /// centre is, not the disc's, and 19 pt left still lands on the disc.
    func testHeaderCirclesHaveA44PointHitArea() throws {
        let app = try FentonHomeApp.launchSignedIn()
        for (id, sheetClose) in [("quickLinks.open", "quickLinks.close"), ("nav.profile", "account.close")] {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10), id)
            let centre = button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            centre.withOffset(CGVector(dx: -19, dy: 0)).tap()
            XCTAssertTrue(app.buttons[sheetClose].waitForExistence(timeout: 5), "\(id) ignored a tap 19 pt from its centre")
            app.buttons[sheetClose].tap()
            XCTAssertTrue(app.buttons[sheetClose].waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.buttons["home.chip.lights"].waitForExistence(timeout: 10))
        }
    }

    /// A pushed page (Master Bedroom, which had no Profile) carries both buttons; each opens its sheet from there.
    func testHeaderButtonsOnAPushedRoomPage() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openMasterBedroom(in: app)
        sleep(1)
        assertHeaderButtons(app, on: "Master Bedroom")
        shoot(app, "room-page")
        app.buttons["nav.profile"].tap()
        XCTAssertTrue(app.buttons["account.close"].waitForExistence(timeout: 5), "Profile did not open from a pushed page")
        app.buttons["account.close"].tap()
        XCTAssertTrue(app.buttons["quickLinks.open"].waitForExistence(timeout: 5))
        app.buttons["quickLinks.open"].tap()
        XCTAssertTrue(element("quickLinks.rooms", in: app).waitForExistence(timeout: 5), "Quick Links did not open from a pushed page")
        app.buttons["quickLinks.close"].tap()
        XCTAssertTrue(element("room.scroll.master-bedroom", in: app).waitForExistence(timeout: 5), "The room page was lost behind the sheet")
    }

    /// The Quick Links sheet pushes the page it picks on the stack under it, so Back returns to where it was opened.
    func testQuickLinksPushesItsPageOnTheCurrentStack() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openSection("climate", title: "Climate", in: app)
        app.buttons["quickLinks.open"].tap()
        let link = element("quickLinks.custom-lights", in: app)
        XCTAssertTrue(link.waitForExistence(timeout: 10), "No Custom Lights tile")
        link.tap()
        XCTAssertTrue(app.navigationBars["Custom Lights"].waitForExistence(timeout: 10), "Custom Lights did not push")
        XCTAssertFalse(element("quickLinks.rooms", in: app).exists, "The sheet stayed open")
        assertHeaderButtons(app, on: "Custom Lights")
        goBack(in: app)
        XCTAssertTrue(app.navigationBars["Climate"].waitForExistence(timeout: 10), "Back did not return to Climate, where Quick Links was opened")
    }

    // MARK: - Profile modal (decision 3)

    /// The Profile button opens the web's Your Summary on the live house, read-only: it opens on the summary (a resident's
    /// Overdue Chores), carries the four tabs, and keeps the account (who is signed in, who is home, Sign Out) on Profile.
    func testSummarySheetOpensOnTheSummaryAndKeepsTheAccountOnProfile() throws {
        let app = try FentonHomeApp.launchSignedIn()
        app.openAccountSheet(tab: nil)
        XCTAssertTrue(app.buttons["summary.tabs.profile"].waitForExistence(timeout: 5) || app.buttons["summary.tabs"].exists,
                      "No tab bar in the Summary sheet")
        XCTAssertFalse(element("account.header", in: app).exists, "The sheet opened on Profile, not the summary")
        shoot(app, "summary-opening")
        app.selectSummaryTab(.profile)
        XCTAssertTrue(element("account.header", in: app).waitForExistence(timeout: 5), "No account header")
        XCTAssertFalse(app.buttons["account.settings"].exists, "Settings row in the Account sheet")
        shoot(app, "account-top")
        let signOut = app.buttons["account.signOut"]
        let list = element("account.list", in: app)
        for _ in 0..<10 where !(signOut.exists && signOut.isHittable) { list.swipeUp() }
        XCTAssertTrue(signOut.exists, "No Sign Out")
        assertTarget(signOut)
        shoot(app, "account-bottom")
    }

    // MARK: - Title in the header (decision 4)

    /// Without a hamburger the large title sits in the header row beside the buttons, then collapses to a centred inline
    /// title as the page scrolls and grows back at the top. With the hamburger (regular width) it stays below the bar.
    func testTitleSharesTheHeaderRowAndCollapsesOnScroll() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openSection("climate", title: "Climate", in: app)
        XCTAssertTrue(app.navigationBars["Climate"].waitForExistence(timeout: 10))
        sleep(2)
        let title = barTitle(app, "Climate")
        let profile = app.buttons["nav.profile"]
        XCTAssertTrue(title.exists, "No Climate title")
        if isRegular(app) {
            XCTAssertTrue(app.buttons["nav.open"].exists, "No menu button beside the title")
            shoot(app, "title-regular")
            return
        }
        XCTAssertEqual(app.buttons["nav.open"].exists, FentonHomeApp.family == .iPhone, "Hamburger only on iPhone")
        let large = title.frame
        XCTAssertLessThan(abs(large.midY - profile.frame.midY), 20, "The title is not in the buttons' row")
        XCTAssertGreaterThan(large.height, 30, "The title is not large at the top")
        XCTAssertLessThan(large.minX, 40, "The large title is not leading")
        shoot(app, "title-large")
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<3 { scroll.swipeUp() }
        sleep(1)
        let collapsed = barTitle(app, "Climate")
        // The folded Duo's vertical bar has no inline title, so the title simply goes once the page scrolls.
        if collapsed.exists {
            let inline = collapsed.frame
            XCTAssertLessThan(inline.height, large.height - 8, "The title did not shrink on scroll")
            XCTAssertLessThan(abs(inline.midY - profile.frame.midY), 20, "The inline title left the buttons' row")
            // With the hamburger (iPhone) the bar keeps the inline title leading beside it; without it the title centres.
            if app.buttons["nav.open"].exists {
                XCTAssertLessThan(inline.maxX, app.buttons["nav.open"].frame.minX, "The inline title runs under the buttons")
            } else {
                XCTAssertGreaterThan(inline.minX, large.minX + 40, "The inline title did not centre")
            }
        } else {
            XCTAssertEqual(FentonHomeApp.family, .iPhoneDuo, "The title vanished on scroll")
        }
        shoot(app, "title-inline")
        for _ in 0..<4 { scroll.swipeDown() }
        sleep(1)
        XCTAssertTrue(barTitle(app, "Climate").waitForExistence(timeout: 5), "The title did not come back at the top")
        XCTAssertGreaterThan(barTitle(app, "Climate").frame.height, 30, "The title did not grow back at the top")
    }

    /// A pushed page keeps the system's own title behaviour: Back leading, the title below or centred, and both header
    /// buttons trailing; the title never collides with them.
    func testPushedPageTitleClearsTheHeaderButtons() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openMasterBedroom(in: app)
        sleep(1)
        let title = barTitle(app, "Master Bedroom")
        XCTAssertTrue(title.exists, "No Master Bedroom title")
        let links = app.buttons["quickLinks.open"]
        if abs(title.frame.midY - links.frame.midY) < 20 {
            XCTAssertLessThan(title.frame.maxX, links.frame.minX, "The title runs under the header buttons")
        }
        shoot(app, "title-pushed")
    }
}
