import Foundation
import HassCore
import Observation

// MARK: - Container

/// State for the Food pages, owned by the section's navigation stack (``FoodNavigation``) so the Recipes
/// results, search and filters survive leaving and re-entering the pages (web `useRecipeControls` is scoped
/// per route and survives navigation) and nothing reloads on reopen.
@MainActor
@Observable
final class FoodModels {
    /// The recipe service; set once the stack knows its connection.
    @ObservationIgnored var service: (any RecipeServing)? {
        didSet {
            collection.service = service
            suggestions.service = service
        }
    }

    let collection = RecipeCollectionModel()
    let suggestions = SuggestedRecipesModel()
    /// Details already loaded, shown at once when a recipe is reopened while a fresh copy loads.
    @ObservationIgnored var detailCache: [Int: RecipeDetail] = [:]

    init(service: (any RecipeServing)? = nil) {
        self.service = service
        collection.service = service
        suggestions.service = service
    }

    /// A detail model for `recipe`.
    func detailModel(for recipe: RecipeCard) -> RecipeDetailModel {
        RecipeDetailModel(recipe: recipe, service: service, cached: detailCache[recipe.id]) { [weak self] detail in
            self?.detailCache[detail.id] = detail
        }
    }
}

// MARK: - Suggested recipes

/// The Food hub's Suggested Recipes carousel (web `SuggestedRecipeCarousel`).
@MainActor
@Observable
final class SuggestedRecipesModel {
    enum Phase: Equatable { case idle, loading, ready, failed }

    private(set) var phase: Phase = .idle
    private(set) var items: [RecipeCard] = []
    @ObservationIgnored var service: (any RecipeServing)?
    @ObservationIgnored private var loadedAt: Date?
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Cards requested: five pages of the widest layout (web asks columns x rows x 5).
    static let limit = 40
    /// Suggestions older than this refresh quietly when the hub reappears.
    static let staleAfter: TimeInterval = 300

    /// Loads on first appearance; later appearances refresh in place only when stale, keeping the cards on screen.
    func appear(now: Date = .now) {
        guard task == nil else { return }
        if let loadedAt, now.timeIntervalSince(loadedAt) < Self.staleAfter { return }
        load()
    }

    /// Fetches suggestions. Existing cards stay visible until new ones arrive.
    func load() {
        guard let service else { return }
        if items.isEmpty { phase = .loading }
        task = Task { [weak self] in
            do {
                let cards = try await service.recommendations(limit: Self.limit)
                guard let self else { return }
                self.items = cards
                self.phase = .ready
                self.loadedAt = .now
            } catch {
                guard let self else { return }
                if self.items.isEmpty { self.phase = .failed }
            }
            self?.task = nil
        }
    }

    /// Waits for an in-flight load (tests).
    func settle() async { await task?.value }
}

// MARK: - Filters

/// The Filter sheet's values (web `RecipeFilterValues`).
struct RecipeFilters: Equatable, Sendable {
    var expiringOnly = false
    var expiringWithinDays = 7
    var minimumCoverage: Double = 0
    var availabilityWeight: Double = 100
    var expiryWeight: Double = 25

    /// Web `DEFAULT_RECIPE_FILTERS`.
    static let defaults = RecipeFilters()
    /// Expiry horizons offered (web `EXPIRY_HORIZONS`).
    static let horizons = [7, 30, 90]

    /// The horizon's title and description.
    static func horizon(_ days: Int) -> (title: String, subtitle: String) {
        switch days {
        case 7: ("7 Days", "Use ingredients expiring within the next week.")
        case 30: ("30 Days", "Use ingredients expiring within the next month.")
        default: ("90 Days", "Use ingredients expiring within the next three months.")
        }
    }
}

// MARK: - Recipes grid

/// The Recipes grid: criteria, paging and remote-catalog hydration (web `useRecipeControls` + `useRecipeCollection`).
@MainActor
@Observable
final class RecipeCollectionModel {
    enum Phase: Equatable { case idle, loading, loaded, failed }

