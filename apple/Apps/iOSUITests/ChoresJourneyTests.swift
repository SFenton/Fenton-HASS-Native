import XCTest

/// Chores tab, its sub-pages, the admin To-Do and every todo sheet on fixture lists in the debug gallery
/// (no house changes), plus a read-only signed-in pass of the real Chores tab. Spec: `.agents/pages/chores/spec.md`.
@MainActor
final class ChoresJourneyTests: JourneyTestCase {
    // MARK: Helpers

    private func launch(page: String? = nil, empty: Bool = false, arguments: [String] = []) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "chores"
        if let page { app.launchEnvironment["FENTON_GALLERY_TODO_PAGE"] = page }
        if empty { app.launchEnvironment["FENTON_GALLERY_EMPTY"] = "1" }
        app.launchArguments += arguments
        app.launch()
        XCTAssertTrue(app.buttons["fab.add"].waitForExistence(timeout: 10), "Add button missing")
        return app
    }

    /// Scrolls the page until `element` is hittable and clear of the floating Add bar and the gallery's
    /// last-call line (XCUITest calls an element under them hittable, but the tap lands on the overlay).
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        func clear() -> Bool {
            guard element.exists, element.isHittable else { return false }
            let overlays = [app.buttons["fab.add"], app.staticTexts["gallery.lastCall"]].filter(\.exists)
            let top = overlays.map(\.frame.minY).min() ?? .greatestFiniteMagnitude
            return element.frame.maxY <= top
        }
        for _ in 0..<8 where !clear() {
            // A short drag, not a fling, so the row stops where it lands and the next tap isn't eaten
            // by deceleration.
            let scroll = app.scrollViews.firstMatch
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.4)))
        }
        XCTAssertTrue(clear(), "\(element) never came into view")
        return element
    }

    private func screenshotName(_ name: String) -> String {
        let orientation = ProcessInfo.processInfo.environment["FENTON_UITEST_ORIENTATION"] ?? "portrait"
        return "\(name)-\(FentonHomeApp.family)-\(orientation)"
    }

    // MARK: Chores tab

    /// Quick links are named buttons with their counts; the viewer's own link reads "Your Chores".
    func testQuickLinksShowCountsAndNavigate() {
        let app = launch()
        let mine = element("chores.link.stephens-chores", in: app)
        XCTAssertTrue(mine.waitForExistence(timeout: 5))
        XCTAssertEqual(mine.label, "Your Chores")
        XCTAssertEqual(mine.value as? String, "2 overdue tasks · 1 task listed")
        XCTAssertEqual(element("chores.link.groceries", in: app).value as? String, "3 items")
        XCTAssertEqual(element("chores.link.stephs-chores", in: app).label, "Steph's Chores")
        XCTAssertGreaterThanOrEqual(mine.frame.height, 43)
        mine.tap()
        XCTAssertTrue(element("todo.page.stephens-chores", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Stephen's Chores"].exists)
    }

    /// Checking a chore off hides it at once and calls Home Assistant.
    func testCheckingOffAChoreHidesIt() {
        let app = launch()
        let row = element("todo.item.13--fixture", in: app)
        reveal(row, in: app)
        XCTAssertEqual(row.label, "Run the dishwasher")
        XCTAssertTrue((row.value as? String)?.hasPrefix("Not done, Due in") == true)
        row.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "Completed chore still shown")
        XCTAssertEqual(lastCall(in: app), "todo.update_item 13--fixture")
    }

    /// The pencil opens the task form, loads the task, and saving sends the form.
    func testEditingATaskLoadsAndSaves() {
        let app = launch()
        let edit = element("todo.edit.13--fixture", in: app)
        reveal(edit, in: app)
        XCTAssertEqual(edit.label, "Edit Run the dishwasher")
        edit.tap()
        let name = app.textFields["task.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Run the dishwasher")
        app.buttons["task.save"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        XCTAssertEqual(lastCall(in: app), "donetick.update_task_form")
    }

    /// Add Task opens an empty form whose Create stays off until the task has a name.
    func testCreatingATask() {
        let app = launch()
        app.buttons["fab.add"].tap()
        let create = app.buttons["task.save"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertFalse(create.isEnabled)
        app.textFields["task.name"].tap()
        app.textFields["task.name"].typeText("Clean the oven")
        XCTAssertTrue(create.isEnabled)
        create.tap()
        // On iPad the first tap can only end editing in the focused field; tap again if the sheet stayed.
        if !create.waitForNonExistence(timeout: 2), create.exists, create.isHittable { create.tap() }
        XCTAssertTrue(create.waitForNonExistence(timeout: 5))
        XCTAssertEqual(lastCall(in: app), "donetick.create_task_form")
    }

    // MARK: Sub-pages

    func testGroceriesAddAndCheckOff() {
        let app = launch(page: "groceries")
        XCTAssertEqual(app.buttons["fab.add"].label, "Add Groceries")
        app.buttons["fab.add"].tap()
        let field = app.textFields["grocery.item"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Eggs")
        app.buttons["grocery.add"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        let eggs = app.buttons.matching(NSPredicate(format: "label == 'Eggs'")).firstMatch
        XCTAssertTrue(eggs.waitForExistence(timeout: 5), "New grocery not listed")
        element("todo.item.g1", in: app).tap()
        XCTAssertTrue(element("todo.item.g1", in: app).waitForNonExistence(timeout: 5))
        XCTAssertFalse(element("todo.edit.g2", in: app).exists, "Groceries are not editable")
    }

    func testAdminTodoRenamesAndCompletesWithItsScript() {
        let app = launch(page: "to-do")
        XCTAssertTrue(app.navigationBars["To-Do"].waitForExistence(timeout: 5))
        element("todo.edit.a1", in: app).tap()
        let name = app.textFields["renameTodo.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["renameTodo.save"].isEnabled)
        name.tap()
        name.typeText(" now")
        app.buttons["renameTodo.save"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        XCTAssertEqual(lastCall(in: app), "todo.update_item a1")
        element("todo.item.a2", in: app).tap()
        XCTAssertTrue(element("todo.item.a2", in: app).waitForNonExistence(timeout: 5))
        XCTAssertEqual(lastCall(in: app), "script.complete_admin_todo_item a2")
    }

    func testEmptyPagesSayNiceJob() {
        let app = launch(page: "stephens-chores", empty: true)
        XCTAssertTrue(element("todo.empty", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["You have no chores due- nice job!"].exists)
    }

    // MARK: Audits and screenshots

    func testChoresTabPassesAccessibilityAudit() throws {
        let app = launch()
        keepScreenshot(app, screenshotName("chores"))
        try FentonHomeApp.audit(app) { self.launch(arguments: FentonHomeApp.ax5) }
    }

    func testSubPagesPassAccessibilityAudit() throws {
        for page in ["groceries", "stephens-chores", "stephs-chores", "unassigned-chores", "home-improvement-chores", "to-do"] {
            let app = launch(page: page)
            keepScreenshot(app, screenshotName(page))
            try FentonHomeApp.audit(app) { self.launch(page: page, arguments: FentonHomeApp.ax5) }
        }
        let empty = launch(page: "groceries", empty: true)
        keepScreenshot(empty, screenshotName("groceries-empty"))
        try FentonHomeApp.audit(empty) { self.launch(page: "groceries", empty: true, arguments: FentonHomeApp.ax5) }
    }

    func testSheetsPassAccessibilityAudit() throws {
        let sheets: [(name: String, page: String?, open: (XCUIApplication) -> Void, ready: String)] = [
            ("task-create", nil, { $0.buttons["fab.add"].tap() }, "task.save"),
            ("task-edit", nil, { app in
                // Clear of the Add bar and the last-call line, which cover the row's pencil at AX5.
                self.reveal(self.element("todo.edit.13--fixture", in: app), in: app).tap()
            }, "task.name"),
            ("grocery-add", "groceries", { $0.buttons["fab.add"].tap() }, "grocery.add"),
            ("admin-todo-add", "to-do", { $0.buttons["fab.add"].tap() }, "adminTodo.add"),
            ("admin-todo-rename", "to-do", { $0.descendants(matching: .any)["todo.edit.a1"].firstMatch.tap() }, "renameTodo.save"),
        ]
        for sheet in sheets {
            func open(_ app: XCUIApplication) -> XCUIApplication {
                sheet.open(app)
                XCTAssertTrue(app.descendants(matching: .any)[sheet.ready].firstMatch.waitForExistence(timeout: 5), "\(sheet.name) did not open")
                sleep(1) // Let the sheet settle.
                return app
            }
            let app = open(launch(page: sheet.page))
            keepScreenshot(app, screenshotName(sheet.name))
            try FentonHomeApp.audit(app) { open(self.launch(page: sheet.page, arguments: FentonHomeApp.ax5)) }
        }
    }

    // MARK: Live (read-only)

    /// Signed in, the real Chores tab shows its quick links and Groceries opens. Nothing is checked off.
    func testLiveChoresTabIsReadable() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openChores(in: app)
        let groceries = element("chores.link.groceries", in: app)
        XCTAssertTrue(groceries.waitForExistence(timeout: 15), "Quick links missing")
        try FentonHomeApp.audit(app)
        groceries.tap()
        XCTAssertTrue(element("todo.page.groceries", in: app).waitForExistence(timeout: 10))
    }

    /// Opens the Chores section through whichever navigation the window shows: the tab bar, the folded Duo's
    /// vertical bar (a toolbar to XCUITest), or the iPad flyout.
    private func openChores(in app: XCUIApplication) {
        let bar = app.tabBars.buttons["Chores"]
        let item = bar.exists ? bar : app.toolbars.buttons["Chores"]
        if item.waitForExistence(timeout: 5), item.isHittable {
            item.tap()
        } else {
            app.buttons["nav.open"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["nav.flyout"].waitForExistence(timeout: 3), "Flyout did not open")
            app.buttons["nav.chores"].tap()
        }
    }

    /// Goes back one page: the system Back button wherever the bar puts it (the folded iPhone Duo moves bar items
    /// into its vertical bar), else the leading-edge back swipe.
    private func goBack(in app: XCUIApplication) {
        let back = app.buttons["BackButton"].firstMatch
        if back.exists, back.isHittable {
            back.tap()
            return
        }
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: window.frame.height / 2))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: window.frame.width * 0.7, dy: 0)))
    }

    /// Signed in, every Chores quick link opens its page without crashing and comes back (owner report
    /// 2026-10-13: Steph's Chores crashed). Nothing is checked off.
    func testLiveEveryChoresPageOpens() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openChores(in: app)
        for page in ["groceries", "stephens-chores", "stephs-chores", "unassigned-chores", "home-improvement-chores"] {
            let link = element("chores.link.\(page)", in: app)
            XCTAssertTrue(link.waitForExistence(timeout: 15), "\(page) link missing")
            reveal(link, in: app).tap()
            XCTAssertTrue(element("todo.page.\(page)", in: app).waitForExistence(timeout: 10), "\(page) did not open")
            // Let the lists load and draw before leaving.
            _ = element("todo.empty", in: app).waitForExistence(timeout: 4)
            XCTAssertEqual(app.state, .runningForeground, "\(page) crashed the app")
            goBack(in: app)
            XCTAssertTrue(link.waitForExistence(timeout: 10), "Back from \(page) failed")
        }
    }
}
