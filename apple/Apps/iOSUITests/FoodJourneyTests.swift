import XCTest

/// The Food & Recipes hub, Recipes grid and recipe detail in the debug gallery (fixture recipes, recording
/// service; nothing reaches the house): semantics, service calls, split per pose, accessibility audits and
/// screenshots on iPhone, iPhone Duo and iPad (`.agents/pages/food/spec.md`).
@MainActor
final class FoodJourneyTests: XCTestCase {
    /// `TEST_RUNNER_FENTON_ORIENTATION=landscape` runs every journey in landscape (iPad and unfolded Duo
    /// screenshots per layout); otherwise portrait.
    private static var orientation: UIDeviceOrientation {
        ProcessInfo.processInfo.environment["FENTON_ORIENTATION"] == "landscape" ? .landscapeLeft : .portrait
    }

    override func setUp() {
        continueAfterFailure = false
        MainActor.assumeIsolated {
            if FentonHomeApp.family != .iPhone { XCUIDevice.shared.orientation = Self.orientation }
        }
    }
    override func tearDown() {
        MainActor.assumeIsolated {
            if FentonHomeApp.family != .iPhone { XCUIDevice.shared.orientation = Self.orientation }
        }
    }

    // MARK: - Helpers

    private var device: String {
        switch FentonHomeApp.family {
        case .iPhone: "iphone"
        case .iPhoneDuo: Self.orientation == .portrait ? "duo" : "duo-landscape"
        case .iPad: Self.orientation == .portrait ? "ipad" : "ipad-landscape"
        }
    }