    // MARK: Controls

    /// The search field. Changes reload after ``debounce``.
    var searchText = "" {
        didSet { if searchText != oldValue { scheduleSearch() } }
    }
    private(set) var sort: RecipeSort = .availability
    private(set) var filters = RecipeFilters.defaults
    private(set) var appliedQuery = ""

    var sortActive: Bool { sort != .availability }
    var filterActive: Bool { filters != .defaults }

    /// The query sent to the server.
    var criteria: RecipeBrowseCriteria {
        RecipeBrowseCriteria(
            query: appliedQuery, sort: sort, availabilityWeight: filters.availabilityWeight,
            expiryWeight: filters.expiryWeight, minimumCoverage: filters.minimumCoverage,
            expiringWithinDays: filters.expiringOnly ? filters.expiringWithinDays : nil
        )
    }

    // MARK: Results

    private(set) var phase: Phase = .idle
    private(set) var items: [RecipeCard] = []
    private(set) var hasMore = false
    private(set) var nextPageLoading = false
    private(set) var nextPageFailed = false
    private(set) var hydrating = false
    /// Polite announcement for VoiceOver (web live region).
    private(set) var announcement = ""

    // MARK: Plumbing

    @ObservationIgnored var service: (any RecipeServing)?
    @ObservationIgnored var debounce: Duration = .milliseconds(250)
    @ObservationIgnored var hydrationSettle: Duration = .milliseconds(600)
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var cursor: String?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var pageTask: Task<Void, Never>?
    @ObservationIgnored private var hydrationTask: Task<Void, Never>?

    /// Hydration starts for queries this long or longer (web `query.length < 3`).
    static let hydrationMinimumQuery = 3
    /// Items from the end that trigger the next page.
    static let prefetchDistance = 8

    // MARK: Intents

    /// First appearance loads; later appearances keep what is on screen.
    func appear() {
        if phase == .idle { reload() }
    }

    /// Applies a sort from the Sort sheet.
    func apply(sort newSort: RecipeSort) {
        guard newSort != sort else { return }
        sort = newSort
        reload()
    }

    /// Applies filters from the Filter sheet.
    func apply(filters newFilters: RecipeFilters) {
        guard newFilters != filters else { return }
        filters = newFilters
        reload()
    }

    /// Loads the first page for the current criteria, replacing the results.
    func reload() {
        generation += 1
        let current = generation
        [loadTask, pageTask, hydrationTask].forEach { $0?.cancel() }
        cursor = nil
        hasMore = false
        nextPageLoading = false
        nextPageFailed = false
        hydrating = false
        phase = .loading
        guard let service else { return }
        let criteria = criteria
        loadTask = Task { [weak self] in
            do {
                let page = try await service.browse(criteria, cursor: nil)
                guard let self, self.generation == current else { return }
                self.items = page.items
                self.cursor = page.nextCursor
                self.hasMore = page.hasMore && page.nextCursor != nil
                self.phase = .loaded
                self.announce(page.items.isEmpty ? "No recipes found." : "\(page.total) recipes.")
                self.startHydration(criteria, generation: current)
            } catch {
                guard let self, self.generation == current, !Task.isCancelled else { return }
                self.items = []
                self.phase = .failed
                self.announce("Unable to load recipes.")
            }
        }
    }

    /// Call as each card appears; near the end it loads the next page (web infinite scroll).
    func itemAppeared(_ item: RecipeCard) {
        guard let index = items.lastIndex(where: { $0.dedupeKey == item.dedupeKey }),
              index >= items.count - Self.prefetchDistance else { return }
        loadNextPage()
    }

