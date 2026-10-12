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

    private func launch(_ route: String, mode: String? = nil, arguments: [String] = []) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "food"
        app.launchEnvironment["FENTON_GALLERY_ROUTE"] = route
        if let mode { app.launchEnvironment["FENTON_GALLERY_FOOD_MODE"] = mode }
        app.launchArguments += arguments
        app.launch()
        return app
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
        try FentonHomeApp.audit(app) { self.launch("hub", arguments: FentonHomeApp.ax5) }

        first.tap()
        XCTAssertTrue(element("recipe.tabs", in: app).waitForExistence(timeout: 10), "Recipe sheet did not open")
        expectCall("recipe_detail recipe_id=1", in: app)
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
        XCTAssertTrue(app.staticTexts["Coming in a later update."].exists)

        app = launch("hub")
        let allFood = element("food.allFood", in: app)
        XCTAssertTrue(allFood.waitForExistence(timeout: 15))
        reveal(allFood, in: app)
        allFood.tap()
        XCTAssertTrue(app.navigationBars["All Food"].waitForExistence(timeout: 10), "All Food did not open its page")
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
        try FentonHomeApp.audit(app)
    }

    // MARK: - Recipes

    func testRecipesSortFilterAndSearch() throws {
        let app = launch("recipes")
        waitForGrid(app)
        expectCall("recipe_query kind=browse q= sort=availability cursor=-", in: app)
        keepScreenshot(app, "food-recipes-\(device)")
        try FentonHomeApp.audit(app) { self.launch("recipes", arguments: FentonHomeApp.ax5) }

        for id in ["fab.sort", "fab.filter", "fab.search"] { assertTarget(element(id, in: app)) }

        // Sort.
        element("fab.sort", in: app).tap()
        XCTAssertTrue(app.navigationBars["Sort Recipes"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["filterSheet.apply"].isEnabled, "Apply waits for a change")
        element("recipes.sort.alphabetical", in: app).tap()
        XCTAssertTrue(element("recipes.sort.alphabetical", in: app).isSelected)
        sleep(1)
        keepScreenshot(app, "food-recipes-sort-\(device)")
        try FentonHomeApp.audit(app)
        app.buttons["filterSheet.apply"].tap()
        expectCall("recipe_query kind=browse q= sort=alphabetical", in: app)
        XCTAssertTrue(element("fab.sort", in: app).isSelected, "an applied sort marks the button")

        // Filter.
        element("fab.filter", in: app).tap()
        XCTAssertTrue(app.navigationBars["Filter Recipes"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("recipes.filter.days30", in: app).isEnabled, "horizons wait for the toggle")
        element("recipes.filter.expiringOnly", in: app).switches.firstMatch.tap()
        sleep(1)
        keepScreenshot(app, "food-recipes-filter-\(device)")
        try FentonHomeApp.audit(app)
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

    func testRecipesErrorAndEmpty() throws {
        let failing = launch("recipes", mode: "error")
        XCTAssertTrue(element("recipes.error", in: failing).waitForExistence(timeout: 15))
        assertTarget(element("recipes.retry", in: failing))
        keepScreenshot(failing, "food-recipes-error-\(device)")
        try FentonHomeApp.audit(failing)

        let empty = launch("recipes", mode: "empty")
        XCTAssertTrue(element("recipes.empty", in: empty).waitForExistence(timeout: 15))
        try FentonHomeApp.audit(empty)
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
        try FentonHomeApp.audit(app)

        let tabs = element("recipe.tabs", in: app)
        tabs.buttons["Ingredients"].tap()
        XCTAssertTrue(element("recipe.ingredient.0", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(element("recipe.ingredient.1", in: app).value as? String, "Not on hand", "missing lemons read as not on hand")
        XCTAssertEqual(element("recipe.ingredient.0", in: app).value as? String, "On hand")
        // Audit before scrolling: rows scrolled half under the sheet's edge measure ~1.1:1.
        sleep(1)
        keepScreenshot(app, "food-recipe-ingredients-\(device)")
        try FentonHomeApp.audit(app)
        let add = element("recipe.grocery.add", in: app)
        reveal(add, in: app, swiping: element("recipe.scroll", in: app))
        assertTarget(add)
        add.tap()
        expectCall("recipe_grocery_add recipe_id=6 selections=1,4", in: app)
        XCTAssertTrue(element("recipe.grocery.added", in: app).waitForExistence(timeout: 10))

        tabs.buttons["Instructions"].tap()
        XCTAssertTrue(app.staticTexts["Heat the oven to 425°F and zest the lemons."].waitForExistence(timeout: 5))
        keepScreenshot(app, "food-recipe-instructions-\(device)")
        try FentonHomeApp.audit(app)
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
        try FentonHomeApp.audit(app)
    }

    func testRecipeDetailAtAX5() throws {
        let app = launch("recipes", arguments: FentonHomeApp.ax5)
        waitForGrid(app)
        keepScreenshot(app, "food-recipes-\(device)-ax5")
        try FentonHomeApp.audit(app)
        element("recipes.card.6", in: app).tap()
        XCTAssertTrue(element("recipe.tabs", in: app).waitForExistence(timeout: 10))
        sleep(1)
        keepScreenshot(app, "food-recipe-general-\(device)-ax5")
        try FentonHomeApp.audit(app)
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
        try FentonHomeApp.audit(hub)

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
        try FentonHomeApp.audit(app)
    }

    // MARK: - Live

    /// Signs in with the runner's long-lived token and opens a Food page (`FENTON_OPEN_FOOD`). Skips without one.
    private func launchLive(_ route: String) throws -> XCUIApplication {
        let environment = ProcessInfo.processInfo.environment
        guard let token = environment["FENTON_HASS_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_FENTON_HASS_TOKEN to check the live EverShelf recipe calls")
        }
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_UITEST_RESET"] = "1"
        app.launchEnvironment["FENTON_HASS_TOKEN"] = token
        if let server = environment["FENTON_HASS_SERVER"] { app.launchEnvironment["FENTON_HASS_SERVER"] = server }
        app.launchEnvironment["FENTON_OPEN_FOOD"] = route
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
        element("recipe.tabs", in: app).buttons["Ingredients"].tap()
        sleep(2)
        keepScreenshot(app, "food-live-recipe-ingredients-\(device)")
        XCTAssertTrue(first("recipe.ingredient.", in: app).waitForExistence(timeout: 30), "No live ingredients")
        element("recipe.tabs", in: app).buttons["Instructions"].tap()
        sleep(1)
        keepScreenshot(app, "food-live-recipe-instructions-\(device)")
    }

    /// Live server: the Recipes grid's first browse page loads.
    func testLiveRecipesGrid() throws {
        let app = try launchLive("recipes")
        XCTAssertTrue(first("recipes.card.", in: app).waitForExistence(timeout: 45), "No live recipes")
        XCTAssertFalse(element("recipes.error", in: app).exists)
        sleep(2)
        keepScreenshot(app, "food-live-recipes-\(device)")
    }
}
