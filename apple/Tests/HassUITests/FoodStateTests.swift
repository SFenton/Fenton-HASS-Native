import Foundation
import HassCore
@testable import HassUI
import SwiftUI
import Testing

/// A recipe service whose answers each test scripts: failures, partial results, paging and hydration polls.
@MainActor
final class ScriptedRecipeService: RecipeServing {
    var browsePages: [Result<RecipeBrowsePage, any Error>] = []
    var hydrations: [Result<RecipeHydration, any Error>] = []
    var detailResult: Result<RecipeDetail, any Error> = .success(FoodFixtures.detail(id: 2))
    var groceryResult: Result<RecipeGroceryResult, any Error> = .success(RecipeGroceryResult(success: true, backend: .init(added: 2)))
    /// While set, browse calls wait for ``release()``.
    var holdBrowse = false
    private var held: [CheckedContinuation<Void, Never>] = []
    private(set) var hydrationCalls: [String?] = []

    func recommendations(limit: Int) async throws -> [RecipeCard] { Array(FoodFixtures.catalog.prefix(limit)) }

    func browse(_ criteria: RecipeBrowseCriteria, cursor: String?) async throws -> RecipeBrowsePage {
        if holdBrowse { await withCheckedContinuation { held.append($0) } }
        guard !browsePages.isEmpty else { return RecipeBrowsePage(items: []) }
        return try browsePages.removeFirst().get()
    }

    func release() {
        holdBrowse = false
        held.forEach { $0.resume() }
        held = []
    }

    func hydrate(_ criteria: RecipeBrowseCriteria, searchId: String?) async throws -> RecipeHydration {
        hydrationCalls.append(searchId)
        guard !hydrations.isEmpty else { return RecipeHydration(searchId: "", status: "complete") }
        return try hydrations.removeFirst().get()
    }

    func detail(recipeId: Int) async throws -> RecipeDetail { try detailResult.get() }

    func addToGroceries(recipeId: Int, ingredients: [RecipeDetail.Ingredient], idempotencyKey: String) async throws -> RecipeGroceryResult {
        try groceryResult.get()
    }
}

struct PlainFailure: LocalizedError {
    var errorDescription: String? { "" }
}

/// Model states the journeys cannot reach (failures, paging, hydration polls) and hosted renders of each.
@MainActor
struct FoodStateTests {
    func render(_ view: some View, width: CGFloat = 402, height: CGFloat = 874, size: DynamicTypeSize = .large) -> CGImage? {
        ImageRenderer(content: view.frame(width: width, height: height).dynamicTypeSize(size).environment(FoodFixtures.store())).cgImage
    }

    private var cards: [RecipeCard] { FoodFixtures.catalog }

    // MARK: - Recipes

    @Test func nextPageFailureShowsRetryAndRetries() async {
        let service = ScriptedRecipeService()
        service.browsePages = [
            .success(RecipeBrowsePage(items: Array(cards.prefix(10)), nextCursor: "10", hasMore: true)),
            .failure(PlainFailure()),
            .success(RecipeBrowsePage(items: Array(cards[10..<20]))),
        ]
        let models = FoodModels(service: service)
        let collection = models.collection
        collection.debounce = .zero
        collection.appear()
        await collection.settle()
        collection.loadNextPage()
        await collection.settle()
        #expect(collection.nextPageFailed)
        #expect(render(RecipeGrid(collection: collection, selectedId: 1) { _ in }) != nil)
        collection.retryNextPage()
        await collection.settle()
        #expect(!collection.nextPageFailed)
        #expect(collection.items.count == 20)
        #expect(collection.announcement.contains("10 more recipes loaded"))
    }

    @Test func nextPageLoadingShowsProgress() async {
        let service = ScriptedRecipeService()
        service.browsePages = [
            .success(RecipeBrowsePage(items: Array(cards.prefix(10)), nextCursor: "10", hasMore: true)),
            .success(RecipeBrowsePage(items: Array(cards[10..<12]))),
        ]
        let models = FoodModels(service: service)
        models.collection.appear()
        await models.collection.settle()
        service.holdBrowse = true
        models.collection.loadNextPage()
        await Task.yield()
        #expect(models.collection.nextPageLoading)
        #expect(render(RecipeGrid(collection: models.collection, selectedId: nil) { _ in }) != nil)
        service.release()
        await models.collection.settle()
        #expect(models.collection.items.count == 12)
    }

