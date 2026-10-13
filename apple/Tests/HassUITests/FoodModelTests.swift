import Foundation
import HassCore
@testable import HassUI
import SwiftUI
import Testing

/// The Food pages' models against the gallery's fixture service.
@MainActor
struct FoodModelTests {
    func makeCollection(_ mode: FixtureRecipeService.Mode = .normal) -> (RecipeCollectionModel, FixtureRecipeService) {
        let service = FixtureRecipeService(mode: mode, delay: .zero)
        let models = FoodModels(service: service)
        models.collection.debounce = .zero
        models.collection.hydrationSettle = .zero
        return (models.collection, service)
    }

    @Test func firstAppearanceLoadsOnePageAndPagesOnScroll() async {
        let (collection, service) = makeCollection()
        collection.appear()
        #expect(collection.phase == .loading)
        await collection.settle()
        #expect(collection.phase == .loaded)
        #expect(collection.items.count == 50)
        #expect(collection.hasMore)
        #expect(collection.announcement == "120 recipes.")

        collection.itemAppeared(collection.items[10])
        #expect(!collection.nextPageLoading, "far from the end")
        collection.itemAppeared(collection.items[45])
        #expect(collection.nextPageLoading)
        await collection.settle()
        #expect(collection.items.count == 100)
        #expect(collection.announcement == "50 more recipes loaded; 100 total.")
        collection.loadNextPage()
        await collection.settle()
        #expect(collection.items.count == 120)
        #expect(!collection.hasMore)
        collection.loadNextPage()
        #expect(!collection.nextPageLoading, "nothing left")

        collection.appear()
        #expect(service.calls.count == 3, "a second appearance keeps the results")
    }

    @Test func searchDebouncesThenHydrates() async {
        let (collection, service) = makeCollection()
        collection.appear()
        await collection.settle()
        collection.searchText = "  Soup "
        await collection.settle()
        #expect(collection.appliedQuery == "Soup")
        #expect(collection.items.allSatisfy { $0.title.contains("Soup") })
        #expect(service.calls.contains("recipe_hydration query=Soup"))

        let count = service.calls.count
        collection.searchText = "Soup"
        await collection.settle()
        #expect(service.calls.count == count, "the same normalized query does not reload")

        collection.searchText = "zz"
        await collection.settle()
        #expect(collection.items.isEmpty)
        #expect(collection.announcement == "No recipes found.")
        #expect(!service.calls.contains("recipe_hydration query=zz"), "short queries skip hydration")
    }

    @Test func sortAndFiltersReload() async {
        let (collection, service) = makeCollection()
        collection.appear()
        await collection.settle()
        collection.apply(sort: .alphabetical)
        await collection.settle()
        #expect(collection.sortActive)
        #expect(service.lastCall.contains("sort=alphabetical"))
        #expect(collection.items.map(\.title) == collection.items.map(\.title).sorted())
        let calls = service.calls.count
        collection.apply(sort: .alphabetical)
        #expect(service.calls.count == calls)

        var filters = RecipeFilters.defaults
        filters.expiringOnly = true
        filters.expiringWithinDays = 7
        filters.minimumCoverage = 50
        collection.apply(filters: filters)
        await collection.settle()
        #expect(collection.filterActive)
        #expect(collection.criteria.expiringWithinDays == 7)
        #expect(collection.items.allSatisfy { $0.coverage >= 50 && ($0.soonestExpiryDays ?? 99) <= 7 })
        let filtered = service.calls.count
        collection.apply(filters: filters)
        #expect(service.calls.count == filtered, "the same filters do not reload")
    }

    @Test func failuresShowAndRetry() async {
        let (collection, _) = makeCollection(.error)
        collection.appear()
        await collection.settle()
        #expect(collection.phase == .failed)
        #expect(collection.announcement == "Unable to load recipes.")
        collection.reload()
        await collection.settle()
        #expect(collection.phase == .failed)
    }

    @Test func suggestionsLoadOnceUntilStale() async {
        let service = FixtureRecipeService(delay: .zero)
        let model = SuggestedRecipesModel()
        model.service = service
        model.appear()
        #expect(model.phase == .loading)
        await model.settle()
        #expect(model.phase == .ready)
        #expect(model.items.count == SuggestedRecipesModel.limit)
        model.appear()
        #expect(service.calls.count == 1)
        model.appear(now: .now.addingTimeInterval(SuggestedRecipesModel.staleAfter + 1))
        #expect(model.phase == .ready, "a stale refresh keeps the cards")
        await model.settle()
        #expect(service.calls.count == 2)

        let failing = SuggestedRecipesModel()
        failing.service = FixtureRecipeService(mode: .error, delay: .zero)
        failing.appear()
        await failing.settle()
        #expect(failing.phase == .failed)
    }

