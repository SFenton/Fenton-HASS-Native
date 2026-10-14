import HassCore
import HassDesign
import SwiftUI

/// All recipes: search, sort, filter and an endlessly loading grid (web `RecipesPage` + `RecipeFloatingActions`).
///
/// Search, Sort and Filter are the shared floating actions (`.agents/patterns/floating-actions.md`), as on the
/// web. Where a split is allowed (iPad and unfolded iPhone Duo landscape) an open recipe fills the trailing
/// half; elsewhere it opens as a sheet.
struct RecipesScreen: View {
    let models: FoodModels
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var window = WindowMetrics()
    @State private var selected: RecipeCard?
    @State private var detail: RecipeDetailModel?
    @State private var sheet: ControlSheet?
    @State private var searchExpanded = false

    enum ControlSheet: String, Identifiable {
        case sort, filter
        var id: String { rawValue }
    }

    /// - Parameters:
    ///   - window: Initial window metrics (hosted tests; the reader replaces them on screen).
    ///   - selected: A recipe to open at once (hosted tests).
    init(models: FoodModels, window: WindowMetrics = WindowMetrics(), selected: RecipeCard? = nil) {
        self.models = models
        _window = State(initialValue: window)
        _selected = State(initialValue: selected)
        _detail = State(initialValue: selected.map(models.detailModel(for:)))
    }

    private var collection: RecipeCollectionModel { models.collection }

    private var split: Bool {
        guard let size = window.size else { return false }
        return SplitPolicy.allowsSplit(size: size, isRegularWidth: horizontalSizeClass == .regular || window.isRegularWidth)
    }

    var body: some View {
        @Bindable var collection = collection
        HStack(spacing: 0) {
            results
                .frame(maxWidth: .infinity)
                .floatingActionBar(
                    [
                        FloatingAction(id: "sort", title: "Sort", symbol: "arrow.up.arrow.down", showsTitle: false, isActive: collection.sortActive) { sheet = .sort },
                        FloatingAction(id: "filter", title: "Filter", symbol: "line.3.horizontal.decrease", showsTitle: false, isActive: collection.filterActive) { sheet = .filter },
                    ],
                    search: FloatingSearch(text: $collection.searchText, isExpanded: $searchExpanded, prompt: "Search recipes")
                )
            if split, let detail {
                RecipeDetailPane(model: detail) { close() }
                    .frame(maxWidth: .infinity)
                    // Reduce Motion: the pane fades in instead of sliding (HIG Motion).
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing))
            }
        }
        .background { WindowMetricsReader(metrics: $window) }
        .navigationTitle("Recipes")
        .sheet(item: $sheet) { RecipeControlSheet(kind: $0, collection: collection) }
        .sheet(item: sheetRecipe) { _ in
            if let detail { RecipeDetailSheet(model: detail) }
        }
        .onAppear {
            collection.appear()
            if !collection.searchText.isEmpty { searchExpanded = true }
        }
        .onChange(of: collection.announcement) { _, text in announce(text) }
        .animation(.snappy, value: split && detail != nil)
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        switch collection.phase {
        case .idle, .loading:
            ProgressView("Loading recipes")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("recipes.loading")
        case .failed:
            ContentUnavailableView {
                Label("Unable to Load Recipes", systemImage: "exclamationmark.triangle")
            } actions: {
                Button { collection.reload() } label: {
                    Text("Retry").frame(minWidth: 88, minHeight: HassTokens.minTarget)
                }
                    .buttonStyle(.borderedProminent)
                    .tint(FoodStyle.action)
                    .accessibilityIdentifier("recipes.retry")
            }
            // A container keeps the Retry button's own identifier (an outer identifier overrides children's).
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("recipes.error")
        case .loaded where collection.items.isEmpty:
            // Not ContentUnavailableView: it caps its text size and clipped the title on the folded iPhone Duo's
            // outer panel (AX audit, 2026-10-12). A scrolling stack scales and wraps fully.
            ScrollView {
                VStack(spacing: HassTokens.Spacing.m) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(HassTokens.Ink.secondary)
                        .accessibilityHidden(true)
                    Text("No Recipes Found")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(HassTokens.Ink.primary)
                        .accessibilityAddTraits(.isHeader)
                    Text(collection.appliedQuery.isEmpty
                        ? "No recipes matched the current filters."
                        : "Try a different search or loosen the recipe filters.")
                        .font(.body)
                        .foregroundStyle(HassTokens.Ink.secondary)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(HassTokens.Spacing.xl)
                .padding(.top, HassTokens.Spacing.xl * 2)
            }
            .accessibilityIdentifier("recipes.empty")
        case .loaded:
            RecipeGrid(collection: collection, selectedId: split ? selected?.id : nil) { open($0) }
        }
    }

    // MARK: - Selection

    /// The sheet's item: only while no split shows the recipe inline. When a fold or rotation removes the
    /// split, an open recipe moves into the sheet.
    private var sheetRecipe: Binding<RecipeCard?> {
        Binding(
            get: { split ? nil : selected },
            set: { if $0 == nil, !split { close() } }
        )
    }

    private func open(_ recipe: RecipeCard) {
        guard recipe.id != selected?.id else { return }
        selected = recipe
        detail = models.detailModel(for: recipe)
    }

    private func close() {
        selected = nil
        detail = nil
    }

    private func announce(_ text: String) {
        guard !text.isEmpty else { return }
        #if os(iOS)
        UIAccessibility.post(notification: .announcement, argument: text)
        #endif
    }
}

