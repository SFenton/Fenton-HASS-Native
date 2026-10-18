import XCTest

/// The Your Summary sheet (the header Profile button) on fixtures in the debug gallery: four tabs with badges, the Chores
/// page's rows with their edit button and swipe actions, the Food page's rows, the empty and Vacation Mode states, and
/// the accessibility rules (names, reading order, 44 pt targets, AX5). No house is touched: every change lands on the
/// gallery's fixture services. Spec: `.agents/pages/settings/profile.md`.
@MainActor
final class SummaryJourneyTests: JourneyTestCase {
    // MARK: Helpers

    private func launch(tab: SummaryTabID? = nil, viewer: String? = nil, vacation: Bool = false, empty: Bool = false,
                        arguments: [String] = [], appearance: String? = nil) -> XCUIApplication {
        var environment: [String: String] = ["FENTON_GALLERY_CLEAN": "0"]
        if let tab { environment["FENTON_GALLERY_TAB"] = tab.rawValue }
        if let viewer { environment["FENTON_GALLERY_VIEWER"] = viewer }
        if vacation { environment["FENTON_GALLERY_VACATION"] = "1" }
        if empty { environment["FENTON_GALLERY_EMPTY"] = "1" }
        let app = FentonHomeApp.launchGallery("profile", arguments: arguments, environment: environment, appearance: appearance)
        XCTAssertTrue(app.buttons["account.close"].waitForExistence(timeout: 15), "The Summary sheet did not open")
        return app
    }

    /// A tab's segment, or nil at accessibility sizes where the bar is a menu.
    private func segment(_ tab: SummaryTabID, in app: XCUIApplication) -> XCUIElement { app.buttons["summary.tabs.\(tab.rawValue)"] }

    private func screenshotName(_ name: String) -> String { "summary-\(name)-\(layout)" }

