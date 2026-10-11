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
    @State private var openRecipe: RecipeCard?

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
        .accessibilityIdentifier("food.scroll")
        .navigationTitle("Food & Recipes")
        .onAppear { models.suggestions.appear() }
        .sheet(item: $openRecipe) { recipe in
            RecipeDetailSheet(model: models.detailModel(for: recipe))
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var recipeSections: some View {
        FoodSection("Suggested Recipes") {
            SuggestedRecipesCarousel(model: models.suggestions) { openRecipe = $0 }
        }
        NavigationLink(value: FoodRoute.recipes) {
            GlassTileLabel(title: "All Recipes", symbol: FoodSymbols.symbol(for: "mdi:book-open-page-variant"), tint: Self.tint(FoodConfig.allRecipesTint))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("food.allRecipes")
    }

    @ViewBuilder
    private var inventorySections: some View {
        let state: (String) -> EntityState? = { store?.entity($0).state }
        FoodSection("All Food") {
            DynamicGridLayout(minCellWidth: 150, maxColumns: 4) {
                NavigationLink(value: FoodRoute.inventory(location: nil)) {
                    GlassTileLabel(
                        title: "All Food", subtitle: FoodConfig.allFoodSubtitle(state: state),
                        symbol: FoodSymbols.symbol(for: "mdi:food-variant"), tint: Self.tint(FoodConfig.allFoodTint)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("food.allFood")
            }
        }
        FoodSection("Food Spaces") {
            DynamicGridLayout(minCellWidth: 150, maxColumns: 4) {
                ForEach(FoodConfig.spaces) { space in
                    NavigationLink(value: FoodRoute.inventory(location: space.location)) {
                        GlassTileLabel(
                            title: space.title, subtitle: FoodConfig.spaceSubtitle(space, state: state),
                            symbol: FoodSymbols.symbol(for: space.icon), tint: Self.tint((space.red, space.green, space.blue))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("food.space.\(space.location)")
                }
            }
        }
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

/// A navigation tile drawn like ``GlassTile`` for use as a `NavigationLink` label, so the link
/// keeps the system's push semantics.
struct GlassTileLabel: View {
    var title: String
    var subtitle: String?
    var symbol: String
    var tint: Color

    var body: some View {
        GlassTile(title: title, subtitle: subtitle, symbol: symbol, tint: tint, isActive: true, kind: .navigate) {}
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(subtitle ?? "")
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