// MARK: - Grid

/// The recipe card grid with infinite loading (web `RecipeGrid`): 2+ columns (1+ at accessibility sizes).
struct RecipeGrid: View {
    let collection: RecipeCollectionModel
    var selectedId: Int?
    var onOpen: (RecipeCard) -> Void
    @State private var width: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Columns for a width: 160 pt cards, at least two (web). At accessibility text sizes cards are twice
    /// as wide and a phone shows one column, so titles wrap whole words instead of clipping.
    static func columnCount(width: CGFloat, accessibilitySize: Bool) -> Int {
        let metrics = DynamicGridMetrics(width: max(width, 1), minCellWidth: accessibilitySize ? 320 : 160, maxColumns: 8, spacing: HassTokens.Spacing.m)
        return accessibilitySize ? metrics.columns : max(2, metrics.columns)
    }

    var body: some View {
        let count = Self.columnCount(width: width, accessibilitySize: dynamicTypeSize.isAccessibilitySize)
        let columns = Array(repeating: GridItem(.flexible(), spacing: HassTokens.Spacing.m, alignment: .top), count: count)
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: HassTokens.Spacing.m) {
                ForEach(collection.items, id: \.dedupeKey) { recipe in
                    ImageCard(
                        title: recipe.title, subtitle: recipe.coverageText, imageURL: recipe.cardImageURL,
                        fallbackImageURL: recipe.imageURL, placeholderSymbol: "fork.knife", accessibilityHint: "Opens recipe details"
                    ) { onOpen(recipe) }
                    .overlay {
                        if recipe.id == selectedId {
                            RoundedRectangle(cornerRadius: HassTokens.Radius.media, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 3)
                        }
                    }
                    .accessibilityAddTraits(recipe.id == selectedId ? .isSelected : [])
                    .accessibilityIdentifier("recipes.card.\(recipe.id)")
                    .onAppear { collection.itemAppeared(recipe) }
                }
            }
            .padding(.horizontal, HassTokens.Spacing.l)
            .padding(.vertical, HassTokens.Spacing.m)
            footer
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width - 2 * HassTokens.Spacing.l }) { width = $0 }
        .scrollTelemetry("Recipes")
        .accessibilityIdentifier("recipes.grid")
    }

    @ViewBuilder
    private var footer: some View {
        if collection.nextPageFailed {
            VStack(spacing: HassTokens.Spacing.s) {
                Text("Unable to load more recipes.").foregroundStyle(HassTokens.Ink.secondary)
                Button("Retry") { collection.retryNextPage() }
                    .buttonStyle(.bordered)
                    .frame(minHeight: HassTokens.minTarget)
                    .accessibilityIdentifier("recipes.nextPage.retry")
            }
            .padding(.bottom, HassTokens.Spacing.xl)
        } else if collection.nextPageLoading || collection.hydrating {
            ProgressView(collection.hydrating ? "Finding more recipes" : "Loading more recipes")
                .padding(.bottom, HassTokens.Spacing.xl)
                .accessibilityIdentifier("recipes.nextPage.loading")
        }
    }
}

// MARK: - Sort and filter

/// The Sort or Filter sheet for the grid's current criteria.
struct RecipeControlSheet: View {
    let kind: RecipesScreen.ControlSheet
    let collection: RecipeCollectionModel

    var body: some View {
        switch kind {
        case .sort: RecipeSortSheet(current: collection.sort) { collection.apply(sort: $0) }
        case .filter: RecipeFilterSheet(current: collection.filters, sortedAlphabetically: collection.sort == .alphabetical) { collection.apply(filters: $0) }
        }
    }
}

/// Sort Recipes (web `RecipeSortSheet`).
struct RecipeSortSheet: View {
    @State private var draft: RecipeSort
    var current: RecipeSort
    var onApply: (RecipeSort) -> Void

    init(current: RecipeSort, onApply: @escaping (RecipeSort) -> Void) {
        _draft = State(initialValue: current)
        self.current = current
        self.onApply = onApply
    }

