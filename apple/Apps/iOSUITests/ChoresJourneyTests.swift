import XCTest

/// Chores tab, its sub-pages, the admin To-Do and every todo sheet on fixture lists in the debug gallery
/// (no house changes), plus a read-only signed-in pass of the real Chores tab. Spec: `.agents/pages/chores/spec.md`.
@MainActor
final class ChoresJourneyTests: JourneyTestCase {
    // MARK: Helpers

    /// The settings belong to the simulator: leave it as found.
    override func tearDown() {
        super.tearDown()
        let reduced = reducedMotion
        MainActor.assumeIsolated {
            if reduced { FentonHomeApp.launchGallery("system-accessibility").terminate() }
        }
    }

    private var reducedMotion = false

    /// Drags a row part of the way left, which opens its trailing swipe actions without performing the full swipe.
    private func revealTrailingActions(of row: XCUIElement) {
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)))
    }

    private func launch(page: String? = nil, empty: Bool = false, arguments: [String] = [], environment: [String: String] = [:]) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "chores"
        app.launchEnvironment.merge(environment) { _, new in new }
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
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, clearOfBar: Bool = true) -> XCUIElement {
        func clear() -> Bool {
            guard element.exists, element.isHittable else { return false }
            // `clearOfBar: false` asks only for a hittable element, for a row big enough that no scroll position puts all of
            // it above the bar (the folded Duo's AX5 rows are 386 pt tall and the bar crosses the screen at y 430).
            guard clearOfBar else { return true }
            let overlays = [app.buttons["fab.add"], app.staticTexts["gallery.lastCall"]].filter(\.exists)
            let top = overlays.map(\.frame.minY).min() ?? .greatestFiniteMagnitude
            return element.frame.maxY <= top
        }
        // Content-up drags of a measured distance once the row is in the tree, and back down when it went past: a fixed
        // 200 pt step jumped over the folded Duo's AX5 clear band (the Add bar sits at y 430, a row is 300 pt tall), and
        // the lazy list then dropped the row for good. A short drag, not a fling, so the row stops where it lands and the
        // next tap isn't eaten by deceleration.
        func drag(contentUp distance: CGFloat) {
            let scroll = scroller(app)
            let height = max(scroll.frame.height, 1)
            let half = min(max(distance, -300), 420) / height / 2
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5 + half))
                .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5 - half)))
        }
        for _ in 0..<80 where !clear() { // AX5 pages run many screens long, the folded Duo's the most (20 drags fell short).
            // 400 pt, as the last-chore journey drags: 200 pt drags did not carry the folded Duo's AX5 page the 2,400 pt to
            // the first row in 80 attempts.
            guard element.exists else { drag(contentUp: 400); continue }
            guard clearOfBar else { drag(contentUp: 200); continue } // In the tree but not hittable yet: carry on down.
            let overlays = [app.buttons["fab.add"], app.staticTexts["gallery.lastCall"]].filter(\.exists)
            let top = overlays.map(\.frame.minY).min() ?? .greatestFiniteMagnitude
            let frame = element.frame
            if frame.maxY > top {
                drag(contentUp: min(max(frame.maxY - top + 12, 100), 300)) // Below the band: bring it up to the bar.
            } else {
                drag(contentUp: -120) // Under the header, or not hittable above the band: back down.
            }
        }
        if !clear() {
            let state = element.exists ? "exists hittable=\(element.isHittable) frame=\(element.frame)" : "not in the tree"
            add(XCTAttachment(string: "\(state)\n" + app.debugDescription))
        }
        XCTAssertTrue(clear(), "\(element) never came into view")
        return element
    }

    /// The page's scrolling list: a `List` is a collection view to XCUITest.
    private func scroller(_ app: XCUIApplication) -> XCUIElement {
        app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews.firstMatch
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
        // The page that opens is the tapped link's (in a list row, the links all fired and Groceries, the last, won).
        XCTAssertTrue(app.navigationBars["Stephen's Chores"].waitForExistence(timeout: 10), "Your Chores did not open Stephen's Chores")
    }

    /// The quick links start and end where the modules below them do, whatever the window: the header they sit in is set in
    /// by the system, and `AlignedToListMargins` takes that back (owner follow-up, 2026-10-17: the tiles were inset about
    /// 16 pt more than the Past Due rows).
    func testQuickLinksAlignWithTheListMargins() {
        let app = launch()
        let groceries = element("chores.link.groceries", in: app)
        XCTAssertTrue(groceries.waitForExistence(timeout: 10))
        let heading = app.staticTexts["Past Due"].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 5), "Past Due heading missing")
        let edit = element("todo.edit.12--fixture", in: app)
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "Past Due row missing")
        // Let the measured inset settle.
        sleep(1)
        XCTAssertEqual(groceries.frame.minX, heading.frame.minX, accuracy: 1.5, "The tiles start inside the headings' edge")
        // The row's edit button sits 4 pt inside the module's trailing edge.
        // The grid's rightmost tile (Groceries spans the row on a phone, but not in four columns on iPad).
        let tiles = ["stephens-chores", "stephs-chores", "unassigned-chores", "home-improvement-chores", "groceries"]
            .map { element("chores.link.\($0)", in: app) }
        let trailing = tiles.map(\.frame.maxX).max() ?? 0
        let leading = tiles.map(\.frame.minX).min() ?? 0
        XCTAssertEqual(leading, heading.frame.minX, accuracy: 1.5, "The leftmost tile starts at the headings' edge")
        XCTAssertEqual(trailing, edit.frame.maxX + 4, accuracy: 2, "The rightmost tile ends at the modules' edge")
        keepScreenshot(app, screenshotName("chores-alignment"))
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

    /// The pencil opens the task form, loads the task, and saving sends the form once something changed: the confirm
    /// check is disabled while the task is as loaded (`SheetEditState`).
    func testEditingATaskLoadsAndSaves() {
        let app = launch()
        let edit = element("todo.edit.13--fixture", in: app)
        reveal(edit, in: app)
        XCTAssertEqual(edit.label, "Edit Run the dishwasher")
        edit.tap()
        let name = app.textFields["task.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Run the dishwasher")
        let save = app.buttons["task.save"]
        XCTAssertFalse(save.isEnabled, "Nothing changed yet: the check is disabled")
        name.tap()
        name.typeText("!")
        XCTAssertTrue(save.wait(for: \.isEnabled, toEqual: true, timeout: 5), "A change enables the check")
        save.tap()
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
        submit(create, closing: create)
        XCTAssertEqual(lastCall(in: app), "donetick.create_task_form")
    }

    /// Owner, 2026-10-16: Task Name and Description are separate fields, each with a footer saying what goes in it, and the
    /// header no longer says "Donetick".
    func testAddTaskSheetHasSeparateFieldsWithFooters() {
        let app = launch()
        app.buttons["fab.add"].tap()
        XCTAssertTrue(app.textFields["task.name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["task.description"].exists || app.textViews["task.description"].exists)
        for footer in ["task.name.footer", "task.description.footer"] {
            XCTAssertTrue(element(footer, in: app).exists, "\(footer) missing")
        }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'short name for the chore'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Optional. Add steps'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Donetick"].exists, "The Donetick subtitle is gone")
        keepScreenshot(app, screenshotName("task-create-fields"))
    }

    // MARK: Swipe actions

    /// Owner, 2026-10-16: swiping a row in from the leading edge completes it (a full swipe performs the action).
    func testLeadingSwipeCompletes() {
        let app = launch()
        let row = reveal(element("todo.item.13--fixture", in: app), in: app)
        // A drag across most of the row is a full swipe, which performs the leading action.
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)))
        XCTAssertTrue(row.waitForNonExistence(timeout: 8), "Swiped chore still shown")
        XCTAssertEqual(lastCall(in: app), "todo.update_item 13--fixture")
    }

    /// The trailing swipe offers Delete (outermost) and Edit; Edit opens the task form.
    func testTrailingSwipeShowsDeleteAndEdit() {
        let app = launch()
        let row = reveal(element("todo.item.13--fixture", in: app), in: app)
        revealTrailingActions(of: row)
        let delete = element("todo.swipe.delete.13--fixture", in: app)
        let edit = element("todo.swipe.edit.13--fixture", in: app)
        XCTAssertTrue(delete.waitForExistence(timeout: 5) && edit.exists, "Trailing actions missing")
        XCTAssertEqual(delete.label, "Delete")
        XCTAssertEqual(edit.label, "Edit")
        keepScreenshot(app, screenshotName("chores-swipe-trailing"))
        XCTAssertLessThan(edit.frame.minX, delete.frame.minX, "Delete is outermost")
        edit.tap()
        XCTAssertTrue(app.textFields["task.name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["task.name"].value as? String, "Run the dishwasher")
    }

    /// Delete asks first; cancelling leaves the task, confirming removes it with `todo.remove_item`.
    func testSwipeDeleteConfirmsBeforeRemoving() {
        let app = launch()
        let row = reveal(element("todo.item.13--fixture", in: app), in: app)
        revealTrailingActions(of: row)
        element("todo.swipe.delete.13--fixture", in: app).tap()
        let confirm = element("todo.delete.confirm", in: app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "No confirmation")
        XCTAssertNotEqual(lastCall(in: app), "todo.remove_item 13--fixture", "Deleted before the answer")
        XCTAssertTrue(row.exists)
        confirm.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        XCTAssertEqual(lastCall(in: app), "todo.remove_item 13--fixture")
    }

    /// Owner, 2026-10-16: a completed chore animates away, and if Home Assistant rejects it the chore comes back with
    /// the error (the fixture refuses every check-off after 4 s).
    func testRejectedCompletionBringsTheChoreBack() {
        let app = launch(environment: ["FENTON_GALLERY_FAIL_COMPLETE": "1"])
        let row = reveal(element("todo.item.13--fixture", in: app), in: app)
        row.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 8), "The chore did not leave at once")
        XCTAssertTrue(element("todo.item.13--fixture", in: app).waitForExistence(timeout: 15), "The chore never came back")
        XCTAssertTrue(app.staticTexts["Unable to update task"].waitForExistence(timeout: 3), "No error shown")
        XCTAssertTrue(lastCall(in: app).hasSuffix("failed"))
    }

    /// Reduce Motion: the row still leaves and returns (a fade, not a slide).
    func testCompletionStillWorksWithReduceMotion() {
        let app = FentonHomeApp.launchGallery("chores", environment: FentonHomeApp.SystemSetting.environment([.reduceMotion]))
        reducedMotion = true
        XCTAssertTrue(app.buttons["fab.add"].waitForExistence(timeout: 10))
        let row = reveal(element("todo.item.13--fixture", in: app), in: app)
        row.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
    }

    /// Owner, 2026-10-16: quick-link tiles are filled in colours that nothing else in the app uses, with white filled
    /// glyphs. Each tile's fill is sampled from the screen and matched to its family.
    func testQuickLinkTilesAreFilledInTheirOwnColours() throws {
        let app = launch()
        let expected: [(id: String, family: String, rgb: (Int, Int, Int))] = [
            ("stephens-chores", "choreStephen", (0x00, 0x22, 0xCC)),
            ("stephs-chores", "choreSteph", (0xB4, 0x10, 0xAE)),
            ("unassigned-chores", "choreUnassigned", (0xC2, 0x12, 0x7A)),
            ("home-improvement-chores", "choreHome", (0x66, 0x00, 0xCC)),
            ("groceries", "groceries", (0x80, 0x22, 0x00)),
        ]
        keepScreenshot(app, screenshotName("chores-quick-links"))
        let capture = try XCTUnwrap(RenderedContrast.Capture.screen())
        for tile in expected {
            let link = element("chores.link.\(tile.id)", in: app)
            XCTAssertTrue(link.exists, tile.id)
            // The bottom-leading corner area, below the text and clear of the top highlight. On the page the tile is tinted
            // glass: the fill at 78% over the dark underlay, then the sheen's bottom shade (`TileGeometry.glass`).
            let point = CGPoint(x: link.frame.minX + 10, y: link.frame.maxY - 6)
            let sample = try XCTUnwrap(RenderedContrast.rgb(at: point, in: capture), tile.id)
            let fill = UInt32(tile.rgb.0 << 16 | tile.rgb.1 << 8 | tile.rgb.2)
            XCTAssertTrue(TileGeometry.matchesGlass((sample.red, sample.green, sample.blue), fill, onPage: true,
                                                    heightFraction: 1 - 6 / link.frame.height),
                          "\(tile.id) is \(sample), expected \(tile.rgb) (\(tile.family)) under tinted glass")
        }
    }

    /// The Add bar's height is added to the list's bottom inset: at AX5 the last chore scrolls clear of the bar and can be
    /// tapped (owner, 2026-10-16: nothing permanently covered).
    func testLastChoreScrollsClearOfTheAddBar() {
        let app = launch(arguments: FentonHomeApp.ax5)
        let list = scroller(app)
        let last = element("todo.item.15--fixture", in: app)
        // Until the last row exists (a lazy list only builds rows near the viewport, and the folded Duo's short screen needs
        // more than the 20 swipes the iPhone does), then a few more so the list is at its end.
        // Dragged at the leading edge like `reveal`: `swipeUp` from the list's centre did not scroll it at all on the folded
        // Duo (the dump after 80 swipes showed the top of the page, 2026-10-17).
        func drag() {
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.8))
                .press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.2)))
        }
        for _ in 0..<80 where !last.exists { drag() }
        for _ in 0..<3 { drag() }
        if !last.exists { add(XCTAttachment(string: app.debugDescription)) }
        XCTAssertTrue(last.exists, "The last chore never appeared")
        let barTop = min(app.buttons["fab.add"].frame.minY, app.staticTexts["gallery.lastCall"].frame.minY)
        XCTAssertLessThanOrEqual(last.frame.maxY, barTop, "The last chore ends under the Add bar")
        XCTAssertTrue(last.isHittable)
    }

    // MARK: Sub-pages

    func testGroceriesAddAndCheckOff() {
        let app = launch(page: "groceries")
        XCTAssertEqual(app.buttons["fab.add"].label, "Add Groceries")
        app.buttons["fab.add"].tap()
        let field = app.textFields["grocery.item"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Eggs")
        submit(app.buttons["grocery.add"], closing: field)
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
        // On iPad the first tap can only end editing in the focused field.
        submit(app.buttons["renameTodo.save"], closing: name)
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
                // The row's context-menu Edit, not its pencil: at AX5 the pencil sits mid-row, the folded Duo's rows are
                // 386 pt tall and the Add bar and last-call line cross the screen at y 430, so no scroll position put the
                // pencil clear of them (2026-10-17). The menu opens the same form.
                let row = self.reveal(self.element("todo.item.13--fixture", in: app), in: app, clearOfBar: false)
                row.press(forDuration: 1.2)
                let edit = app.buttons["Edit"].firstMatch
                XCTAssertTrue(edit.waitForExistence(timeout: 5), "The row's context menu has no Edit")
                edit.tap()
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

    /// Taps a sheet's submit button and waits for `closing` to go. On iPad the first tap can only end editing in
    /// the focused field, so it taps once more if the sheet stayed.
    private func submit(_ button: XCUIElement, closing: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        button.tap()
        if !closing.waitForNonExistence(timeout: 2), button.exists, button.isHittable { button.tap() }
        XCTAssertTrue(closing.waitForNonExistence(timeout: 5), "Sheet stayed open", file: file, line: line)
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
