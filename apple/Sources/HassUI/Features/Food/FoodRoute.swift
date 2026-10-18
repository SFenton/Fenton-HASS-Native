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
    /// An inventory page (Inventory lane's ``InventorySpace``: All Food or one of the five spaces).
    case inventory(InventorySpace)
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
        #if DEBUG
        // FENTON_FOOD_FIXTURES=1: the signed-in app's Food pages answer from fixtures (journeys that separate live
        // data from the signed-in app's own behavior).
        if serviceOverride == nil, ProcessInfo.processInfo.environment["FENTON_FOOD_FIXTURES"] == "1" {
            if !(models.service is FixtureRecipeService) { models.service = FixtureRecipeService() }
            return
        }
        #endif
        if let serviceOverride {
            if models.service !== serviceOverride { models.service = serviceOverride }
        } else if let connection, !(models.service is EverShelfRecipeService) {
            models.service = EverShelfRecipeService(caller: connection)
        }
    }

    private func destination(_ route: FoodRoute) -> some View { Self.destination(route, models: models).pageChrome() }

    /// The page for a route.
    @ViewBuilder
    static func destination(_ route: FoodRoute, models: FoodModels) -> some View {
        switch route {
        case .hub: FoodHubScreen(models: models)
        case .recipes: RecipesScreen(models: models)
        case let .inventory(space):
            FoodInventoryScreen(space: space)
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
}

/// The Food hub as a pushed page from another stack (``HomeRoute/food`` from Quick Links): owns its models and
/// uses the signed-in connection's recipe service. The hub's tiles push through its own destination.
struct FoodEntryScreen: View {
    @Environment(HassConnection.self) private var connection: HassConnection?
    @Environment(\.sessionModels) private var session
    @State private var ownModels = FoodModels()

    /// The session's models, so a revisit shows Suggested Recipes at once; the page's own outside the shell.
    private var models: FoodModels { session?.food ?? ownModels }

    var body: some View {
        FoodHubScreen(models: models)
            .onAppear {
                guard models.service == nil, let connection else { return }
                models.service = EverShelfRecipeService(caller: connection)
                // The hub's own onAppear may have run first, without a service.
                models.suggestions.appear()
            }
    }
}

/// An inventory page pushed from the Food hub: the Inventory lane's page with the stack's ``InventoryModels``
/// (the gallery's fixture server, else the signed-in connection), the same way ``inventoryDestinations()``
/// builds it.
struct FoodInventoryScreen: View {
    let space: InventorySpace
    @Environment(\.inventoryModels) private var injected
    @Environment(\.sessionModels) private var session
    @Environment(HassConnection.self) private var connection: HassConnection?
    @State private var holder = InventoryModelsHolder()

    var body: some View {
        InventoryDestinationScreen(route: .space(space), models: injected ?? connection.map { session?.inventory(for: $0) ?? holder.models(for: $0) })
    }

    /// The inventory page for one of the hub's EverShelf locations (`FoodConfig.spaces`).
    static func space(forLocation location: String) -> InventorySpace? {
        switch location {
        case "dispensa": .pantry
        case "frigo": .fridge
        case "freezer": .freezer
        case "spice_rack": .spiceRack
        case "cabinet": .cabinet
        default: nil
        }
    }
}
