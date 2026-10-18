import Foundation
import HassCore
import SwiftUI

/// Navigation values for the inventory pages. The Food & Recipes hub pushes these; any stack that shows them
/// adds ``SwiftUICore/View/inventoryDestinations()`` once.
public enum InventoryRoute: Hashable, Sendable {
    /// One of the six inventory pages.
    case space(InventorySpace)
}

/// Page models shared by every inventory page in a stack, so pages keep their rows between visits.
private struct InventoryModelsKey: EnvironmentKey {
    static var defaultValue: InventoryModels? { nil }
}

extension EnvironmentValues {
    /// Inventory page models; set by ``SwiftUICore/View/inventoryDestinations()`` or the gallery.
    var inventoryModels: InventoryModels? {
        get { self[InventoryModelsKey.self] }
        set { self[InventoryModelsKey.self] = newValue }
    }
}

extension View {
    /// Registers the inventory pages as destinations of the enclosing `NavigationStack`.
    ///
    /// Uses the signed-in ``HassConnection`` unless an ``InventoryModels`` is already in the environment
    /// (the debug gallery's fixture server). In debug builds `FENTON_OPEN_INVENTORY=<space>` (e.g. `pantry`)
    /// pushes that page at launch, so journeys can reach it before the Food & Recipes hub links it.
    public func inventoryDestinations() -> some View {
        modifier(InventoryDestinations())
    }
}

/// Holds the stack's models for the life of its root view.
@MainActor
final class InventoryModelsHolder {
    var models: InventoryModels?

    func models(for connection: HassConnection) -> InventoryModels {
        if let models { return models }
        let created = InventoryModels(client: EverShelfClient(caller: connection))
        models = created
        return created
    }
}

struct InventoryDestinations: ViewModifier {
    @Environment(\.inventoryModels) private var injected
    @Environment(\.sessionModels) private var session
    @Environment(HassConnection.self) private var connection: HassConnection?
    @State private var holder = InventoryModelsHolder()
    @State private var launchSpace: InventorySpace? = InventoryDestinations.requestedAtLaunch()

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: InventoryRoute.self) { route in
                screen(route).pageChrome()
            }
            .navigationDestination(item: $launchSpace) { space in
                screen(.space(space)).pageChrome()
            }
    }

    private func screen(_ route: InventoryRoute) -> InventoryDestinationScreen {
        InventoryDestinationScreen(route: route, models: injected ?? connection.map { session?.inventory(for: $0) ?? holder.models(for: $0) })
    }

    /// `FENTON_OPEN_INVENTORY=<space>` (debug builds only).
    static func requestedAtLaunch(environment: [String: String] = ProcessInfo.processInfo.environment) -> InventorySpace? {
        #if DEBUG
        environment["FENTON_OPEN_INVENTORY"].flatMap(InventorySpace.init(rawValue:))
        #else
        nil
        #endif
    }
}

/// One inventory destination: the page for a route with the stack's models, or Not Signed In without them.
struct InventoryDestinationScreen: View {
    var route: InventoryRoute
    var models: InventoryModels?

    var body: some View {
        if let models {
            switch route {
            case let .space(space):
                InventoryScreen(model: models.model(for: space), models: models)
                    .environment(\.inventoryModels, models)
                    // Live rows are the household's own: screenshots shared outside it hide item names
                    // (`FENTON_REDACT_PRIVATE=1`). The gallery's fixture rows stay readable.
                    .redacted(reason: ScreenshotPrivacy.isRedacting ? .privacy : [])
            }
        } else {
            ContentUnavailableView("Not Signed In", systemImage: "person.crop.circle.badge.exclamationmark")
        }
    }
}