    private func launch(_ route: String, mode: String? = nil, arguments: [String] = [], environment: [String: String] = [:]) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment.merge(environment) { $1 }
        app.launchEnvironment["FENTON_GALLERY"] = "food"
        app.launchEnvironment["FENTON_GALLERY_ROUTE"] = route
        if let mode { app.launchEnvironment["FENTON_GALLERY_FOOD_MODE"] = mode }
        app.launchArguments += arguments
        app.launch()
        return app
    }

    /// The accessibility audit, unless `TEST_RUNNER_FENTON_SKIP_AUDIT=1` (screenshot-only passes, so a failing
    /// audit cannot stop a journey before its later pages are captured).
    private func audit(_ app: XCUIApplication, presenter: XCUIElement? = nil, ax5Page: (() throws -> XCUIApplication)? = nil) throws {
        guard ProcessInfo.processInfo.environment["FENTON_SKIP_AUDIT"] != "1" else { return }
        try FentonHomeApp.audit(app, ax5Page: ax5Page, presenter: presenter)
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func expectCall(_ prefix: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let label = app.staticTexts["gallery.lastCall"].firstMatch
        let matched = waitFor(label, "label BEGINSWITH %@", "Last call: \(prefix)")
        XCTAssertTrue(matched, "Last call was '\(label.label)'", file: file, line: line)
    }

    private func waitFor(_ element: XCUIElement, _ format: String, _ argument: String, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: format, argument), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Swipes up until `element` is on screen; `container` (e.g. the recipe's scroll view in a split pane)
    /// receives the swipes, the app otherwise.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, swiping container: XCUIElement? = nil) {
        let target = container ?? app
        for _ in 0..<12 where !(element.exists && element.isHittable) { target.swipeUp() }
        XCTAssertTrue(element.isHittable, "\(element) never came into view")
    }

    private func assertTarget(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(element.frame.width, 43, element.label, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 43, element.label, file: file, line: line)
    }

    private func waitForGrid(_ app: XCUIApplication) {
        XCTAssertTrue(element("recipes.card.1", in: app).waitForExistence(timeout: 15), "Recipes did not load")
        sleep(1) // Mid-animation frames fail contrast and clipping.
    }

    // MARK: - Hub

    func testHubShowsSuggestionsRecipesAndSpaces() throws {
        let app = launch("hub")
        XCTAssertTrue(app.navigationBars["Food & Recipes"].waitForExistence(timeout: 15))
        XCTAssertTrue(element("food.suggestion.1", in: app).waitForExistence(timeout: 10), "Suggestions did not load")
        expectCall("recipe_query kind=recommendations limit=40", in: app)
        let allRecipes = element("food.allRecipes", in: app)
        XCTAssertTrue(allRecipes.exists)
        assertTarget(allRecipes)
        reveal(element("food.space.cabinet", in: app), in: app)
        let fridge = element("food.space.frigo", in: app)
        XCTAssertTrue("\(fridge.label) \(fridge.value as? String ?? "")".contains("38 Items"), "Fridge tile reads '\(fridge.label)'")
        sleep(1)
        keepScreenshot(app, "food-hub-spaces-\(device)")
        // Audit from the top: scrolled down, the carousel sits half under the translucent bar and measures ~1.1:1.
        let first = element("food.suggestion.1", in: app)
        for _ in 0..<4 where !first.isHittable { app.swipeDown() }
        app.swipeDown()
        sleep(1)
        keepScreenshot(app, "food-hub-\(device)")
        try audit(app) { self.launch("hub", arguments: FentonHomeApp.ax5) }

        first.tap()
        XCTAssertTrue(element("recipe.tabs", in: app).waitForExistence(timeout: 10), "Recipe sheet did not open")
        expectCall("recipe_detail recipe_id=1", in: app)
    }

    /// Swiping the suggestions pages them: the dots follow, nothing opens, and swiping back returns to the first page.
    func testSuggestionsPageBySwipe() throws {
        let app = launch("hub")
        let first = element("food.suggestion.1", in: app)
        XCTAssertTrue(first.waitForExistence(timeout: 15), "Suggestions did not load")
        let dots = element("food.suggestions.pages", in: app)
        XCTAssertTrue(dots.waitForExistence(timeout: 5))
        XCTAssertTrue((dots.value as? String ?? "").hasPrefix("1 of"), "\(String(describing: dots.value))")
        for _ in 0..<3 where !first.isHittable { app.swipeDown() }
        let section = element("food.suggestions", in: app)
        section.swipeLeft()
        XCTAssertTrue(waitFor(dots, "value BEGINSWITH %@", "2 of"), "The dots stayed on \(String(describing: dots.value))")
        XCTAssertFalse(element("recipe.tabs", in: app).exists, "Swiping opened a recipe")
        section.swipeRight()
        XCTAssertTrue(waitFor(dots, "value BEGINSWITH %@", "1 of"), "The dots stayed on \(String(describing: dots.value))")
    }

    /// The hub's recipe sheet switches tabs (on iPad a live hub sheet ignored taps on the picker, 2026-10-12).
    func testHubSheetSwitchesTabs() {
        let app = launch("hub")
        let suggestion = element("food.suggestion.2", in: app)
        XCTAssertTrue(suggestion.waitForExistence(timeout: 15))
        suggestion.tap()
        let tabs = element("recipe.tabs", in: app)
        XCTAssertTrue(tabs.waitForExistence(timeout: 10), "Recipe sheet did not open")
        sleep(1)
        let ingredients = tabs.buttons["Ingredients"]
        ingredients.tap()
        XCTAssertTrue(element("recipe.ingredient.0", in: app).waitForExistence(timeout: 10), "The hub's recipe sheet did not switch to Ingredients")
        tabs.buttons["Instructions"].tap()
        XCTAssertTrue(app.staticTexts["Heat the oven to 425°F and zest the lemons."].waitForExistence(timeout: 10))
    }

    /// The same check with the pages inside a TabView, as in the live app (the live iPad sheet ignored taps).
    func testHubSheetSwitchesTabsInTabView() {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "food"
        app.launchEnvironment["FENTON_GALLERY_ROUTE"] = "hub"
        app.launchEnvironment["FENTON_GALLERY_FOOD_TABS"] = "1"
        app.launch()
        let suggestion = element("food.suggestion.2", in: app)
        XCTAssertTrue(suggestion.waitForExistence(timeout: 15))
        suggestion.tap()
        let tabs = element("recipe.tabs", in: app)
        XCTAssertTrue(tabs.waitForExistence(timeout: 10), "Recipe sheet did not open")
        sleep(1)
        tabs.buttons["Ingredients"].tap()
        XCTAssertTrue(element("recipe.ingredient.0", in: app).waitForExistence(timeout: 10),
                      "In a TabView the hub's recipe sheet did not switch to Ingredients")
    }

    /// The hub opened by the debug launch route (FENTON_OPEN_FOOD, a navigationDestination(item:)) with fixture
    /// data: the live iPad journeys open Food this way and their recipe sheet ignored taps (2026-10-12).
    func testLaunchRouteHubSheetSwitchesTabs() {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "food"
        app.launchEnvironment["FENTON_GALLERY_ROUTE"] = "none"
        app.launchEnvironment["FENTON_OPEN_FOOD"] = "hub"
        app.launch()
        let suggestion = element("food.suggestion.2", in: app)
        XCTAssertTrue(suggestion.waitForExistence(timeout: 15))
        suggestion.tap()
        let tabs = element("recipe.tabs", in: app)
        XCTAssertTrue(tabs.waitForExistence(timeout: 10), "Recipe sheet did not open")
        sleep(1)
        tabs.buttons["Ingredients"].tap()
        XCTAssertTrue(element("recipe.ingredient.0", in: app).waitForExistence(timeout: 10),
                      "From the launch route the hub's recipe sheet did not switch to Ingredients")
    }

    /// Hub tiles are controls of their own: All Recipes pushes the grid, a space tile pushes its inventory page.
    func testHubTilesOpenTheirPages() {
        // A fresh launch per tile: the back button's place differs per layout (and in Duo landscape).
        var app = launch("hub")
        let allRecipes = element("food.allRecipes", in: app)
        XCTAssertTrue(allRecipes.waitForExistence(timeout: 15))
        allRecipes.tap()
        XCTAssertTrue(app.navigationBars["Recipes"].waitForExistence(timeout: 10), "All Recipes did not open the grid")
        waitForGrid(app)

        app = launch("hub")
        let fridge = element("food.space.frigo", in: app)
        XCTAssertTrue(fridge.waitForExistence(timeout: 15))
        reveal(fridge, in: app)
        fridge.tap()
        XCTAssertTrue(app.navigationBars["Fridge"].waitForExistence(timeout: 10), "The Fridge tile did not open its page")

        app = launch("hub")
        let allFood = element("food.allFood", in: app)
        XCTAssertTrue(allFood.waitForExistence(timeout: 15))
        reveal(allFood, in: app)
        allFood.tap()
        XCTAssertTrue(app.navigationBars["All Food"].waitForExistence(timeout: 10), "All Food did not open its page")
    }

    /// The hub loads like the web (owner, 2026-10-16): the spinner fades in over a hidden hub, then the spinner leaves
    /// and the content fades in; they never show together.
    func testHubSpinnerThenContent() throws {
        // Answers take 5 s, so the spinner outlasts the simulator's own launch and can be watched.
        let app = launch("hub", environment: ["FENTON_GALLERY_FOOD_DELAY_MS": "5000"])
        let spinner = element("contentGate.spinner", in: app)
        XCTAssertTrue(spinner.waitForExistence(timeout: 5), "The spinner never showed")
        XCTAssertEqual(spinner.label, "Loading Food & Recipes")
        XCTAssertFalse(element("food.suggestion.1", in: app).exists, "The hub's content shows under the spinner")
        XCTAssertFalse(element("food.allFood", in: app).exists, "The hub's tiles show under the spinner")
        XCTAssertTrue(element("food.suggestion.1", in: app).waitForExistence(timeout: 20), "The hub never loaded")
        XCTAssertTrue(spinner.waitForNonExistence(timeout: 3), "The spinner stayed once the content showed")
    }

    /// While the suggestions never arrive the spinner holds and the hub stays hidden.
    func testHubStaysOnTheSpinnerWhileLoading() {
        let app = launch("hub", mode: "slow")
        XCTAssertTrue(element("contentGate.spinner", in: app).waitForExistence(timeout: 5))
        sleep(2)
        XCTAssertTrue(element("contentGate.spinner", in: app).exists)
        XCTAssertFalse(element("food.allRecipes", in: app).exists)
    }

    /// All Recipes, All Food and the five spaces are filled tiles, each a button with its count line as the value.
    func testHubTilesAreColouredTiles() throws {
        let app = launch("hub")
        XCTAssertTrue(element("food.suggestion.1", in: app).waitForExistence(timeout: 15))
        let allRecipes = element("food.allRecipes", in: app)
        XCTAssertTrue(allRecipes.exists)
        XCTAssertEqual(allRecipes.elementType, .button, "All Recipes is a tile button")
        let allFood = element("food.allFood", in: app)
        reveal(allFood, in: app)
        XCTAssertEqual(allFood.elementType, .button, "All Food is a tile button, not a list row")
        XCTAssertTrue("\(allFood.label) \(allFood.value as? String ?? "")".contains("143 Items"), "All Food reads '\(allFood.label)'")
        assertTarget(allFood)
        let titles = ["dispensa": "Pantry", "frigo": "Fridge", "freezer": "Freezer", "spice_rack": "Spice Rack", "cabinet": "Cabinet"]
        reveal(element("food.space.cabinet", in: app), in: app)
        for (key, title) in titles {
            let tile = element("food.space.\(key)", in: app)
            XCTAssertTrue(tile.exists, title)
            XCTAssertEqual(tile.label, title)
            assertTarget(tile)
        }
        sleep(1)
        keepScreenshot(app, "food-hub-tiles-\(device)")
        // Audit from the top, as the hub journey does: the audit measures frames against a capture that a scrolled page moves.
        for _ in 0..<4 where !element("food.suggestion.1", in: app).isHittable { app.swipeDown() }
        sleep(1)
        try audit(app)
    }

    func testHubFailureOffersRetry() {
        let app = launch("hub", mode: "error")
        XCTAssertTrue(element("food.suggestions.error", in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(element("food.allRecipes", in: app).exists, "navigation stays available when suggestions fail")
    }

    func testHubAtAX5() throws {
        let app = launch("hub", arguments: FentonHomeApp.ax5)
        XCTAssertTrue(element("food.suggestion.1", in: app).waitForExistence(timeout: 15))
        sleep(1)
        keepScreenshot(app, "food-hub-\(device)-ax5")
        try audit(app)
    }

    // MARK: - Recipes

    func testRecipesSortFilterAndSearch() throws {
        let app = launch("recipes")
        waitForGrid(app)
        expectCall("recipe_query kind=browse q= sort=availability cursor=-", in: app)
        keepScreenshot(app, "food-recipes-\(device)")
        try audit(app) { self.launch("recipes", arguments: FentonHomeApp.ax5) }

        for id in ["fab.sort", "fab.filter", "fab.search"] { assertTarget(element(id, in: app)) }

        // Sort.
        element("fab.sort", in: app).tap()
        XCTAssertTrue(app.navigationBars["Sort Recipes"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["filterSheet.apply"].isEnabled, "Apply waits for a change")
        element("recipes.sort.alphabetical", in: app).tap()
        XCTAssertTrue(element("recipes.sort.alphabetical", in: app).isSelected)
        sleep(1)
        keepScreenshot(app, "food-recipes-sort-\(device)")
        // The AX5 page lets the audit waive the stock Form button's iPad Dynamic Type false positive on
        // "Reset to Defaults" (FentonHomeApp.audit, ax5Page).
        try audit(app, presenter: element("fab.sort", in: app)) { self.openSortSheet(self.launch("recipes", arguments: FentonHomeApp.ax5)) }
        app.buttons["filterSheet.apply"].tap()
        expectCall("recipe_query kind=browse q= sort=alphabetical", in: app)
        XCTAssertTrue(element("fab.sort", in: app).isSelected, "an applied sort marks the button")

        // Filter.
        element("fab.filter", in: app).tap()
        XCTAssertTrue(app.navigationBars["Filter Recipes"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("recipes.filter.horizon", in: app).isEnabled, "the horizon waits for the toggle")
        element("recipes.filter.expiringOnly", in: app).switches.firstMatch.tap()
        let horizon = element("recipes.filter.horizon", in: app)
        XCTAssertTrue(horizon.wait(for: \.isEnabled, toEqual: true, timeout: 5), "the toggle enables the horizon")
        horizon.buttons["30 Days"].tap()
        XCTAssertTrue(app.staticTexts["Use ingredients expiring within the next month."].waitForExistence(timeout: 5),
                      "the footer explains the chosen horizon")
        sleep(1)
        keepScreenshot(app, "food-recipes-filter-\(device)")
        try audit(app, presenter: element("fab.filter", in: app)) { self.openFilterSheet(self.launch("recipes", arguments: FentonHomeApp.ax5)) }
        app.buttons["filterSheet.apply"].tap()
        expectCall("recipe_query kind=browse q= sort=alphabetical", in: app)
        XCTAssertTrue(element("fab.filter", in: app).wait(for: \.isSelected, toEqual: true, timeout: 5), "applied filters mark the button")

        // Search.
        element("fab.search", in: app).tap()
        let field = element("fab.search.field", in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("zzz")
        XCTAssertTrue(element("recipes.empty", in: app).waitForExistence(timeout: 10))
        expectCall("recipe_hydration query=zzz", in: app)
        element("fab.search.close", in: app).tap()
        XCTAssertFalse(field.exists)
    }

    /// The Sort sheet with a changed choice (so Reset to Defaults shows), scrolled until `reveal` is on screen,
    /// for an audit and its AX5 comparison page.
    private func openSortSheet(_ app: XCUIApplication, reveal: String = "Reset to Defaults") -> XCUIApplication {
        waitForGrid(app)
        element("fab.sort", in: app).tap()
        XCTAssertTrue(app.buttons["filterSheet.apply"].waitForExistence(timeout: 5))
        let alphabetical = element("recipes.sort.alphabetical", in: app)
        let sheet = app.collectionViews.firstMatch
        // At AX5 the row starts below the fold, and the Form only creates rows on screen.
        for _ in 0..<6 where !(alphabetical.exists && alphabetical.isHittable) { sheet.swipeUp() }
        alphabetical.tap()
        if reveal == "Sort By" {
            for _ in 0..<6 { sheet.swipeDown() }
            sleep(1)
        } else {
            scroll(to: reveal, in: app, sheet: sheet)
        }
        return app
    }

    /// The Filter sheet with expiring-only on (so Reset to Defaults shows), scrolled until `reveal` is on screen.
    private func openFilterSheet(_ app: XCUIApplication, reveal: String = "Reset to Defaults") -> XCUIApplication {
        waitForGrid(app)
        element("fab.filter", in: app).tap()
        XCTAssertTrue(app.buttons["filterSheet.apply"].waitForExistence(timeout: 5))
        let toggle = element("recipes.filter.expiringOnly", in: app).switches.firstMatch
        let sheet = app.collectionViews.firstMatch
        for _ in 0..<6 where !(toggle.exists && toggle.isHittable) { sheet.swipeUp() }
        toggle.tap()
        scroll(to: reveal, in: app, sheet: sheet)
        return app
    }

    /// Logs Reset to Defaults' frame against the sheet and window (evidence for the FilterSheet audit findings).
    private func logResetFrame(_ moment: String, in app: XCUIApplication) {
        let reset = app.buttons["Reset to Defaults"]
        let sheet = app.collectionViews.firstMatch
        print("FOODDIAG reset \(moment): exists=\(reset.exists) hittable=\(reset.exists && reset.isHittable) "
              + "frame=\(reset.exists ? reset.frame : .zero) sheet=\(sheet.frame) window=\(app.windows.firstMatch.frame) "
              + "keyboard=\(app.keyboards.firstMatch.exists)")
    }

    /// Scrolls the sheet until the text or button labeled `label` is on screen, so the AX5 comparison page can
    /// measure it (the Form only creates rows on screen).
    private func scroll(to label: String, in app: XCUIApplication, sheet: XCUIElement) {
        let target = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        for _ in 0..<8 where !(target.exists && target.isHittable) { sheet.swipeUp() }
        // One more so the row clears the sheet's bottom edge: a row cut by the edge reads as clipped text with
        // unsupported Dynamic Type. Headers stay put so the AX5 page still shows them.
        if !["Ranking Strength", "Sort By"].contains(label) { sheet.swipeUp() }
        sleep(1)
    }

    /// The Sort sheet alone, with the AX5 comparison page (as FloatingActionsJourneyTests does for its sheet).
    func testSortSheetPassesAccessibilityAudit() throws {
        // Top (the Sort By header), then scrolled to Reset to Defaults: each AX5 page shows what it measures.
        for reveal in ["Sort By", "Reset to Defaults"] {
            let app = openSortSheet(launch("recipes"), reveal: reveal)
            keepScreenshot(app, "food-recipes-sort-\(device)")
            try audit(app, presenter: element("fab.sort", in: app)) {
                self.openSortSheet(self.launch("recipes", arguments: FentonHomeApp.ax5), reveal: reveal)
            }
        }
    }

    /// The Filter sheet alone, with the AX5 comparison page.
    func testFilterSheetPassesAccessibilityAudit() throws {
        // The Ranking Strength section (scrolled to its last row, so no row is cut by the sheet's edge; the AX5
        // page shows the header it measures), then Reset to Defaults.
        for (reveal, ax5Reveal) in [("Reset to Defaults", "Reset to Defaults"), ("Expiry Weight", "Ranking Strength")] {
            let app = openFilterSheet(launch("recipes"), reveal: reveal)
            keepScreenshot(app, "food-recipes-filter-\(device)")
            logResetFrame("filter \(reveal)", in: app)
            try audit(app, presenter: element("fab.filter", in: app)) {
                let large = self.openFilterSheet(self.launch("recipes", arguments: FentonHomeApp.ax5), reveal: ax5Reveal)
                self.logResetFrame("filter AX5 \(ax5Reveal)", in: large)
                self.keepScreenshot(large, "food-recipes-filter-\(self.device)-ax5-\(ax5Reveal == "Reset to Defaults" ? "reset" : "ranking")")
                return large
            }
        }
    }

    func testRecipesErrorAndEmpty() throws {
        let failing = launch("recipes", mode: "error")
        XCTAssertTrue(element("recipes.error", in: failing).waitForExistence(timeout: 15))
        assertTarget(element("recipes.retry", in: failing))
        keepScreenshot(failing, "food-recipes-error-\(device)")
        try audit(failing)

        let empty = launch("recipes", mode: "empty")
        XCTAssertTrue(element("recipes.empty", in: empty).waitForExistence(timeout: 15))
        keepScreenshot(empty, "food-recipes-empty-\(device)")
        try audit(empty)
    }

    func testRecipesLoadMoreOnScroll() {
        let app = launch("recipes")
        waitForGrid(app)
        let last = element("recipes.card.120", in: app)
        let grid = element("recipes.grid", in: app)
        for _ in 0..<100 where !last.exists { grid.swipeUp(velocity: .fast) }
        XCTAssertTrue(last.exists, "infinite scroll stopped early")
        expectCall("recipe_query kind=browse q= sort=availability cursor=100", in: app)
    }

    // MARK: - Detail

    func testRecipeDetailTabsAndGroceries() throws {
        let app = launch("recipes")
        waitForGrid(app)
        element("recipes.card.6", in: app).tap()
        XCTAssertTrue(element("recipe.tabs", in: app).waitForExistence(timeout: 10))
        expectCall("recipe_detail recipe_id=6", in: app)
        sleep(1)
        let split = element("recipe.pane", in: app).exists
        let frame = app.windows.firstMatch.frame
        if FentonHomeApp.family == .iPad || frame.width <= frame.height {
            // Unfolded Duo landscape may split; iPad splits exactly in landscape; portrait never does.
            XCTAssertEqual(split, frame.width > frame.height, "the pane shows only where a split is allowed")
        }
        keepScreenshot(app, "food-recipe-general-\(device)")
        try audit(app)

        let tabs = element("recipe.tabs", in: app)
        tabs.buttons["Ingredients"].tap()
        XCTAssertTrue(element("recipe.ingredient.0", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(element("recipe.ingredient.1", in: app).value as? String, "Not on hand", "missing lemons read as not on hand")
        XCTAssertEqual(element("recipe.ingredient.0", in: app).value as? String, "On hand")
        // Audit before scrolling: rows scrolled half under the sheet's edge measure ~1.1:1.
        sleep(1)
        keepScreenshot(app, "food-recipe-ingredients-\(device)")
        try audit(app)
        let add = element("recipe.grocery.add", in: app)
        reveal(add, in: app, swiping: element("recipe.scroll", in: app))
        assertTarget(add)
        // Owner, 2026-10-16: "Add to Grocery List", with what it does under it.
        XCTAssertEqual(add.label, "Add to Grocery List")
        XCTAssertTrue(app.staticTexts["Adds the missing ingredients for this recipe to your shopping list."].exists,
                      "The button's description is missing")
        add.tap()
        expectCall("recipe_grocery_add recipe_id=6 selections=1,4", in: app)
        XCTAssertTrue(element("recipe.grocery.added", in: app).waitForExistence(timeout: 10))

        tabs.buttons["Instructions"].tap()
        XCTAssertTrue(app.staticTexts["Heat the oven to 425°F and zest the lemons."].waitForExistence(timeout: 5))
        keepScreenshot(app, "food-recipe-instructions-\(device)")
        try audit(app)
    }

    /// Owner, 2026-10-16: a recipe opens full screen (the other sheets size to their content), and Instructions that fit
    /// sit in the vertical centre of the sheet.
    func testRecipeIsFullScreenAndInstructionsAreCentred() throws {
        let app = launch("recipes")
        waitForGrid(app)
        element("recipes.card.6", in: app).tap()
        let tabs = element("recipe.tabs", in: app)
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        sleep(1)
        if !element("recipe.pane", in: app).exists {
            // A sheet: its section bar sits at the bottom of the window, which a half-height sheet would not.
            XCTAssertGreaterThan(tabs.frame.maxY, app.windows.firstMatch.frame.height * 0.85, "The recipe sheet is not full height")
        }
        tabs.buttons["Instructions"].tap()
        let first = app.staticTexts["Heat the oven to 425°F and zest the lemons."]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        sleep(1)
        let scroll = element("recipe.scroll", in: app)
        let last = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Roast for 40 minutes'")).firstMatch
        XCTAssertTrue(last.exists)
        let top = first.frame.minY
        let bottom = last.frame.maxY
        let contentMid = (top + bottom) / 2
        // Short instructions sit around the scroll view's middle, not at its top.
        XCTAssertEqual(contentMid, scroll.frame.midY, accuracy: scroll.frame.height * 0.2,
                       "Instructions are not vertically centred (content \(top)-\(bottom), sheet \(scroll.frame))")
        XCTAssertGreaterThan(top - scroll.frame.minY, 60, "Instructions start at the top of the sheet")
        keepScreenshot(app, "food-recipe-instructions-centred-\(device)")
    }

    func testCookidooRecipeLinksOut() throws {
        let app = launch("recipes")
        waitForGrid(app)
        element("recipes.card.1", in: app).tap()
        XCTAssertTrue(element("recipe.tabs", in: app).waitForExistence(timeout: 10))
        element("recipe.tabs", in: app).buttons["Instructions"].tap()
        XCTAssertTrue(element("recipe.openCookidoo", in: app).waitForExistence(timeout: 5))
        assertTarget(element("recipe.openCookidoo", in: app))
        keepScreenshot(app, "food-recipe-cookidoo-\(device)")
        try audit(app)
    }

    func testRecipeDetailAtAX5() throws {
        let app = launch("recipes", arguments: FentonHomeApp.ax5)
        waitForGrid(app)
        keepScreenshot(app, "food-recipes-\(device)-ax5")
        try audit(app)
        element("recipes.card.6", in: app).tap()
        XCTAssertTrue(element("recipe.tabs", in: app).waitForExistence(timeout: 10))
        sleep(1)
        keepScreenshot(app, "food-recipe-general-\(device)-ax5")
        try audit(app)
    }

    // MARK: - Poses

    /// Landscape on iPad and the iPhone Duo: the hub goes to two columns and an open recipe fills the trailing
    /// half where a split is allowed (unfolded Duo, iPad); the folded Duo keeps the sheet.
    func testLandscapeSplit() throws {
        guard FentonHomeApp.family != .iPhone else { throw XCTSkip("iPhone is portrait-only") }
        XCUIDevice.shared.orientation = .landscapeLeft
        let hub = launch("hub")
        XCTAssertTrue(element("food.suggestion.1", in: hub).waitForExistence(timeout: 15))
        sleep(1)
        keepScreenshot(hub, "food-hub-\(device)-landscape")
        try audit(hub)

        let app = launch("recipes")
        waitForGrid(app)
        keepScreenshot(app, "food-recipes-\(device)-landscape")
        element("recipes.card.6", in: app).tap()
        XCTAssertTrue(element("recipe.tabs", in: app).waitForExistence(timeout: 10))
        sleep(1)
        let window = app.windows.firstMatch.frame
        if element("recipe.pane", in: app).exists {
            XCTAssertTrue(element("recipes.card.11", in: app).isHittable, "the grid stays usable beside the pane")
            XCTAssertTrue(element("recipes.card.6", in: app).isSelected)
            element("recipe.close", in: app).tap()
            XCTAssertFalse(element("recipe.pane", in: app).waitForExistence(timeout: 2))
            element("recipes.card.6", in: app).tap()
            XCTAssertTrue(element("recipe.pane", in: app).waitForExistence(timeout: 5))
        } else {
            XCTAssertNotEqual(FentonHomeApp.family, .iPad, "iPad landscape (\(window)) must split")
            XCTAssertTrue(element("recipe.done", in: app).exists)
        }
        sleep(1)
        keepScreenshot(app, "food-recipe-general-\(device)-landscape")
        try audit(app)
    }

    // MARK: - Live

    /// Signs in with the runner's long-lived token and opens a Food page (`FENTON_OPEN_FOOD`). Skips without one.
    private func launchLive(_ route: String, fixtures: Bool = false) throws -> XCUIApplication {
        let environment = ProcessInfo.processInfo.environment
        guard let token = environment["FENTON_HASS_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_FENTON_HASS_TOKEN to check the live EverShelf recipe calls")
        }
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_UITEST_RESET"] = "1"
        app.launchEnvironment["FENTON_HASS_TOKEN"] = token
        if let server = environment["FENTON_HASS_SERVER"] { app.launchEnvironment["FENTON_HASS_SERVER"] = server }
        app.launchEnvironment["FENTON_OPEN_FOOD"] = route
        app.launchEnvironment["FENTON_FOOD_DEBUG"] = "1"
        if fixtures { app.launchEnvironment["FENTON_FOOD_FIXTURES"] = "1" }
        app.launch()
        return app
    }

    private func first(_ prefix: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }

    /// Live server: suggestions load, a suggestion opens a real detail with ingredients and instructions.
    /// Never taps "Add Missing Ingredients to Groceries".
    func testLiveSuggestionsAndDetail() throws {
        let app = try launchLive("hub")
        let suggestion = first("food.suggestion.", in: app)
        XCTAssertTrue(suggestion.waitForExistence(timeout: 45), "No live suggestions")
        XCTAssertFalse(element("food.suggestions.error", in: app).exists)
        sleep(2)
        keepScreenshot(app, "food-live-hub-\(device)")
        suggestion.tap()
        XCTAssertTrue(element("recipe.tabs", in: app).waitForExistence(timeout: 30), "Recipe detail did not open")
        XCTAssertFalse(element("recipe.error", in: app).waitForExistence(timeout: 3), "Live recipe detail failed")
        sleep(2)
        keepScreenshot(app, "food-live-recipe-general-\(device)")
        let tabs = element("recipe.tabs", in: app)
        let ingredients = tabs.buttons["Ingredients"]
        diagnose("before Ingredients", app: app, tabs: tabs, segment: ingredients)
        ingredients.tap()
        sleep(2)
        diagnose("after Ingredients", app: app, tabs: tabs, segment: ingredients)
        keepScreenshot(app, "food-live-recipe-ingredients-\(device)")
        XCTAssertTrue(first("recipe.ingredient.", in: app).waitForExistence(timeout: 30), "No live ingredients")
        element("recipe.tabs", in: app).buttons["Instructions"].tap()
        sleep(1)
        keepScreenshot(app, "food-live-recipe-instructions-\(device)")
    }

    /// Logs the tab picker's state and the hierarchy around a tap (iPad live-sheet investigation, 2026-10-12).
    private func diagnose(_ moment: String, app: XCUIApplication, tabs: XCUIElement, segment: XCUIElement) {
        let count = app.descendants(matching: .any).matching(identifier: "recipe.tabs").count
        let marker = app.staticTexts["recipe.debug"]
        print("FOODDIAG \(moment): pickers=\(count) tabs.frame=\(tabs.frame) segment.exists=\(segment.exists) "
              + "hittable=\(segment.exists && segment.isHittable) frame=\(segment.frame) selected=\(segment.isSelected) "
              + "marker=\(marker.exists ? marker.label : "none")")
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "hierarchy \(moment)"
        tree.lifetime = .keepAlways
        add(tree)
        print("FOODDIAG-TREE \(moment) BEGIN\n\(app.debugDescription)\nFOODDIAG-TREE END")
    }

    /// The signed-in app (Home, tabs, live entity updates) with fixture recipes: the recipe sheet switches tabs.
    /// Separates live recipe data from the signed-in app when the live iPad sheet ignored taps (2026-10-12).
    func testSignedInFixtureSheetSwitchesTabs() throws {
        let app = try launchLive("hub", fixtures: true)
        let suggestion = element("food.suggestion.2", in: app)
        XCTAssertTrue(suggestion.waitForExistence(timeout: 45))
        suggestion.tap()
        let tabs = element("recipe.tabs", in: app)
        XCTAssertTrue(tabs.waitForExistence(timeout: 15), "Recipe sheet did not open")
        sleep(2)
        let ingredients = tabs.buttons["Ingredients"]
        diagnose("signed-in fixture before", app: app, tabs: tabs, segment: ingredients)
        ingredients.tap()
        sleep(2)
        diagnose("signed-in fixture after", app: app, tabs: tabs, segment: ingredients)
        XCTAssertTrue(element("recipe.ingredient.0", in: app).waitForExistence(timeout: 10),
                      "In the signed-in app the fixture recipe sheet did not switch to Ingredients")
    }

    /// Live server: the Recipes grid's first browse page loads.
    func testLiveRecipesGrid() throws {
        let app = try launchLive("recipes")
        let card = first("recipes.card.", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 45), "No live recipes")
        XCTAssertFalse(element("recipes.error", in: app).exists)
        sleep(2)
        keepScreenshot(app, "food-live-recipes-\(device)")
        // A live recipe opened from the grid switches tabs too (compare the hub's sheet).
        card.tap()
        let tabs = element("recipe.tabs", in: app)
        XCTAssertTrue(tabs.waitForExistence(timeout: 30), "Recipe detail did not open from the grid")
        sleep(2)
        let ingredients = tabs.buttons["Ingredients"]
        diagnose("grid before Ingredients", app: app, tabs: tabs, segment: ingredients)
        ingredients.tap()
        sleep(2)
        diagnose("grid after Ingredients", app: app, tabs: tabs, segment: ingredients)
        XCTAssertTrue(first("recipe.ingredient.", in: app).waitForExistence(timeout: 30), "No live ingredients from the grid")
    }
}