    @Test func hydrationPollsUntilCompleteAndStopsOnFailure() async {
        let service = ScriptedRecipeService()
        service.browsePages = [.success(RecipeBrowsePage(items: Array(cards.prefix(2))))]
        service.hydrations = [
            .success(RecipeHydration(searchId: "s1", status: "running", nextPollMilliseconds: 0, newItems: [cards[50]])),
            .success(RecipeHydration(searchId: "s1", status: "complete", newItems: [cards[51]])),
        ]
        let collection = FoodModels(service: service).collection
        collection.debounce = .zero
        collection.hydrationSettle = .zero
        collection.searchText = "lemon"
        await collection.settle()
        await collection.settle()
        #expect(service.hydrationCalls == [nil, "s1"])
        #expect(!collection.hydrating)
        #expect(collection.announcement.contains("hydrated"))

        let failing = ScriptedRecipeService()
        failing.browsePages = [.success(RecipeBrowsePage(items: []))]
        failing.hydrations = [.failure(PlainFailure())]
        let other = FoodModels(service: failing).collection
        other.debounce = .zero
        other.hydrationSettle = .zero
        other.searchText = "soup"
        await other.settle()
        await other.settle()
        #expect(!other.hydrating)
    }

    @Test func splitScreenShowsThePaneAndSheetsRender() async {
        let models = FoodModels(service: FixtureRecipeService(delay: .zero))
        models.collection.appear()
        await models.collection.settle()
        let landscape = WindowMetrics(size: CGSize(width: 1180, height: 820), isRegularWidth: true)
        let split = NavigationStack { RecipesScreen(models: models, window: landscape, selected: cards[5]) }
        #expect(render(split, width: 1180, height: 820) != nil)
        #expect(render(NavigationStack { RecipesScreen(models: models, selected: cards[5]) }) != nil)
        #expect(render(NavigationStack { RecipesScreen(models: FoodModels()) }) != nil)
        for kind in [RecipesScreen.ControlSheet.sort, .filter] {
            #expect(kind.id == kind.rawValue)
            #expect(render(RecipeControlSheet(kind: kind, collection: models.collection)) != nil)
        }
    }

    // MARK: - Hub and routes

    @Test func hubSplitsInLandscapeAndShowsFailure() async {
        let models = FoodModels(service: FixtureRecipeService(mode: .error, delay: .zero))
        models.suggestions.load()
        await models.suggestions.settle()
        #expect(models.suggestions.phase == .failed)
        let landscape = WindowMetrics(size: CGSize(width: 1180, height: 820), isRegularWidth: true)
        #expect(render(NavigationStack { FoodHubScreen(models: models, window: landscape) }, width: 1180, height: 820) != nil)
    }

    @Test func carouselPagesWithVoiceOver() {
        #expect(SuggestedRecipesCarousel.adjusted(nil, .increment, pageCount: 5) == 1)
        #expect(SuggestedRecipesCarousel.adjusted(4, .increment, pageCount: 5) == 4)
        #expect(SuggestedRecipesCarousel.adjusted(2, .decrement, pageCount: 5) == 1)
        #expect(SuggestedRecipesCarousel.adjusted(0, .decrement, pageCount: 5) == 0)
    }

    @Test func detailTabBarRendersEverySelection() {
        for tab in RecipeDetailModel.Tab.allCases {
            #expect(render(DetailTabBar(selection: .constant(tab)), height: 60) != nil)
            #expect(render(DetailTabBar(selection: .constant(tab)), height: 200, size: .accessibility5) != nil)
        }
    }

    @Test func percentSliderStepsByFive() {
        #expect(PercentSliderRow.adjusted(25, .increment) == 30)
        #expect(PercentSliderRow.adjusted(100, .increment) == 100)
        #expect(PercentSliderRow.adjusted(5, .decrement) == 0)
        #expect(PercentSliderRow.adjusted(0, .decrement) == 0)
    }

    @Test func galleryRendersItsRoutes() {
        #expect(render(FoodGallery()) != nil)
        #expect(render(FoodGallery(), size: .accessibility5) != nil)
    }

    @Test func carouselPlaceholders() {
        let loading = FoodModels(service: FixtureRecipeService(mode: .slow))
        #expect(render(SuggestedRecipesCarousel(model: loading.suggestions) { _ in }) != nil)
    }

