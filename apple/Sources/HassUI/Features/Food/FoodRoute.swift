import HassCore
import SwiftUI

/// Pages in the Food area (web routes `food`, `recipes`, `all-food` and the five storage pages; routes.ts:15-22).
///
/// Any navigation stack that links to Food applies ``SwiftUI/View/foodNavigation(service:)`` once at its root
/// and pushes a route, e.g. `NavigationLink(value: FoodRoute.hub)`. Entry points (web): the Kitchen page's
/// Food tile and the Quick Links "Food & Recipes" tile.
public enum FoodRoute: Hashable, Sendable {
    /// Food & Recipes hub (web `FoodHubPage`).
    case hub
    /// All recipes (web `RecipesPage`).
    case recipes
    /// An inventory page: nil is All Food, otherwise an EverShelf location (`dispensa`, `frigo`, …).
    case inventory(location: String?)
}

public extension View {
    /// Registers the Food pages on this navigation stack and owns their state for the stack's lifetime.
    /// - Parameter service: Overrides the recipe service (gallery fixtures); by default the signed-in connection's.
    func foodNavigation(service: (any RecipeServing)? = nil) -> some View {
        modifier(FoodNavigation(serviceOverride: service))
    }
}

/// Implementation of ``SwiftUI/View/foodNavigation(service:)``.
struct FoodNavigation: ViewModifier {
    var serviceOverride: (any RecipeServing)?
    @Environment(HassConnection.self) private var connection: HassConnection?
    @State private var models = FoodModels()
    /// Debug builds: `FENTON_OPEN_FOOD=hub|recipes` opens that page at launch (signed-in journeys, live checks).
    @State private var launchRoute: FoodRoute? = Self.requestedLaunchRoute

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: FoodRoute.self, destination: destination)
            .navigationDestination(item: $launchRoute, destination: destination)
            .onAppear(perform: connect)
            .onChange(of: connection.map(ObjectIdentifier.init)) { connect() }
    }

    private func connect() {
        if let serviceOverride {
            if models.service !== serviceOverride { models.service = serviceOverride }
        } else if let connection, !(models.service is EverShelfRecipeService) {
            models.service = EverShelfRecipeService(caller: connection)
        }
    }

    @ViewBuilder
    private func destination(_ route: FoodRoute) -> some View {
        switch route {
        case .hub: FoodHubScreen(models: models)
        case .recipes: RecipesScreen(models: models)
        case let .inventory(location):
            // The inventory pages land with their own thread (`plans/inventory-spec.md`).
            PlaceholderScreen(title: Self.inventoryTitle(location), symbol: "refrigerator")
        }
    }

    static var requestedLaunchRoute: FoodRoute? {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["FENTON_OPEN_FOOD"] {
        case "hub": .hub
        case "recipes": .recipes
        default: nil
        }
        #else
        nil
        #endif
    }

    static func inventoryTitle(_ location: String?) -> String {
        guard let location else { return "All Food" }
        return FoodConfig.spaces.first { $0.location == location }?.title ?? "Food"
    }
}