    var body: some View {
        FilterSheet(title: "Sort Recipes", canApply: draft != current, canReset: draft != .availability,
                    onApply: { onApply(draft) }, onReset: { draft = .availability }) {
            FilterSection("Sort By") {
                ForEach(RecipeSort.allCases) { option in
                    FilterOptionRow(title: option.title, subtitle: option.subtitle, isSelected: draft == option) { draft = option }
                        .accessibilityIdentifier("recipes.sort.\(option.rawValue)")
                }
            }
        }
    }
}

/// Filter Recipes (web `RecipeFilterSheet`).
struct RecipeFilterSheet: View {
    @State private var draft: RecipeFilters
    var current: RecipeFilters
    var sortedAlphabetically: Bool
    var onApply: (RecipeFilters) -> Void

    init(current: RecipeFilters, sortedAlphabetically: Bool, onApply: @escaping (RecipeFilters) -> Void) {
        _draft = State(initialValue: current)
        self.current = current
        self.sortedAlphabetically = sortedAlphabetically
        self.onApply = onApply
    }

    var body: some View {
        FilterSheet(title: "Filter Recipes", canApply: draft != current, canReset: draft != .defaults,
                    onApply: { onApply(draft) }, onReset: { draft = .defaults }) {
            Section {
                PercentSliderRow("Minimum Ingredients Available", value: $draft.minimumCoverage, identifier: "recipes.filter.coverage")
            } header: {
                // Styled like FilterSection's header (the system header measured 3.1:1 on the sheet).
                Text("Ingredient Coverage")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HassTokens.Ink.primary)
                    .textCase(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            } footer: {
                Text("Only show recipes where at least this percentage of required ingredients is currently available.")
                    .foregroundStyle(HassTokens.Ink.secondary) // The system footer gray measured 3.3:1 on iPad.
            }
            FilterSection("Expiring Ingredients") {
                Toggle(isOn: $draft.expiringOnly) {
                    Label("Use expiring ingredients only", systemImage: "clock")
                }
                .frame(minHeight: HassTokens.minTarget)
                .accessibilityIdentifier("recipes.filter.expiringOnly")
                ForEach(RecipeFilters.horizons, id: \.self) { days in
                    let horizon = RecipeFilters.horizon(days)
                    FilterOptionRow(title: horizon.title, subtitle: horizon.subtitle, isSelected: draft.expiringWithinDays == days) {
                        draft.expiringWithinDays = days
                    }
                    .disabled(!draft.expiringOnly)
                    .opacity(draft.expiringOnly ? 1 : 0.5)
                    .accessibilityIdentifier("recipes.filter.days\(days)")
                }
            }
            Section {
                PercentSliderRow("Availability Weight", value: $draft.availabilityWeight, identifier: "recipes.filter.availabilityWeight")
                    .disabled(sortedAlphabetically)
                PercentSliderRow("Expiry Weight", value: $draft.expiryWeight, identifier: "recipes.filter.expiryWeight")
                    .disabled(sortedAlphabetically)
            } header: {
                // Styled like FilterSection's header (the system header measured 3.1:1 on the sheet).
                Text("Ranking Strength")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HassTokens.Ink.primary)
                    .textCase(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            } footer: {
                Text(sortedAlphabetically
                    ? "Weights are unavailable while recipes are sorted alphabetically."
                    : "Tune how strongly available and expiring ingredients influence ranked recipe results.")
                    .foregroundStyle(HassTokens.Ink.secondary)
            }
        }
        .hassSheet()
    }
}

/// A labelled 0...100 slider in steps of 5 that shows and speaks its value (web `RangeField`).
struct PercentSliderRow: View {
    var title: String
    @Binding var value: Double
    var identifier: String
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, value: Binding<Double>, identifier: String) {
        self.title = title
        _value = value
        self.identifier = identifier
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(HassTokens.Ink.primary)
                Spacer(minLength: HassTokens.Spacing.s)
                Text("\(Int(value))%").monospacedDigit().foregroundStyle(HassTokens.Ink.secondary)
            }
            Slider(value: $value, in: 0...100, step: 5)
        }
        .padding(.vertical, HassTokens.Spacing.xs)
        .opacity(isEnabled ? 1 : 0.5)
        // One adjustable element for the row: the visible title and value belong to it (hiding them while only
        // the slider spoke flagged "potentially inaccessible text" on the folded iPhone Duo).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(Int(value)) percent")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            value = Self.adjusted(value, direction)
        }
        .accessibilityIdentifier(identifier)
    }

    /// The value after a VoiceOver swipe: steps of 5 within 0...100.
    static func adjusted(_ value: Double, _ direction: AccessibilityAdjustmentDirection) -> Double {
        switch direction {
        case .increment: min(100, value + 5)
        case .decrement: max(0, value - 5)
        @unknown default: value
        }
    }
}
