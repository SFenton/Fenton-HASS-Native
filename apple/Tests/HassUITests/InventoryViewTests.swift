import Foundation
@testable import HassCore
@testable import HassUI
import SwiftUI
import Testing

@MainActor
struct InventoryViewTests {
    private func models(_ server: EverShelfFixtureServer = .sample()) -> (EverShelfFixtureServer, InventoryModels) {
        (server, InventoryModels(client: EverShelfClient(caller: server)))
    }

    private func rendered(_ view: some View, size: CGSize = CGSize(width: 402, height: 874), dynamicType: DynamicTypeSize = .large) -> Bool {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).environment(\.dynamicTypeSize, dynamicType))
        return renderer.cgImage != nil
    }

    // MARK: - Copy and parsing

    @Test func launchOptionsParse() {
        #expect(InventoryLaunch("sort") == .sheet(.sort))
        #expect(InventoryLaunch("filter") == .sheet(.filter))
        #expect(InventoryLaunch("scan") == .sheet(.scan))
        #expect(InventoryLaunch("editor:Black Beans") == .editor("Black Beans"))
        #expect(InventoryLaunch("nope") == nil)
    }

    @Test func pagePromptsMatchTheWeb() async throws {
        let (_, models) = models()
        let model = models.model(for: .pantry)
        await model.load()
        let beans = try #require(model.displayItem(id: "black beans"))
        let shop = InventoryPrompt.shopping(beans)
        #expect(shop.title == "Add Black Beans to Groceries")
        #expect(shop.message == "Quantity of Black Beans to add to the grocery cart.")
        #expect(shop.confirmTitle == "Add")
        #expect(shop.id == "shop-black beans")
        let delete = InventoryPrompt.delete(beans, 3)
        #expect(delete.title == "Delete Black Beans")
        #expect(delete.message.hasSuffix("Enter a number from 1 to 3."))
        #expect(delete.confirmTitle == "Delete")
        #expect(delete.id == "delete-black beans")
        #expect(InventorySheet.scan.id == "scan")
    }

    @Test func editorPromptsNameTheBatch() async throws {
        let (_, models) = models()
        let model = models.model(for: .pantry)
        await model.load()
        let editor = InventoryEditorModel(item: try #require(model.displayItem(id: "black beans")), list: model)
        let batch = try #require(editor.batches.first)
        let delete = EditorPrompt.delete(batch, qualifier: "this batch")
        #expect(delete.title == "Delete this batch")
        #expect(delete.batch == batch)
        #expect(delete.confirmTitle == "Delete")
        #expect(delete.id.hasPrefix("delete-"))
        let prepared = EditorPrompt.prepared(batch, qualifier: "this batch")
        #expect(prepared.title == "Mark this batch as Prepared")
        #expect(prepared.confirmTitle == "Change")
        #expect(prepared.message.contains("from 1 to"))
        #expect(prepared.id.hasPrefix("prepared-"))
    }

    // MARK: - Camera

    @Test func unavailableCameraFailsWithManualEntry() async {
        let (server, models) = models()
        _ = server
        let scan = ScanItemModel(space: .pantry, client: models.everShelf)
        let camera = ScanCameraController(source: .unavailable)
        await camera.sync(with: scan)
        #expect(scan.cameraStatus == .failed(ScanCameraController.unavailableMessage))
        await camera.captureExpiry(for: scan)
        camera.stop()
    }

    @Test func simulatedCameraWalksTheFlow() async {
        let (server, models) = models()
        let scan = ScanItemModel(space: .pantry, client: models.everShelf)
        let camera = ScanCameraController(source: .simulated, simulatedBarcode: "0123456789012")
        await camera.sync(with: scan)
        #expect(scan.cameraStatus == .ready)
        await camera.simulate(on: scan)
        #expect(scan.name == "Greek Yogurt")
        await camera.sync(with: scan) // Barcode camera no longer wanted: stops.
        scan.goToExpiryStep()
        await camera.sync(with: scan)
        await camera.captureExpiry(for: scan)
        #expect(scan.expiryDate == "2030-01-15")
        #expect(server.calls.contains { $0.hasPrefix("evershelf.read_expiry_image") })
        scan.goToReviewStep()
        await camera.simulate(on: scan) // No camera on review: nothing happens.
        #expect(scan.step == .review)
    }

    // MARK: - Rendering

    @Test func pagesRenderInEveryState() async {
        for state in ["content", "empty", "error"] {
            let server = EverShelfFixtureServer.sample()
            if state == "empty" { server.rows = [] }
            if state == "error" { server.failing = ["evershelf.list_inventory"] }
            let (_, models) = models(server)
            for space in InventorySpace.allCases {
                let model = models.model(for: space)
                await model.load()
                #expect(rendered(NavigationStack { InventoryScreen(model: model, models: models) }), "\(space) \(state)")
            }
        }
    }

    @Test func pageRendersLoadingAndAtAccessibilitySizes() async {
        let (_, models) = models()
        let model = models.model(for: .pantry)
        #expect(rendered(NavigationStack { InventoryScreen(model: model, models: models) }))
        await model.load()
        model.sortMode = .expiry
        model.filterMode = .expired
        #expect(rendered(NavigationStack { InventoryScreen(model: model, models: models) }, dynamicType: .accessibility5))
        #expect(rendered(NavigationStack { InventoryScreen(model: model, models: models) }, size: CGSize(width: 1376, height: 1032)))
    }

    @Test func rowsRenderEveryAction() async throws {
        let (_, models) = models()
        let model = models.model(for: .allFood)
        await model.load()
        for item in model.visibleItems {
            #expect(rendered(List { InventoryRow(item: item, model: model, selected: true, onEdit: {}, onShop: {}, onDelete: {}) }))
        }
        let soup = try #require(model.displayItem(id: "chicken soup"))
        model.setRowError("Unable to delete item", for: soup.id)
        #expect(rendered(List { InventoryRow(item: soup, model: model, onEdit: {}, onShop: {}, onDelete: {}) }, dynamicType: .accessibility5))
        #expect(InventoryTone.color(.soon) != InventoryTone.color(.expired))
    }

    @Test func sheetsRender() async throws {
        let (_, models) = models()
        let model = models.model(for: .pantry)
        await model.load()
        #expect(rendered(InventorySortSheet(model: model)))
        #expect(rendered(InventoryFilterSheet(model: model)))
        let editor = InventoryEditorModel(item: try #require(model.displayItem(id: "black beans")), list: model)
        if let batch = editor.batches.first {
            editor.setQuantity(1, for: batch)
            editor.setExpiry("", for: batch)
        }
        #expect(rendered(InventoryItemEditor(model: editor, style: .sheet, onClose: {})))
        #expect(rendered(InventoryItemEditor(model: editor, style: .pane, onClose: {}), dynamicType: .accessibility5))
    }

    @Test func scanStepsRender() async {
        let (_, models) = models()
        let scan = ScanItemModel(space: .fridge, client: models.everShelf)
        let simulated = ScanCameraController(source: .simulated)
        #expect(rendered(ScanItemSheet(model: scan, camera: simulated, onAdded: {})))
        scan.enterNameManually()
        scan.setName("Oat Milk")
        #expect(rendered(ScanItemSheet(model: scan, camera: simulated, onAdded: {})))
        scan.goToExpiryStep()
        #expect(rendered(ScanItemSheet(model: scan, camera: ScanCameraController(source: .unavailable), onAdded: {})))
        scan.enterExpiryManually()
        scan.selectQuickExpiry(.oneWeek)
        #expect(rendered(ScanItemSheet(model: scan, camera: simulated, onAdded: {})))
        scan.goToReviewStep()
        scan.setQuantityText("0")
        _ = scan.validateQuantity()
        #expect(rendered(ScanItemSheet(model: scan, camera: simulated, onAdded: {}), dynamicType: .accessibility5))
        await scan.add()
        #expect(rendered(ScanItemSheet(model: scan, camera: simulated, onAdded: {})))
    }

    @Test func galleryRenders() {
        #expect(rendered(ComponentGallery(page: .inventory)))
        #expect(rendered(InventoryGallery(environment: ["FENTON_GALLERY_STATE": "empty", "FENTON_GALLERY_SPACE": "fridge"])))
        #expect(rendered(InventoryGallery(environment: ["FENTON_GALLERY_STATE": "error", "FENTON_GALLERY_OPEN": "editor:Honey"])))
        #expect(rendered(InventoryGallery(environment: ["FENTON_GALLERY_STATE": "loading"])))
    }
}