    /// Loads the next page unless one is loading, failed, or there is none.
    func loadNextPage() {
        guard phase == .loaded, hasMore, !nextPageLoading, !nextPageFailed, let cursor, let service else { return }
        let current = generation
        let criteria = criteria
        nextPageLoading = true
        pageTask = Task { [weak self] in
            do {
                let page = try await service.browse(criteria, cursor: cursor)
                guard let self, self.generation == current else { return }
                let added = self.append(page.items)
                self.cursor = page.nextCursor
                self.hasMore = page.hasMore && page.nextCursor != nil
                self.nextPageLoading = false
                if added > 0 { self.announce("\(added) more recipes loaded; \(self.items.count) total.") }
            } catch {
                guard let self, self.generation == current, !Task.isCancelled else { return }
                self.nextPageLoading = false
                self.nextPageFailed = true
            }
        }
    }

    /// Retries a failed next page.
    func retryNextPage() {
        nextPageFailed = false
        loadNextPage()
    }

    /// Waits for in-flight work (tests).
    func settle() async {
        await searchTask?.value
        await loadTask?.value
        await pageTask?.value
        await hydrationTask?.value
    }

    // MARK: Private

    private func scheduleSearch() {
        searchTask?.cancel()
        let delay = debounce
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            let normalized = RecipeBrowseCriteria(query: self.searchText).normalizedQuery
            guard normalized != self.appliedQuery else { return }
            self.appliedQuery = normalized
            self.reload()
        }
    }

    /// Imports remote results for a search and appends those that pass the filters (web hydration effect).
    private func startHydration(_ criteria: RecipeBrowseCriteria, generation current: Int) {
        guard criteria.normalizedQuery.count >= Self.hydrationMinimumQuery, let service else { return }
        let settleDelay = hydrationSettle
        hydrationTask = Task { [weak self] in
            try? await Task.sleep(for: settleDelay)
            var searchId: String?
            while !Task.isCancelled {
                guard let self, self.generation == current else { return }
                self.hydrating = true
                let poll: RecipeHydration
                do {
                    poll = try await service.hydrate(criteria, searchId: searchId)
                } catch {
                    if self.generation == current { self.hydrating = false }
                    return
                }
                guard self.generation == current else { return }
                let added = self.append(poll.newItems.filter(criteria.matchesFilters))
                if added > 0 { self.announce("\(added) more recipes hydrated; \(self.items.count) total.") }
                if poll.isFailed || poll.isComplete {
                    self.hydrating = false
                    return
                }
                searchId = poll.searchId
                let wait = min(30_000, max(0, poll.nextPollMilliseconds ?? 1_000))
                try? await Task.sleep(for: .milliseconds(wait))
            }
        }
    }

    /// Appends cards not already shown; returns how many were added (web `appendUniqueRecipes`).
    @discardableResult
    private func append(_ incoming: [RecipeCard]) -> Int {
        var keys = Set(items.map(\.dedupeKey))
        let additions = incoming.filter { keys.insert($0.dedupeKey).inserted }
        if !additions.isEmpty { items += additions }
        return additions.count
    }

    private func announce(_ text: String) { announcement = text }
}

// MARK: - Detail

/// One open recipe: its detail and the grocery action (web `useRecipeDetailModalController`).
@MainActor
@Observable
final class RecipeDetailModel {
    enum Phase: Equatable {
        case loading
        case loaded(RecipeDetail)
        case failed(message: String, unsupported: Bool)
    }

    enum Grocery: Equatable {
        case idle
        case adding
        case added(message: String)
        case failed(message: String)
    }