    @Test func detailLoadsCachesAndAddsGroceries() async {
        let service = FixtureRecipeService(delay: .zero)
        let models = FoodModels(service: service)
        let card = FoodFixtures.catalog[1]
        let model = models.detailModel(for: card)
        #expect(model.phase == .loading)
        model.load()
        await model.settle()
        #expect(model.detail?.id == card.id)
        #expect(models.detailCache[card.id] != nil)
        #expect(models.detailModel(for: card).detail != nil, "reopening starts from the cache")

        #expect(model.groceryDisabledReason == nil)
        model.addMissingToGroceries()
        #expect(model.grocery == .adding)
        #expect(model.groceryDisabledReason == "Adding missing ingredients…")
        await model.settle()
        #expect(service.lastCall == "recipe_grocery_add recipe_id=\(card.id) selections=1,4")
        if case let .added(message) = model.grocery {
            #expect(message.hasPrefix("EverShelf: 2 added."))
        } else { Issue.record("expected added, got \(model.grocery)") }
        #expect(model.addedKeys.count == 2)
        #expect(model.groceryDisabledReason == nil, "the success message stays until the sheet closes")
    }

    @Test func detailFailuresKeepCachedContent() async {
        let failing = RecipeDetailModel(recipe: FoodFixtures.catalog[0], service: FixtureRecipeService(mode: .error, delay: .zero))
        failing.load()
        await failing.settle()
        #expect(failing.phase == .failed(message: "The fixture service is set to fail.", unsupported: false))

        let cached = RecipeDetailModel(recipe: FoodFixtures.catalog[0], service: FixtureRecipeService(mode: .error, delay: .zero),
                                       cached: FoodFixtures.detail(id: 1))
        cached.load()
        await cached.settle()
        #expect(cached.detail?.id == 1)
        #expect(RecipeDetailModel.Tab.allCases.map(\.title) == ["General", "Ingredients", "Instructions"])
    }

    @Test func carouselLayoutMatchesTheWeb() {
        #expect(SuggestedRecipesCarousel.layout(width: 370) == (2, 3))
        #expect(SuggestedRecipesCarousel.layout(width: 700) == (4, 3))
        #expect(SuggestedRecipesCarousel.layout(width: 1000) == (5, 2))
        #expect(SuggestedRecipesCarousel.layout(width: 5000).columns == 10)
        #expect(SuggestedRecipesCarousel.layout(width: 370, accessibilitySize: true) == (1, 2))
        #expect(RecipeGrid.columnCount(width: 370, accessibilitySize: false) == 2)
        #expect(RecipeGrid.columnCount(width: 100, accessibilitySize: false) == 2)
        #expect(RecipeGrid.columnCount(width: 370, accessibilitySize: true) == 1)
        #expect(RecipeGrid.columnCount(width: 1100, accessibilitySize: true) == 3)
        #expect(SuggestedRecipesCarousel.layout(width: 1000, accessibilitySize: true) == (2, 2))
        #expect(RecipeFilters.horizons.map { RecipeFilters.horizon($0).title } == ["7 Days", "30 Days", "90 Days"])
    }

    @Test func fixturesAreValid() {
        #expect(Set(FoodFixtures.catalog.map(\.dedupeKey)).count == 120)
        let detail = FoodFixtures.detail(id: 2)
        #expect(detail.ingredients.allSatisfy { $0.key.wholeMatch(of: #/^ri:\d+:[a-f0-9]{16}$/#) != nil })
        #expect(FoodFixtures.detail(id: 1).capabilities.instructions == .externalLink)
    }
}

/// Hosted renders of the Food pages from fixtures.
@MainActor
struct FoodViewTests {
    func render(_ view: some View, width: CGFloat = 402, height: CGFloat = 874, size: DynamicTypeSize = .large) -> CGImage? {
        ImageRenderer(content: view.frame(width: width, height: height).dynamicTypeSize(size)).cgImage
    }

    @Test func hubRendersAtEverySize() async {
        let models = FoodModels(service: FixtureRecipeService(delay: .zero))
        models.suggestions.load()
        await models.suggestions.settle()
        let hub = NavigationStack { FoodHubScreen(models: models) }.environment(FoodFixtures.store())
        #expect(render(hub) != nil)
        #expect(render(hub, width: 1180, height: 820) != nil)
        #expect(render(hub, size: .accessibility5) != nil)
    }

    @Test func recipesRendersEveryPhase() async {
        for mode in [FixtureRecipeService.Mode.normal, .empty, .error] {
            let models = FoodModels(service: FixtureRecipeService(mode: mode, delay: .zero))
            models.collection.appear()
            await models.collection.settle()
            #expect(render(NavigationStack { RecipesScreen(models: models) }) != nil)
            #expect(render(NavigationStack { RecipesScreen(models: models) }, size: .accessibility5) != nil)
        }
        let models = FoodModels(service: FixtureRecipeService(delay: .zero))
        #expect(render(RecipeSortSheet(current: .expiry) { _ in }) != nil)
        #expect(render(RecipeFilterSheet(current: .defaults, sortedAlphabetically: true) { _ in }) != nil)
        #expect(render(RecipeGrid(collection: models.collection, selectedId: nil) { _ in }) != nil)
    }

    @Test func detailRendersEveryTab() async {
        for id in [1, 2] {
            let model = RecipeDetailModel(recipe: FoodFixtures.catalog[id - 1], service: nil, cached: FoodFixtures.detail(id: id))
            for tab in RecipeDetailModel.Tab.allCases {
                model.tab = tab
                #expect(render(RecipeDetailSheet(model: model)) != nil)
                #expect(render(RecipeDetailPane(model: model) {}, width: 590, height: 820, size: .accessibility5) != nil)
            }
        }
        #expect(render(RecipeDetailSheet(model: RecipeDetailModel(recipe: FoodFixtures.catalog[0], service: nil))) != nil)
    }
}
