import HassCore
import HassDesign
import SwiftUI

/// Food & Recipes hub (web `FoodHubPage`). Spec: `.agents/pages/food/spec.md`.
///
/// Single column everywhere a split is not allowed; in iPad and unfolded iPhone Duo landscape the
/// recipes sections take the leading column and the inventory sections the trailing one.
struct FoodHubScreen: View {
    let models: FoodModels
    @Environment(EntityStore.self) private var store: EntityStore?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var window = WindowMetrics()
    /// The open recipe, as the sheet's item. Held here, not built in the sheet's closure: live entity updates
    /// re-render the hub, and a model rebuilt on each render reset the open recipe's tab (iPad, 2026-10-11).
    @State private var openDetail: RecipeDetailModel?
    /// The page a hub tile opened. Tiles are `GlassTile`s with their own action: a tile drawn with
    /// `.allowsHitTesting(false)` inside a `NavigationLink` label left the link nothing to tap on iPhone
    /// (`.agents/patterns/entity-tile.md`).
    @State private var pushed: FoodRoute?

    /// - Parameter window: Initial window metrics (hosted tests; the reader replaces them on screen).
    init(models: FoodModels, window: WindowMetrics = WindowMetrics()) {
        self.models = models
        _window = State(initialValue: window)
    }

    private var split: Bool {
        guard let size = window.size else { return false }
        return SplitPolicy.allowsSplit(size: size, isRegularWidth: horizontalSizeClass == .regular || window.isRegularWidth)
    }

    var body: some View {
        ScrollView {
            Group {
                if split {
                    HStack(alignment: .top, spacing: HassTokens.Spacing.xl) {
                        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) { recipeSections }
                            .frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) { inventorySections }
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
                        recipeSections
                        inventorySections
                    }
                }
            }
            .padding(.horizontal, HassTokens.Spacing.l)
            .padding(.vertical, HassTokens.Spacing.m)
        }
        .background { WindowMetricsReader(metrics: $window) }
        .scrollTelemetry("Food")
        .accessibilityIdentifier("food.scroll")
        .navigationTitle("Food & Recipes")
        .onAppear { models.suggestions.appear() }
        .navigationDestination(item: $pushed) { FoodNavigation.destination($0, models: models).pageChrome() }
        .sheet(item: $openDetail) { RecipeDetailSheet(model: $0) }
    }

    // MARK: - Sections

    @ViewBuilder
    private var recipeSections: some View {
        // The carousel draws its own header: "Page 1 of 5" follows its scroll position.
        SuggestedRecipesCarousel(title: "Suggested Recipes", model: models.suggestions, clipsPages: split) { open($0) }
        FoodLinkRow(title: "All Recipes", symbol: FoodSymbols.symbol(for: "mdi:book-open-page-variant")) { pushed = .recipes }
            .accessibilityIdentifier("food.allRecipes")
    }

    @ViewBuilder
    private var inventorySections: some View {
        let state: (String) -> EntityState? = { store?.entity($0).state }
        FoodSection("All Food") {
            FoodLinkRow(
                title: "All Food", subtitle: FoodConfig.allFoodSubtitle(state: state),
                symbol: FoodSymbols.symbol(for: "mdi:food-variant")
            ) { pushed = .inventory(.allFood) }
            .accessibilityIdentifier("food.allFood")
        }
        FoodSection("Food Spaces") {
            // Dark G tiles with neutral glyphs: storage spaces are places, which have no colour of their own
            // (direction G, Colour). Off faces, so the glyph stays an outline and nothing reads as "on".
            DynamicGridLayout(minCellWidth: 150, maxColumns: 4, equalRowHeights: true) {
                ForEach(FoodConfig.spaces) { space in
                    GlassTile(
                        title: space.title, subtitle: FoodConfig.spaceSubtitle(space, state: state),
                        symbol: FoodSymbols.symbol(for: space.icon), family: .neutral,
                        isActive: false, kind: .navigate
                    ) {
                        if let inventory = FoodInventoryScreen.space(forLocation: space.location) { pushed = .inventory(inventory) }
                    }
                    .accessibilityIdentifier("food.space.\(space.location)")
                }
            }
            .equalHeightTiles()
        }
    }

    private func open(_ recipe: RecipeCard) {
        openDetail = models.detailModel(for: recipe)
    }
}

// MARK: - Pieces

/// A titled section on the Food pages (web `SectionHeader`): a 20 Bold header over its content, with an optional
/// trailing detail in secondary ink ("Page 1 of 5" on Suggested Recipes).
struct FoodSection<Content: View>: View {
    var title: String
    var detail: String?
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            // The detail moves under the title at accessibility sizes, so neither is squeezed into a narrow column.
            let header = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: HassTokens.Spacing.xs))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.s))
            header {
                Text(title)
                    // Direction G, Type: section headers on pages are 20 Bold.
                    .font(.title3.bold())
                    .foregroundStyle(HassTokens.Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                if let detail {
                    Text(detail)
                        .foregroundStyle(HassTokens.Ink.secondary)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// SF Symbols for the Food pages' MDI icons.
///
/// Kept here rather than in ``SymbolMap`` while several page threads add rows there at once: a key added twice
/// to that dictionary literal traps at launch. Fold these into ``SymbolMap`` once the parallel ports land.
enum FoodSymbols {
    static let table: [String: String] = [
        "mdi:food-fork-drink": "fork.knife",
        "mdi:book-open-page-variant": "book",
        "mdi:food-variant": "carrot",
        "mdi:fridge": "refrigerator",
        "mdi:snowflake": "snowflake",
        "mdi:shaker-outline": "takeoutbag.and.cup.and.straw",
        "mdi:cupboard": "cabinet",
        "mdi:chef-hat": "frying.pan",
    ]

    /// The SF Symbol for an MDI name, falling back to ``SymbolMap``.
    static func symbol(for mdi: String) -> String { table[mdi] ?? SymbolMap.symbol(for: mdi) }
}
