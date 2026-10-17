import Foundation
import HassCore
@testable import HassUI
import SwiftUI
import Testing

/// The grocery button's copy (owner, 2026-10-16), the Food tiles' colour families and the recipe detail's tabs.
@MainActor
struct FoodCopyTests {
    @Test func groceryButtonAndItsDescriptionUseTheOwnersWording() {
        #expect(GroceryAction.title == "Add to Grocery List")
        #expect(GroceryAction.explanation == "Adds the missing ingredients for this recipe to your shopping list.")
    }

    @Test func eachSpaceTakesItsOwnFamilyAndUnknownLocationsFallBackToFood() {
        #expect(FoodFamilies.family(forLocation: "dispensa") == .pantry)
        #expect(FoodFamilies.family(forLocation: "frigo") == .fridge)
        #expect(FoodFamilies.family(forLocation: "freezer") == .freezer)
        #expect(FoodFamilies.family(forLocation: "spice_rack") == .spiceRack)
        #expect(FoodFamilies.family(forLocation: "cabinet") == .cabinet)
        #expect(FoodFamilies.family(forLocation: "elsewhere") == .food)
        let families = FoodConfig.spaces.map { FoodFamilies.family(forLocation: $0.location) }
        #expect(Set(families).count == FoodConfig.spaces.count, "every space has its own colour")
    }

    @Test func theRecipeDetailRendersLoadedOnEveryTab() async {
        let models = FoodModels(service: FixtureRecipeService(delay: .zero))
        let model = models.detailModel(for: FoodFixtures.catalog[5])
        model.load()
        await model.settle()
        for tab in RecipeDetailModel.Tab.allCases {
            model.tab = tab
            let view = NavigationStack { RecipeDetailContent(model: model) }
                .frame(width: 402, height: 874)
                .environment(FoodFixtures.store())
            #expect(ImageRenderer(content: view).cgImage != nil, "\(tab)")
        }
    }
}