    @Test func routesBuildTheirPages() {
        let models = FoodModels(service: FixtureRecipeService(delay: .zero))
        for route in [FoodRoute.hub, .recipes, .inventory(location: nil), .inventory(location: "frigo")] {
            #expect(render(NavigationStack { FoodNavigation.destination(route, models: models) }) != nil)
        }
        #expect(FoodNavigation.inventoryTitle(nil) == "All Food")
        #expect(FoodNavigation.inventoryTitle("frigo") == "Fridge")
        #expect(FoodNavigation.inventoryTitle("garage") == "Food")
        #expect(render(NavigationStack { Text("Food").foodNavigation(service: FixtureRecipeService()) }) != nil)
    }

    // MARK: - Detail

    @Test func detailFailuresRender() async {
        let unsupported = ScriptedRecipeService()
        unsupported.detailResult = .failure(RecipeServiceFailure(unsupported: true, message: "nope"))
        let model = RecipeDetailModel(recipe: cards[1], service: unsupported)
        model.load()
        await model.settle()
        #expect(model.phase == .failed(message: RecipeDetailModel.unsupportedMessage, unsupported: true))
        #expect(render(RecipeDetailSheet(model: model)) != nil)

        let plain = ScriptedRecipeService()
        plain.detailResult = .failure(PlainFailure())
        let other = RecipeDetailModel(recipe: cards[1], service: plain)
        other.load()
        await other.settle()
        #expect(other.phase == .failed(message: "Unable to load recipe details.", unsupported: false))
        #expect(render(RecipeDetailPane(model: other) {}, width: 590) != nil)
        #expect(RecipeDetailModel.Tab.allCases.map(\.symbol) == ["info.circle", "checklist", "frying.pan"])
    }

    @Test func groceryOutcomesRender() async {
        let cases: [(Result<RecipeGroceryResult, any Error>, String)] = [
            (.success(RecipeGroceryResult(success: true, backend: .init(added: 2))), "added"),
            (.success(RecipeGroceryResult(success: false, backend: .init(failed: 2))), "failed"),
            (.failure(RecipeServiceFailure(unsupported: true, message: "x")), RecipeGroceryPolicy.unsupportedMessage),
            (.failure(RecipeServiceFailure(unsupported: false, message: "Server said no")), "Server said no"),
            (.failure(PlainFailure()), "Unable to add missing ingredients to groceries."),
        ]
        for (result, expected) in cases {
            let service = ScriptedRecipeService()
            service.groceryResult = result
            let model = RecipeDetailModel(recipe: cards[1], service: service, cached: FoodFixtures.detail(id: 2))
            model.tab = .ingredients
            model.addMissingToGroceries()
            #expect(model.grocery == .adding)
            #expect(render(RecipeDetailSheet(model: model)) != nil)
            await model.settle()
            switch model.grocery {
            case .added: #expect(expected == "added")
            case let .failed(message): #expect(expected == "failed" || message == expected)
            default: Issue.record("grocery stayed \(model.grocery)")
            }
            #expect(render(RecipeDetailSheet(model: model)) != nil)
        }
    }

    @Test func sparseDetailsRenderTheirEmptyStates() {
        var bare = FoodFixtures.detail(id: 2)
        bare.ingredients = []
        bare.ingredientsTruncated = true
        bare.capabilities.instructions = .externalLink
        bare.instructions = .init()
        bare.source.canonicalURL = nil
        var sparse = FoodFixtures.detail(id: 2)
        sparse.capabilities.ingredients = .namesOnly
        sparse.ingredients[1].optional = true
        sparse.instructions = .init(available: true, groups: [
            .init(key: "a", label: "Sauce", steps: [.init(key: "1", number: 1, text: "Stir.")]),
            .init(key: "b", label: nil, steps: [.init(key: "2", number: 2, text: "Serve.")]),
        ], truncated: true)
        var none = FoodFixtures.detail(id: 2)
        none.capabilities.instructions = .none
        for detail in [bare, sparse, none] {
            let model = RecipeDetailModel(recipe: cards[1], service: nil, cached: detail)
            for tab in RecipeDetailModel.Tab.allCases {
                model.tab = tab
                #expect(render(RecipeDetailSheet(model: model)) != nil)
            }
        }
    }
}
