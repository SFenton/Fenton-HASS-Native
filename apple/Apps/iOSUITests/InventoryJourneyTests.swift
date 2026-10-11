import XCTest

/// Inventory pages, item editor and Add Item sheet in the debug gallery (fixture EverShelf server): rows,
/// prompts, sort/filter, the editor (sheet, or trailing pane on split layouts) and the three-step scan flow,
/// with audits and screenshots on iPhone, iPhone Duo and iPad (`.agents/pages/inventory/`).
@MainActor
final class InventoryJourneyTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        if FentonHomeApp.family == .iPad, ProcessInfo.processInfo.environment["FENTON_UITEST_ORIENTATION"] == "landscape" {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated { if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait } }
    }

    private var layout: String {
        let landscape = ProcessInfo.processInfo.environment["FENTON_UITEST_ORIENTATION"] == "landscape" ? "-landscape" : ""
        return "\(FentonHomeApp.family)\(landscape)"
    }

    private func launch(space: String = "pantry", open: String? = nil, state: String? = nil, arguments: [String] = [],
                        clean: Bool = false, environment: [String: String] = [:]) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment.merge(environment) { $1 }
        app.launchEnvironment["FENTON_GALLERY"] = "inventory"
        app.launchEnvironment["FENTON_GALLERY_SPACE"] = space
        app.launchEnvironment["FENTON_SCAN_CAMERA"] = "simulated"
        if let open { app.launchEnvironment["FENTON_GALLERY_OPEN"] = open }
        if let state { app.launchEnvironment["FENTON_GALLERY_STATE"] = state }
        if clean { app.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1" }
        app.launchArguments += arguments
        app.launch()
        return app
    }

    private func row(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.descendants(matching: .any)["inventory.row.\(name)"]
    }

    private func lastCall(_ app: XCUIApplication) -> String {
        app.staticTexts["gallery.lastCall"].label
    }

    // MARK: - Page

    /// Rows group by name: Black Beans' two batches share one card with a disclosure; expired and undated
    /// items read their state.
    func testPantryRowsGroupAndReadExpiry() {
        let app = launch()
        XCTAssertTrue(row(app, "Black Beans").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Jasmine Rice"].exists)
        XCTAssertTrue(app.staticTexts["Honey"].exists)
        XCTAssertFalse(app.staticTexts["Whole Milk"].exists, "Fridge item on the pantry page")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "expired")).firstMatch.exists)
        let beans = row(app, "Black Beans")
        XCTAssertTrue(beans.buttons["Edit Black Beans"].exists)
        XCTAssertFalse(beans.buttons["Delete Black Beans"].exists, "Multi-batch rows delete from the editor")
    }

    /// Cart asks for a quantity, then sends EverShelf's shopping service and the to-do list item.
    func testAddToGroceriesAsksForQuantity() {
        let app = launch(environment: ["FENTON_GALLERY_HOLD_ADDED": "1"])
        let cart = row(app, "Spaghetti").buttons["inventory.row.cart"]
        XCTAssertTrue(cart.waitForExistence(timeout: 10))
        cart.tap()
        // SwiftUI drops identifiers on alert text fields, so find the alert's only field.
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.clearAndType("2")
        app.alerts.buttons["Add"].tap(until: { !app.alerts.firstMatch.exists })
        XCTAssertTrue(app.buttons["Added Spaghetti to shopping list"].waitForExistence(timeout: 5))
        XCTAssertTrue(lastCall(app).contains("todo.add_item"), lastCall(app))
    }

    /// A single item deletes after a confirmation.
    func testDeleteSingleItemConfirms() {
        let app = launch()
        let delete = row(app, "Honey").buttons["inventory.row.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        delete.tap()
        let confirm = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Honey"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(lastCall(app).hasPrefix("Last call: evershelf.list_inventory") || lastCall(app).contains("delete_inventory"))
    }

    /// Searching filters the page; closing search brings the rows back.
    func testSearchFiltersRows() {
        let app = launch()
        XCTAssertTrue(app.buttons["fab.search"].waitForExistence(timeout: 10))
        app.buttons["fab.search"].tap()
        let field = app.textFields["fab.search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("rice")
        XCTAssertTrue(app.staticTexts["Spaghetti"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Jasmine Rice"].exists)
        app.buttons["fab.search.close"].tap()
        XCTAssertTrue(app.staticTexts["Spaghetti"].waitForExistence(timeout: 5))
    }

    /// The expiring filter keeps only items inside its window and marks Filter as applied.
    func testFilterSheetApplies() {
        let app = launch()
        XCTAssertTrue(app.buttons["fab.inventory.filter"].waitForExistence(timeout: 10))
        app.buttons["fab.inventory.filter"].tap()
        XCTAssertTrue(app.buttons["inventory.filter.expired"].waitForExistence(timeout: 5))
        app.buttons["inventory.filter.expired"].tap()
        app.buttons["filterSheet.apply"].tap()
        XCTAssertTrue(app.staticTexts["Spaghetti"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Jasmine Rice"].exists)
        XCTAssertTrue(app.buttons["fab.inventory.filter"].isSelected)
    }

    // MARK: - Editor

    /// The editor lists each batch; lowering the quantity and saving deletes one from the smallest row.
    func testEditorSavesQuantityChange() {
        let app = launch(open: "editor:Black Beans")
        let editor = app.descendants(matching: .any)["inventory.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let steppers = app.steppers.matching(identifier: "inventory.editor.quantity")
        XCTAssertEqual(steppers.count, 2, "Black Beans has two batches")
        steppers.element(boundBy: 0).buttons.element(boundBy: 0).tap() // Decrement.
        let save = app.buttons["inventory.editor.save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(lastCall(app).contains("evershelf."), lastCall(app))
    }

    /// Prepared food flips at once and is confirmed by a fresh read.
    func testEditorMarksPreparedFood() {
        let app = launch(open: "editor:Spaghetti")
        let toggle = app.switches["inventory.editor.prepared"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Prepared")).firstMatch.waitForExistence(timeout: 5))
    }

    // MARK: - Add Item

    /// Scan, read the date, review and add: the item lands in the pantry.
    func testScanFlowAddsItem() {
        // All Food: the fixture's location suggestion files Greek Yogurt in the fridge, not the pantry.
        let app = launch(space: "all-food", open: "scan")
        let simulate = app.buttons["scan.simulate"]
        XCTAssertTrue(simulate.waitForExistence(timeout: 10))
        let name = app.textFields["scan.name"]
        simulate.tap(until: { name.exists })
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Greek Yogurt")
        app.buttons["scan.forward"].tap()

        XCTAssertTrue(app.buttons["scan.simulate"].waitForExistence(timeout: 5))
        app.buttons["scan.simulate"].tap()
        XCTAssertTrue(app.buttons["scan.forward"].waitForExistence(timeout: 5))
        app.buttons["scan.forward"].tap()

        XCTAssertTrue(app.buttons["scan.add"].waitForExistence(timeout: 5))
        app.buttons["scan.add"].tap()
        XCTAssertTrue(app.buttons["scan.done"].waitForExistence(timeout: 10))
        app.buttons["scan.done"].tap()
        XCTAssertTrue(app.staticTexts["Greek Yogurt"].waitForExistence(timeout: 10), "Added row missing from All Food")
    }

    /// Manual entry: type a name, pick a quick date, review.
    func testManualEntryFlow() {
        let app = launch(open: "scan")
        XCTAssertTrue(app.buttons["scan.manualName"].waitForExistence(timeout: 10))
        app.buttons["scan.manualName"].tap()
        let name = app.textFields["scan.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Oat Milk")
        app.buttons["scan.forward"].tap()
        XCTAssertTrue(app.buttons["scan.manualExpiry"].waitForExistence(timeout: 5))
        app.buttons["scan.manualExpiry"].tap()
        XCTAssertTrue(app.buttons["scan.quick.1-week"].waitForExistence(timeout: 5))
        app.buttons["scan.quick.1-week"].tap()
        XCTAssertTrue(app.buttons["scan.quick.1-week"].isSelected)
        app.buttons["scan.forward"].tap()
        XCTAssertTrue(app.buttons["scan.add"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["scan.location.dispensa"].isSelected || app.buttons["scan.location.frigo"].isSelected)
    }

    // MARK: - Live

    /// Signed in against the real server, `FENTON_OPEN_INVENTORY=pantry` pushes the Pantry page from Home.
    /// Item names are redacted under `FENTON_REDACT_PRIVATE=1`. Skips without credentials.
    func testLivePantryOpensFromHome() throws {
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_OPEN_INVENTORY": "pantry"])
        XCTAssertTrue(app.descendants(matching: .any)["inventory.pantry"].waitForExistence(timeout: 30), "Pantry did not open")
        let loaded = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'inventory.row.' OR identifier == 'inventory.empty'")).firstMatch
        XCTAssertTrue(loaded.waitForExistence(timeout: 30), "Pantry rows did not load")
        sleep(1)
        keepScreenshot(app, "inventory-live-pantry-\(layout)")
    }

    // MARK: - Audits and screenshots

    func testPagesPassAccessibilityAudit() throws {
        for space in ["all-food", "pantry", "fridge", "freezer", "spice-rack", "cabinet"] {
            let app = launch(space: space, clean: true)
            XCTAssertTrue(app.descendants(matching: .any)["inventory.\(space)"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["fab.inventory.scan"].waitForExistence(timeout: 10))
            keepScreenshot(app, "inventory-\(space)-\(layout)")
            try FentonHomeApp.audit(app) { self.launch(space: space, arguments: FentonHomeApp.ax5, clean: true) }
            app.terminate()
        }
    }

    func testEmptyAndErrorStatesPassAudit() throws {
        for state in ["empty", "error"] {
            let app = launch(state: state, clean: true)
            XCTAssertTrue(app.descendants(matching: .any)["inventory.empty"].waitForExistence(timeout: 10))
            keepScreenshot(app, "inventory-\(state)-\(layout)")
            try FentonHomeApp.audit(app) { self.launch(state: state, arguments: FentonHomeApp.ax5, clean: true) }
            app.terminate()
        }
    }

    func testSheetsPassAccessibilityAudit() throws {
        for (open, ready) in [("sort", "inventory.sort.title"), ("filter", "inventory.filter.all"),
                              ("editor:Black Beans", "inventory.editor.close"), ("editor:Honey", "inventory.editor.close")] {
            func opened(_ arguments: [String]) -> XCUIApplication {
                let app = launch(open: open, arguments: arguments, clean: true)
                XCTAssertTrue(app.buttons[ready].firstMatch.waitForExistence(timeout: 10), "\(open) did not open")
                sleep(1) // Let the sheet settle.
                return app
            }
            let app = opened([])
            let name = open.replacingOccurrences(of: "editor:", with: "editor-").replacingOccurrences(of: " ", with: "-").lowercased()
            keepScreenshot(app, "inventory-\(name)-\(layout)")
            try FentonHomeApp.audit(app) { opened(FentonHomeApp.ax5) }
            app.terminate()
        }
    }

    func testScanStepsPassAccessibilityAudit() throws {
        /// At AX5 wrapped text pushes controls below the fold, where the form loads them once scrolled to; the
        /// footer's large buttons leave the form a short window, so it can take several swipes.
        func reveal(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
            var swipes = 0
            while !(element.waitForExistence(timeout: 2) && element.isHittable), swipes < 10 {
                app.swipeUp()
                swipes += 1
            }
            XCTAssertTrue(element.exists, "\(element) not found")
            return element
        }
        func atStep(_ step: Int, _ arguments: [String]) -> XCUIApplication {
            let app = launch(open: "scan", arguments: arguments, clean: true)
            XCTAssertTrue(app.buttons["scan.cancel"].waitForExistence(timeout: 10))
            _ = reveal(app.buttons["scan.simulate"], in: app)
            if step >= 2 {
                app.buttons["scan.simulate"].tap(until: { app.textFields["scan.name"].exists })
                XCTAssertTrue(app.buttons["scan.forward"].waitForExistence(timeout: 5))
                app.buttons["scan.forward"].tap()
                _ = reveal(app.buttons["scan.manualExpiry"], in: app)
            }
            if step >= 3 {
                app.buttons["scan.manualExpiry"].tap()
                reveal(app.buttons["scan.quick.1-month"], in: app).tap()
                app.buttons["scan.forward"].tap()
                XCTAssertTrue(app.buttons["scan.add"].waitForExistence(timeout: 5))
            }
            sleep(1)
            return app
        }
        for step in 1...3 {
            let app = atStep(step, [])
            keepScreenshot(app, "inventory-scan-step\(step)-\(layout)")
            try FentonHomeApp.audit(app) { atStep(step, FentonHomeApp.ax5) }
            app.terminate()
        }
    }
}

private extension XCUIElement {
    /// Taps, then retries (up to three taps) until `done` holds: a tap that lands while a sheet or alert is
    /// still animating in is dropped on a loaded host.
    func tap(until done: () -> Bool) {
        for _ in 0..<3 {
            tap()
            let deadline = Date().addingTimeInterval(4)
            while Date() < deadline {
                if done() { return }
                usleep(250_000)
            }
            guard exists, isHittable else { return }
        }
    }

    func clearAndType(_ text: String) {
        tap()
        if let value = value as? String, !value.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        typeText(text)
    }
}
