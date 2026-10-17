#if DEBUG
import HassCore
import HassDesign
import SwiftUI

/// Gallery page for the inventory pages, item editor and Add Item sheet, on ``EverShelfFixtureServer``.
///
/// Environment:
/// - `FENTON_GALLERY_SPACE`: `all-food`, `pantry` (default), `fridge`, `freezer`, `spice-rack` or `cabinet`.
/// - `FENTON_GALLERY_OPEN`: `sort`, `filter`, `scan` or `editor:<item name>` once rows load.
/// - `FENTON_GALLERY_STATE`: `empty`, `error` or `loading`.
/// - `FENTON_GALLERY_LATENCY_MS=<ms>`: how long each answer takes (default 150), so a journey can watch the spinner.
/// - `FENTON_GALLERY_SORT=expiry`: sorts by expiration date, so rows group under Expired, Expiring Soon and Later.
/// - `FENTON_SCAN_CAMERA=simulated`: the Add Item camera draws a viewfinder with a Simulate Scan button.
/// - `FENTON_GALLERY_CLEAN=1`: hides the last-call line (screenshots).
/// - `FENTON_GALLERY_HOLD_ADDED=1`: keeps a row's "added to shopping list" check for 30 s instead of 3 s.
struct InventoryGallery: View {
    @State private var server: EverShelfFixtureServer
    @State private var models: InventoryModels
    private let space: InventorySpace
    private let launch: InventoryLaunch?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let server = EverShelfFixtureServer.sample()
        switch environment["FENTON_GALLERY_STATE"] {
        case "empty": server.rows = []
        case "error": server.failing = ["evershelf.list_inventory"]
        case "loading": server.latency = .seconds(3600)
        default: server.latency = .milliseconds(environment["FENTON_GALLERY_LATENCY_MS"].flatMap { Int($0) } ?? 150)
        }
        let models = InventoryModels(client: EverShelfClient(caller: server))
        _server = State(initialValue: server)
        _models = State(initialValue: models)
        space = environment["FENTON_GALLERY_SPACE"].flatMap(InventorySpace.init(rawValue:)) ?? .pantry
        if environment["FENTON_GALLERY_HOLD_ADDED"] == "1" {
            // Journeys on a loaded host can miss the web's 3 s "added" check; hold it so they can read it.
            models.model(for: space).addedVisibleFor = .seconds(30)
        }
        if environment["FENTON_GALLERY_SORT"] == "expiry" {
            // The page as the Sort sheet's Expiration Date leaves it: grouped under Expired, Expiring Soon, Later.
            models.model(for: space).sortMode = .expiry
        }
        launch = environment["FENTON_GALLERY_OPEN"].flatMap(InventoryLaunch.init)
    }

    var body: some View {
        InventoryScreen(model: models.model(for: space), models: models, launch: launch)
            .environment(\.inventoryModels, models)
            .safeAreaInset(edge: .top, spacing: 0) {
                if !GalleryEnvironment.isClean {
                    GalleryLastCall(text: server.lastCall, lineLimit: 2)
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .background(.bar)
                }
            }
    }
}
#endif
