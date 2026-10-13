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
        .navigationDestination(item: $pushed) { FoodNavigation.destination($0, models: models) }
        .sheet(item: $openDetail) { RecipeDetailSheet(model: $0) }
    }

    // MARK: - Sections

    @ViewBuilder
    private var recipeSections: some View {
        FoodSection("Suggested Recipes") {
            SuggestedRecipesCarousel(model: models.suggestions, clipsPages: split) { open($0) }
        }
        GlassTile(title: "All Recipes", symbol: FoodSymbols.symbol(for: "mdi:book-open-page-variant"),
                  tint: Self.tint(FoodConfig.allRecipesTint), isActive: true, kind: .navigate) { pushed = .recipes }
            .accessibilityIdentifier("food.allRecipes")
    }

    @ViewBuilder
    private var inventorySections: some View {
        let state: (String) -> EntityState? = { store?.entity($0).state }
        FoodSection("All Food") {
            DynamicGridLayout(minCellWidth: 150, maxColumns: 4) {
                GlassTile(
                    title: "All Food", subtitle: FoodConfig.allFoodSubtitle(state: state),
                    symbol: FoodSymbols.symbol(for: "mdi:food-variant"), tint: Self.tint(FoodConfig.allFoodTint),
                    isActive: true, kind: .navigate
                ) { pushed = .inventory(.allFood) }
                .accessibilityIdentifier("food.allFood")
            }
        }
        FoodSection("Food Spaces") {
            DynamicGridLayout(minCellWidth: 150, maxColumns: 4) {
                ForEach(FoodConfig.spaces) { space in
                    GlassTile(
                        title: space.title, subtitle: FoodConfig.spaceSubtitle(space, state: state),
                        symbol: FoodSymbols.symbol(for: space.icon), tint: Self.tint((space.red, space.green, space.blue)),
                        isActive: true, kind: .navigate
                    ) {
                        if let inventory = FoodInventoryScreen.space(forLocation: space.location) { pushed = .inventory(inventory) }
                    }
                    .accessibilityIdentifier("food.space.\(space.location)")
                }
            }
        }
    }

    private func open(_ recipe: RecipeCard) {
        openDetail = models.detailModel(for: recipe)
    }

    static func tint(_ rgb: (red: Double, green: Double, blue: Double)) -> Color {
        Color(red: rgb.red / 255, green: rgb.green / 255, blue: rgb.blue / 255)
    }
}

// MARK: - Pieces

/// A titled section on the Food pages (web `SectionHeader`).
struct FoodSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(HassTokens.Ink.primary)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Colors the Food pages share.
enum FoodStyle {
    /// Fill for prominent buttons. White on the app accent (#42A9FE) is 2.5:1 and fails the contrast audit;
    /// this darker blue keeps the same hue at about 5.8:1. Fold into a shared `HassTokens` action tint once
    /// other pages need one.
    static let action = Color(red: 0.04, green: 0.39, blue: 0.78)
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