    /// The detail sheet's tabs (web `RECIPE_DETAIL_TABS`).
    enum Tab: String, CaseIterable, Identifiable {
        case general, ingredients, instructions
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: "General"
            case .ingredients: "Ingredients"
            case .instructions: "Instructions"
            }
        }
        var symbol: String {
            switch self {
            case .general: "info.circle"
            case .ingredients: "checklist"
            case .instructions: "frying.pan"
            }
        }
    }

    let recipe: RecipeCard
    private(set) var phase: Phase
    private(set) var grocery: Grocery = .idle
    /// Ingredients this sheet already sent to groceries.
    private(set) var addedKeys: Set<String> = []
    var tab: Tab = .general

    @ObservationIgnored private let service: (any RecipeServing)?
    @ObservationIgnored private let onLoad: (RecipeDetail) -> Void
    @ObservationIgnored private var commandKey: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var groceryTask: Task<Void, Never>?

    /// The detail when loaded.
    var detail: RecipeDetail? { if case let .loaded(detail) = phase { detail } else { nil } }

    init(recipe: RecipeCard, service: (any RecipeServing)?, cached: RecipeDetail? = nil, onLoad: @escaping (RecipeDetail) -> Void = { _ in }) {
        self.recipe = recipe
        self.service = service
        self.onLoad = onLoad
        phase = cached.map(Phase.loaded) ?? .loading
    }

    /// Loads (or quietly refreshes) the detail.
    func load() {
        guard let service, task == nil else { return }
        let id = recipe.id
        task = Task { [weak self] in
            do {
                let detail = try await service.detail(recipeId: id)
                guard let self else { return }
                self.phase = .loaded(detail)
                self.onLoad(detail)
            } catch let failure as RecipeServiceFailure {
                self?.failIfEmpty(failure.unsupported ? Self.unsupportedMessage : failure.message, unsupported: failure.unsupported)
            } catch {
                self?.failIfEmpty(Self.message(error, fallback: "Unable to load recipe details."), unsupported: false)
            }
            self?.task = nil
        }
    }

    /// Why the grocery button is disabled, or nil.
    var groceryDisabledReason: String? {
        guard let detail else { return nil }
        if case .added = grocery { return nil }
        return RecipeGroceryPolicy.disabledReason(detail, loading: grocery == .adding, added: addedKeys)
    }

    /// Sends the effectively missing ingredients to the grocery list (web `addMissingIngredients`).
    func addMissingToGroceries() {
        guard let detail, let service, grocery != .adding, RecipeGroceryPolicy.disabledReason(detail, added: addedKeys) == nil else { return }
        let missing = RecipeGroceryPolicy.actionableMissing(detail, added: addedKeys)
        guard !missing.isEmpty, missing.count <= RecipeGroceryPolicy.maxSelections else { return }
        // Reused across retries so a repeated tap after a lost response is replayed, not doubled.
        let key = commandKey ?? RecipeServiceData.idempotencyKey(recipeId: detail.id)
        commandKey = key
        grocery = .adding
        groceryTask = Task { [weak self] in
            do {
                let result = try await service.addToGroceries(recipeId: detail.id, ingredients: missing, idempotencyKey: key)
                guard let self else { return }
                let feedback = RecipeGroceryPolicy.feedback(result)
                if result.backend.failed > 0 || result.backend.unresolved > 0 || feedback.success { self.commandKey = nil }
                if feedback.success {
                    self.addedKeys.formUnion(missing.map(\.key))
                    self.grocery = .added(message: feedback.message)
                } else {
                    self.grocery = .failed(message: feedback.message)
                }
            } catch let failure as RecipeServiceFailure {
                self?.grocery = .failed(message: failure.unsupported ? RecipeGroceryPolicy.unsupportedMessage : failure.message)
            } catch {
                self?.grocery = .failed(message: Self.message(error, fallback: "Unable to add missing ingredients to groceries."))
            }
        }
    }

    /// Waits for an in-flight load or grocery add (tests).
    func settle() async {
        await task?.value
        await groceryTask?.value
    }

    static let unsupportedMessage = "The installed EverShelf/ha-evershelf version does not support recipe details yet."

    private func failIfEmpty(_ message: String, unsupported: Bool) {
        if detail == nil { phase = .failed(message: message, unsupported: unsupported) }
    }

    private static func message(_ error: Error, fallback: String) -> String {
        let text = (error as? LocalizedError)?.errorDescription ?? ""
        return text.isEmpty ? fallback : text
    }
}
