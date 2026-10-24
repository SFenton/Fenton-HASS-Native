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
            gatedResults
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
        .task {
            collection.appear()
            if !collection.searchText.isEmpty { searchExpanded = true }
        }
        .onChange(of: collection.announcement) { _, text in announce(text) }
        .motionSafeAnimation(MotionTokens.standard, reduced: MotionTokens.quick, value: split && detail != nil)
    }

    // MARK: - Results

    /// The results wait for the first page like the web's page load gate (spinner fades in, stays at least a second, fades
    /// out, then the grid fades in); later searches, sorts and filters use the quicker results timings. The floating actions
    /// stay outside, so a search keeps its field and keyboard while its results reload.
    private var gatedResults: some View {
        let isReady = collection.phase == .loaded || collection.phase == .failed
        return ContentGate(page: "Recipes", isReady: isReady, timing: .page, reloadTiming: .results, label: "Loading Recipes") {
            results
        }
    }

    @ViewBuilder
    private var results: some View {
        switch collection.phase {
        case .idle, .loading:
            // The previous results stay under the gate while it fades them out for a reload; nothing yet on the first load.
            if collection.items.isEmpty {
                Color.clear
            } else {
                RecipeGrid(collection: collection, selectedId: split ? selected?.id : nil) { open($0) }
            }
        case .failed:
            ContentUnavailableView {
                Label("Unable to Load Recipes", systemImage: "exclamationmark.triangle")
            } actions: {
                // The page's one primary action while nothing loaded (direction G, Controls: Primary buttons), as wide
                // as its label.
                PrimaryButton("Retry") { collection.reload() }
                    .fixedSize(horizontal: true, vertical: false)
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
                        .font(.title2.bold())
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

    /// The line under the large title that names the order: "Sorted by Ingredients Available".
    static func sortSummary(_ sort: RecipeSort) -> String {
        sort == .alphabetical ? "Sorted Alphabetically" : "Sorted by \(sort.title)"
    }

    var body: some View {
        let count = Self.columnCount(width: width, accessibilitySize: dynamicTypeSize.isAccessibilitySize)
        let columns = Array(repeating: GridItem(.flexible(), spacing: HassTokens.Spacing.m, alignment: .top), count: count)
        ScrollView {
            // The order under the large title (mockup n6 Recipes: "Sorted by Ingredients Available").
            Text(Self.sortSummary(collection.sort))
                .foregroundStyle(HassTokens.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, HassTokens.Spacing.l)
                .accessibilityIdentifier("recipes.sortedBy")
            LazyVGrid(columns: columns, alignment: .leading, spacing: HassTokens.Spacing.m) {
                ForEach(collection.items, id: \.dedupeKey) { recipe in
                    ImageCard(
                        title: recipe.title, subtitle: recipe.coverageText, imageURL: recipe.cardImageURL,
                        fallbackImageURL: recipe.imageURL, placeholderSymbol: "fork.knife", accessibilityHint: "Opens recipe details"
                    ) { onOpen(recipe) }
                    .overlay {
                        if recipe.id == selectedId {
                            RoundedRectangle(cornerRadius: ImageCard.cornerRadius, style: .continuous)
                                .strokeBorder(HassTokens.Ink.action, lineWidth: 3)
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
                    .tint(HassTokens.Ink.action)
                    .frame(minHeight: HassTokens.minTarget)
                    .accessibilityIdentifier("recipes.nextPage.retry")
            }
            .padding(.bottom, HassTokens.Spacing.xl)
        } else if collection.nextPageLoading || collection.hydrating {
            ProgressView(collection.hydrating ? "Finding more recipes" : "Loading more recipes")
                .progressViewStyle(.arc(.compact))
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

/// Filter Recipes (web `RecipeFilterSheet`), in direction G's sheet form (mockup n5 Filter Recipes): inset sections
/// under 15 Semibold secondary headers, the expiry horizon as a segmented control under its toggle, and footers that
/// explain each section.
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
        FilterSheet(title: "Filter Recipes", subtitle: draft.activeSummary, canApply: draft != current, canReset: draft != .defaults,
                    onApply: { onApply(draft) }, onReset: { draft = .defaults }) {
            Section {
                PercentSliderRow("Minimum Ingredients Available", value: $draft.minimumCoverage, identifier: "recipes.filter.coverage")
            } header: {
                RecipeSectionHeader("Ingredient Coverage")
            } footer: {
                FormFooter("Only show recipes where at least this percentage of required ingredients is available.")
            }
            Section {
                Toggle(isOn: $draft.expiringOnly) {
                    Label("Expiring Ingredients Only", systemImage: "clock")
                }
                .frame(minHeight: HassTokens.minTarget)
                .accessibilityIdentifier("recipes.filter.expiringOnly")
                RecipeHorizonPicker(days: $draft.expiringWithinDays)
                    .disabled(!draft.expiringOnly)
            } header: {
                RecipeSectionHeader("Expiring Ingredients")
            } footer: {
                FormFooter(RecipeFilters.horizon(draft.expiringWithinDays).subtitle)
            }
            Section {
                PercentSliderRow("Availability Weight", value: $draft.availabilityWeight, identifier: "recipes.filter.availabilityWeight")
                    .disabled(sortedAlphabetically)
                PercentSliderRow("Expiry Weight", value: $draft.expiryWeight, identifier: "recipes.filter.expiryWeight")
                    .disabled(sortedAlphabetically)
            } header: {
                RecipeSectionHeader("Ranking Strength")
            } footer: {
                FormFooter(sortedAlphabetically
                    ? "Weights are unavailable while recipes are sorted alphabetically."
                    : "Tune how strongly available and expiring ingredients influence ranked recipe results.")
            }
        }
    }
}

/// The expiry horizon (7, 30 or 90 days): a segmented control, as direction G picks for two to four short options
/// (Controls: Choosing one option). At accessibility text sizes, where segments cannot grow, it is a pop-up menu that
/// names the choice (as ``ModalTabBar`` does).
private struct RecipeHorizonPicker: View {
    @Binding var days: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let picker = Picker("Expiring Within", selection: $days) {
            ForEach(RecipeFilters.horizons, id: \.self) { option in
                Text(RecipeFilters.horizon(option).title).tag(option)
            }
        }
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                picker
                    .pickerStyle(.menu)
                    .frame(minHeight: HassTokens.minTarget)
            } else {
                picker
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(minHeight: HassTokens.minTarget)
            }
        }
        // The system control dims itself while its toggle is off.
        .accessibilityIdentifier("recipes.filter.horizon")
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