    /// Drags a row part of the way, which opens that edge's swipe actions without performing the full swipe.
    private func reveal(_ row: XCUIElement, from: CGFloat, to: CGFloat) {
        row.coordinate(withNormalizedOffset: CGVector(dx: from, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: to, dy: 0.5)))
    }

    // MARK: Tabs and badges

    /// The sheet opens on Overdue Chores; the tabs are named for VoiceOver with their counts, are 44 pt targets, and each
    /// shows its content.
    func testOpensOnOverdueAndEachTabShowsItsContent() {
        let app = launch()
        XCTAssertTrue(app.navigationBars["Your Summary"].waitForExistence(timeout: 5), "The title reads Your Summary for a resident")
        let overdue = segment(.overdue, in: app)
        XCTAssertTrue(overdue.waitForExistence(timeout: 5), "No Overdue Chores tab")
        XCTAssertEqual(overdue.label, "Overdue Chores, 2 items")
        XCTAssertEqual(segment(.expiredFood, in: app).label, "Expired Food, 3 items")
        XCTAssertEqual(segment(.upcoming, in: app).label, "Upcoming Chores", "Upcoming chores never badge")
        XCTAssertEqual(segment(.profile, in: app).label, "Profile")
        XCTAssertTrue(overdue.isSelected, "It opens on Overdue Chores")
        for tab in SummaryTabID.allCases { assertTarget(segment(tab, in: app)) }
        XCTAssertTrue(element("todo.item.11--fixture", in: app).waitForExistence(timeout: 5), "Overdue chores listed")
        XCTAssertTrue(app.staticTexts["Overdue Chores"].exists, "Its section header")
        keepScreenshot(app, screenshotName("overdue"))

        segment(.upcoming, in: app).tap()
        XCTAssertTrue(element("todo.item.13--fixture", in: app).waitForExistence(timeout: 5), "Chores due today")
        XCTAssertTrue(app.staticTexts["Upcoming Chores"].exists && app.staticTexts["No Due Date"].exists, "Two sections, each with its header")
        XCTAssertTrue(segment(.upcoming, in: app).isSelected)
        keepScreenshot(app, screenshotName("upcoming"))

        segment(.expiredFood, in: app).tap()
        XCTAssertTrue(element("inventory.row.Cereal", in: app).waitForExistence(timeout: 8), "Expired food listed")
        keepScreenshot(app, screenshotName("expired"))

        segment(.profile, in: app).tap()
        XCTAssertTrue(element("account.header", in: app).waitForExistence(timeout: 5), "The account header")
        XCTAssertTrue(app.staticTexts["People at Home"].exists)
        XCTAssertTrue(app.buttons["account.signOut"].exists)
        keepScreenshot(app, screenshotName("profile"))
    }

    /// Profile keeps the account's extras: who is signed in, who is home (a monogram per person, Home or Away), and Sign
    /// Out behind a confirmation that is cancelled here.
    func testProfileHoldsTheAccountPeopleAndSignOut() {
        let app = launch(tab: .profile)
        let header = element("account.header", in: app)
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertTrue(header.label.contains("Stephen Fenton"), header.label)
        XCTAssertTrue(app.staticTexts["People at Home"].exists)
        XCTAssertTrue(app.staticTexts["Stephen Fenton"].exists && app.staticTexts["Steph Fenton"].exists)
        XCTAssertTrue(app.staticTexts["Away"].exists && app.staticTexts["Home"].firstMatch.exists)
        let signOut = app.buttons["account.signOut"]
        let list = element("account.list", in: app)
        for _ in 0..<6 where !(signOut.exists && signOut.isHittable) { list.swipeUp() }
        XCTAssertTrue(signOut.exists)
        assertTarget(signOut)
        signOut.tap()
        XCTAssertTrue(app.alerts["Sign Out of Home Assistant?"].waitForExistence(timeout: 5), "Sign Out confirms first")
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertTrue(signOut.exists, "Cancelling keeps the sheet and the session")
    }

    // MARK: Chores

    /// The rows are the Chores page's own: a check, the due label, an edit button that opens the task form, and the
    /// swipe actions.
    func testChoreRowsCarryTheEditButtonAndSwipeActions() {
        let app = launch(tab: .overdue)
        let row = element("todo.item.11--fixture", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, "Take out the recycling")
        XCTAssertTrue((row.value as? String)?.hasPrefix("Not done, Due") == true || (row.value as? String)?.hasPrefix("Not done") == true,
                      "\(row.value ?? "")")
        let edit = app.buttons["todo.edit.11--fixture"]
        XCTAssertTrue(edit.exists)
        XCTAssertEqual(edit.label, "Edit Take out the recycling")
        assertTarget(edit)

        // Swipe from the leading edge: Complete. From the trailing edge: Delete and Edit.
        reveal(row, from: 0.15, to: 0.55)
        XCTAssertTrue(app.buttons["todo.swipe.complete.11--fixture"].waitForExistence(timeout: 3), "Complete swipes in from the leading edge")
        reveal(row, from: 0.55, to: 0.1)
        reveal(row, from: 0.85, to: 0.35)
        XCTAssertTrue(app.buttons["todo.swipe.edit.11--fixture"].waitForExistence(timeout: 3), "Edit swipes in from the trailing edge")
        XCTAssertTrue(app.buttons["todo.swipe.delete.11--fixture"].exists, "So does Delete")
        keepScreenshot(app, screenshotName("overdue-swipe"))

        edit.tap()
        let name = app.textFields["task.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8), "The edit button opens the Chores page's task form")
        XCTAssertEqual(name.value as? String, "Take out the recycling")
        app.buttons["task.cancel"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        XCTAssertTrue(row.exists, "The Summary is still under the form")
    }

    /// Checking a chore off hides it at once and calls the (fixture) service, as on the Chores page.
    func testCheckingAChoreOffHidesItAndRecordsTheCall() {
        let app = launch(tab: .overdue)
        let row = element("todo.item.12--fixture", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "A completed chore leaves the list")
        expectLastCall("todo.update_item 12--fixture", in: app)
        XCTAssertEqual(segment(.overdue, in: app).label, "Overdue Chores, 1 item", "The tab's badge follows, and is singular for one")
    }

    /// Deleting asks first, through the Chores page's dialog; cancelling leaves the chore.
    func testDeletingAChoreAsksFirst() {
        let app = launch(tab: .overdue)
        let row = element("todo.item.12--fixture", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        reveal(row, from: 0.85, to: 0.35)
        let delete = app.buttons["todo.swipe.delete.12--fixture"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
        let confirm = app.buttons["todo.delete.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Delete confirms first")
        XCTAssertEqual(confirm.label, "Delete Task")
        // The dialog's cancel is the sheet scrim on iPad and a Cancel button on iPhone.
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() } else { app.tap() }
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        XCTAssertTrue(row.exists, "Cancelling keeps the chore")
    }

    // MARK: Expired food

    /// The rows are the Food page's own, soonest expiry first: name, the red "Expired" line, the stock count above one,
    /// the add-to-Groceries cart and a chevron into the item editor.
    func testExpiredFoodRowsAreTheFoodPagesRows() {
        let app = launch(tab: .expiredFood)
        let cereal = element("inventory.row.Cereal", in: app)
        XCTAssertTrue(cereal.waitForExistence(timeout: 8))
        let rice = element("inventory.row.Jasmine Rice", in: app)
        let yogurt = element("inventory.row.Greek Yogurt", in: app)
        XCTAssertTrue(rice.exists && yogurt.exists)
        XCTAssertLessThan(cereal.frame.minY, rice.frame.minY, "The oldest expiry leads")
        XCTAssertLessThan(rice.frame.minY, yogurt.frame.minY)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Cereal, Quantity 2, Expired'")).firstMatch.exists,
                      "The stock count, then the expiry line")
        let cart = app.buttons["Add Cereal to shopping list"]
        let chevron = app.buttons["Edit Cereal"]
        XCTAssertTrue(cart.exists && chevron.exists)
        assertTarget(cart)
        assertTarget(chevron)
        keepScreenshot(app, screenshotName("expired-rows"))

        // The cart asks how many; cancelling adds nothing.
        cart.tap()
        XCTAssertTrue(app.alerts["Add Cereal to Groceries"].waitForExistence(timeout: 5), "The cart asks for a quantity")
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 3))

        // The chevron opens the Food page's item editor.
        chevron.tap()
        XCTAssertTrue(element("inventory.editor", in: app).waitForExistence(timeout: 8), "The chevron opens the item editor")
        keepScreenshot(app, screenshotName("expired-editor"))
    }

    // MARK: Empty and vacation

    func testEmptyTabsSayTheWebsWords() {
        let app = launch(tab: .overdue, empty: true)
        XCTAssertTrue(element("summary.empty.overdue", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Chores Due"].exists)
        XCTAssertTrue(app.staticTexts["You are all caught up on chores that slipped past their due date."].exists)
        XCTAssertEqual(segment(.overdue, in: app).label, "Overdue Chores", "No count when nothing is overdue")
        keepScreenshot(app, screenshotName("overdue-empty"))
        segment(.upcoming, in: app).tap()
        XCTAssertTrue(app.staticTexts["No Chores Upcoming"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["There is nothing else on your schedule for the rest of today."].exists)
        segment(.expiredFood, in: app).tap()
        XCTAssertTrue(app.staticTexts["No Expired Food"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Everything in the kitchen is still within date."].exists)
        keepScreenshot(app, screenshotName("expired-empty"))
    }

    func testVacationModeSaysEnjoyVacationAndHidesExpiredFood() {
        let app = launch(tab: .overdue, vacation: true, empty: true)
        XCTAssertTrue(app.staticTexts["Enjoy vacation!"].waitForExistence(timeout: 5), "An empty chore tab")
        segment(.upcoming, in: app).tap()
        XCTAssertTrue(app.staticTexts["Enjoy vacation!"].waitForExistence(timeout: 5))
        segment(.expiredFood, in: app).tap()
        XCTAssertTrue(app.staticTexts["No Expired Food"].waitForExistence(timeout: 5), "A confirmed zero stays 'No Expired Food'")
        XCTAssertTrue(app.staticTexts["Enjoy vacation!"].exists)
        keepScreenshot(app, screenshotName("expired-vacation-none"))

        let busy = launch(tab: .expiredFood, vacation: true)
        XCTAssertTrue(busy.staticTexts["Expired Food Hidden"].waitForExistence(timeout: 5), "Vacation hides a list that has items")
        XCTAssertTrue(busy.staticTexts["Enjoy vacation!"].exists)
        XCTAssertEqual(segment(.expiredFood, in: busy).label, "Expired Food", "Vacation puts the badge on hold")
        XCTAssertFalse(element("inventory.row.Cereal", in: busy).exists)
        keepScreenshot(busy, screenshotName("expired-vacation"))
    }

    /// Someone who is not a resident has no personal chores: the title reads Summary, with Profile and Expired Food.
    func testAGuestSeesSummaryWithProfileAndExpiredFoodOnly() {
        let app = launch(viewer: "guest")
        XCTAssertTrue(app.navigationBars["Summary"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Your Summary"].exists)
        XCTAssertTrue(segment(.profile, in: app).exists && segment(.expiredFood, in: app).exists)
        XCTAssertFalse(segment(.overdue, in: app).exists || segment(.upcoming, in: app).exists)
        XCTAssertTrue(element("inventory.row.Cereal", in: app).waitForExistence(timeout: 8), "It opens on Expired Food")
        keepScreenshot(app, screenshotName("guest"))
    }

    // MARK: Accessibility

    /// Reading order is title, then the tab's content, then the tab bar last; targets are 44 pt and every tab passes the
    /// accessibility audit.
    func testEachTabPassesTheAuditAndReadsInOrder() throws {
        for tab in SummaryTabID.allCases {
            let app = launch(tab: tab)
            let content: String = switch tab {
            case .profile: "account.header"
            case .overdue: "todo.item.11--fixture"
            case .upcoming: "todo.item.13--fixture"
            case .expiredFood: "inventory.row.Cereal"
            }
            XCTAssertTrue(element(content, in: app).waitForExistence(timeout: 8), "\(tab) content")
            sleep(1)
            let ordered = ["account.close", content, "summary.tabs"].map { element($0, in: app) }
            let top = ordered.map(\.frame.minY)
            XCTAssertLessThan(top[0], top[1], "\(tab): the close button leads the content")
            XCTAssertLessThan(top[1], top[2], "\(tab): the tab bar is last, along the bottom")
            keepScreenshot(app, screenshotName("audit-\(tab.rawValue)"))
            try FentonHomeApp.audit(app) { self.launch(tab: tab, arguments: FentonHomeApp.ax5) }
        }
    }

    /// At accessibility text sizes the bar is a menu that names the selected section and lists every tab with its count.
    func testAtAX5TheTabBarIsAMenuWithCounts() {
        let app = launch(tab: .overdue, arguments: FentonHomeApp.ax5)
        let menu = app.buttons["summary.tabs"]
        XCTAssertTrue(menu.waitForExistence(timeout: 8), "At AX5 the bar is a menu")
        XCTAssertGreaterThanOrEqual(menu.frame.height, 43)
        keepScreenshot(app, screenshotName("ax5-overdue"))
        menu.tap()
        let items = ["Profile", "Overdue Chores, 2 items", "Upcoming Chores", "Expired Food, 3 items"]
        for item in items {
            XCTAssertTrue(app.buttons[item].waitForExistence(timeout: 5), "No '\(item)' in the menu")
        }
        keepScreenshot(app, screenshotName("ax5-menu"))
        app.buttons["Upcoming Chores"].tap()
        XCTAssertTrue(element("todo.item.13--fixture", in: app).waitForExistence(timeout: 8), "Choosing a tab shows it")
    }

    /// Rows and the bar read in a light sheet too (the sheet follows the system appearance; the row cards are the sheet's cell).
    func testTheChoreAndFoodRowsReadInALightSheet() throws {
        for tab in [SummaryTabID.overdue, .expiredFood] {
            let app = launch(tab: tab, appearance: "light")
            XCTAssertTrue(element(tab == .overdue ? "todo.item.11--fixture" : "inventory.row.Cereal", in: app).waitForExistence(timeout: 8))
            sleep(1)
            keepScreenshot(app, screenshotName("light-\(tab.rawValue)"))
            try FentonHomeApp.audit(app)
        }
    }
}
