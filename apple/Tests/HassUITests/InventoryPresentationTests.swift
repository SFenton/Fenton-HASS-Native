import CoreGraphics
import Foundation
@testable import HassCore
@testable import HassUI
import SwiftUI
import Testing

/// Page and editor actions (``InventoryPresentation``, ``EditorPrompt``), destinations, and the in-flight
/// states of the inventory views.
@MainActor
struct InventoryPresentationTests {
    private func loaded(_ space: InventorySpace = .pantry, server: EverShelfFixtureServer = .sample()) async -> (EverShelfFixtureServer, InventoryModels, InventoryListModel) {
        let models = InventoryModels(client: EverShelfClient(caller: server))
        let model = models.model(for: space)
        await model.load()
        return (server, models, model)
    }

    private func rendered(_ view: some View, size: CGSize = CGSize(width: 402, height: 874)) -> Bool {
        ImageRenderer(content: view.frame(width: size.width, height: size.height)).cgImage != nil
    }

    /// Starts `work` with the server slowed down, waits for `until`, runs `check`, then lets the work finish.
    private func whileRunning(
        _ server: EverShelfFixtureServer,
        _ work: @escaping @MainActor () async -> Void,
        until: () -> Bool,
        check: () -> Void
    ) async {
        server.latency = .milliseconds(400)
        let task = Task { await work() }
        let deadline = ContinuousClock.now + .seconds(5)
        while !until(), ContinuousClock.now < deadline { await Task.yield() }
        #expect(until(), "in-flight state never appeared")
        check()
        await task.value
        server.latency = .zero
    }

    // MARK: - Page presentation

    @Test func launchOpensSheetsAndEditors() async {
        let (_, _, model) = await loaded()
        let presentation = InventoryPresentation()
        presentation.open(nil, in: model)
        #expect(presentation.sheet == nil && presentation.editing == nil)
        presentation.open(.sheet(.filter), in: model)
        #expect(presentation.sheet == .filter)
        presentation.open(.editor("Nothing Here"), in: model)
        #expect(presentation.editing == nil)
        presentation.open(.editor("Black Beans"), in: model)
        #expect(presentation.editing?.id == "black beans")
    }

    @Test func editorShowsAsSheetOnlyWhenTheWindowCannotSplit() async throws {
        let (_, _, model) = await loaded()
        let presentation = InventoryPresentation()
        presentation.open(try #require(model.displayItem(id: "honey")), in: model)
        #expect(presentation.sheetEditor?.itemId == "honey")
        presentation.canSplit = true
        #expect(presentation.sheetEditor == nil)
        presentation.sheetEditor = nil // Dismissing a sheet that isn't shown keeps the pane open.
        #expect(presentation.editing != nil)
        presentation.canSplit = false
        presentation.sheetEditor = nil
        #expect(presentation.editing == nil)
    }

    @Test func splitFollowsTheGeometricPolicy() {
        let presentation = InventoryPresentation()
        presentation.updateSplit(CGSize(width: 1376, height: 1032), isRegularWidth: true)
        #expect(presentation.canSplit)
        presentation.updateSplit(CGSize(width: 1376, height: 1032), isRegularWidth: true)
        #expect(presentation.canSplit)
        presentation.updateSplit(CGSize(width: 402, height: 874), isRegularWidth: false)
        #expect(!presentation.canSplit)
    }

    @Test func deleteAsksHowManyOnlyWhenMoreThanOneIsStocked() async throws {
        let (_, _, model) = await loaded()
        let presentation = InventoryPresentation()
        let beans = try #require(model.displayItem(id: "black beans"))
        presentation.promptText = "7"
        presentation.requestDelete(beans, in: model)
        #expect(presentation.prompt?.id == "delete-black beans")
        #expect(presentation.promptText == "1")
        #expect(presentation.confirmDelete == nil)
        let honey = try #require(model.displayItem(id: "honey"))
        presentation.prompt = nil
        presentation.requestDelete(honey, in: model)
        #expect(presentation.confirmDelete?.id == "honey")
        #expect(presentation.prompt == nil)
    }

    @Test func deleteSkipsItemsWithoutDeletableRows() async {
        let (_, _, model) = await loaded()
        let presentation = InventoryPresentation()
        let unaddressable = InventoryDisplayItem(rows: [InventoryItem(inventoryId: nil, name: "Jam", quantity: 2, location: .pantry)])
        presentation.requestDelete(unaddressable, in: model)
        #expect(presentation.prompt == nil && presentation.confirmDelete == nil)
    }

    @Test func shoppingPromptAddsTheEnteredQuantity() async throws {
        let (server, _, model) = await loaded()
        let presentation = InventoryPresentation()
        let beans = try #require(model.displayItem(id: "black beans"))
        presentation.ask(.shopping(beans))
        presentation.promptText = "abc"
        await presentation.submit(.shopping(beans), in: model)
        #expect(!server.calls.contains { $0.hasPrefix("evershelf.add_to_shopping") })
        presentation.promptText = "2"
        await presentation.submit(.shopping(beans), in: model)
        #expect(server.calls.contains { $0.hasPrefix("evershelf.add_to_shopping") && $0.contains("quantity=2") })
    }

    @Test func deletePromptValidatesTheRange() async throws {
        let (server, _, model) = await loaded()
        let presentation = InventoryPresentation()
        let beans = try #require(model.displayItem(id: "black beans"))
        presentation.promptText = "4"
        await presentation.submit(.delete(beans, 3), in: model)
        #expect(model.rowErrors["black beans"] == "Enter a number from 1 to 3.")
        presentation.promptText = "1"
        await presentation.submit(.delete(beans, 3), in: model)
        #expect(server.calls.contains { $0.hasPrefix("evershelf.delete_inventory") })
        #expect(model.rowErrors["black beans"] == nil)
    }

    // MARK: - Editor prompts

    @Test func editorPromptsApplyOrReject() async throws {
        let (server, _, model) = await loaded(.fridge)
        let editor = InventoryEditorModel(item: try #require(model.displayItem(id: "eggs")), list: model)
        let batch = try #require(editor.batches.first)
        let delete = try #require(await EditorPrompt.delete(batch, in: editor))
        #expect(delete.id == "delete-\(batch.key)")
        await delete.submit("13", to: editor)
        #expect(editor.error != nil)
        await delete.submit("2", to: editor)
        #expect(server.rows.first { $0.name == "Eggs" }?.quantity == 10)
        let remaining = try #require(editor.batches.first)
        let prepared = try #require(await EditorPrompt.prepared(remaining, in: editor))
        #expect(prepared.confirmTitle == "Change")
        await prepared.submit("1", to: editor)
        #expect(server.calls.contains { $0.hasPrefix("evershelf.set_inventory_prepared_food") })
    }

    @Test func batchNamesPrefixTheItemTitleLikeTheWeb() async throws {
        let (_, _, model) = await loaded()
        let beans = InventoryEditorModel(item: try #require(model.displayItem(id: "black beans")), list: model)
        let batch = try #require(beans.batches.first)
        #expect(beans.batchName(batch) == "Black Beans" + beans.qualifier(batch))
        #expect(beans.batchName(batch).hasPrefix("Black Beans expiring "))
        let prompt = try #require(await EditorPrompt.delete(batch, in: beans))
        #expect(prompt.title == "Delete \(beans.batchName(batch))")
        let honey = InventoryEditorModel(item: try #require(model.displayItem(id: "honey")), list: model)
        #expect(honey.batchName(try #require(honey.batches.first)) == "Honey")
    }

    @Test func singleUnitBatchesActWithoutAsking() async throws {
        let (server, _, model) = await loaded()
        let honey = InventoryEditorModel(item: try #require(model.displayItem(id: "honey")), list: model)
        let batch = try #require(honey.batches.first)
        #expect(await EditorPrompt.prepared(batch, in: honey) == nil)
        #expect(server.calls.contains { $0.hasPrefix("evershelf.set_inventory_prepared_food") })
        let spaghetti = InventoryEditorModel(item: try #require(model.displayItem(id: "spaghetti")), list: model)
        #expect(await EditorPrompt.delete(try #require(spaghetti.batches.first), in: spaghetti) == nil)
        #expect(!server.rows.contains { $0.name == "Spaghetti" })
    }

    // MARK: - Destinations

    @Test func destinationsReuseOneModelRegistryPerStack() async {
        let store = EntityStore()
        let connection = HassConnection(server: .fentonHome, tokens: TokenManager(store: InMemoryTokenStore()), store: store)
        let holder = InventoryModelsHolder()
        let first = holder.models(for: connection)
        #expect(holder.models(for: connection) === first)
        #expect(InventoryDestinations.requestedAtLaunch(environment: ["FENTON_OPEN_INVENTORY": "pantry"]) == .pantry)
        #expect(InventoryDestinations.requestedAtLaunch(environment: ["FENTON_OPEN_INVENTORY": "garage"]) == nil)
        #expect(InventoryDestinations.requestedAtLaunch(environment: [:]) == nil)
    }

    @Test func destinationsRender() async {
        let (_, models, _) = await loaded()
        #expect(rendered(InventoryDestinationScreen(route: .space(.fridge), models: models)))
        #expect(rendered(InventoryDestinationScreen(route: .space(.fridge), models: nil)))
        #expect(rendered(NavigationStack { Color.clear.inventoryDestinations() }.environment(\.inventoryModels, models)))
    }

    // MARK: - In-flight and split rendering

    @Test func splitPageRendersTheEditorPane() async throws {
        let (_, models, model) = await loaded()
        let presentation = InventoryPresentation(canSplit: true)
        presentation.open(try #require(model.displayItem(id: "black beans")), in: model)
        let view = NavigationStack { InventoryScreen(model: model, models: models, presentation: presentation) }
        #expect(rendered(view, size: CGSize(width: 1376, height: 1032)))
        for sheet in [InventorySheet.sort, .filter, .scan] {
            #expect(rendered(InventorySheetContent(sheet: sheet, model: model, models: models)))
        }
    }

    @Test func pageRendersWhileSearching() async {
        let (server, models, model) = await loaded()
        await whileRunning(server, {
            model.searchQuery = "bean"
            try? await Task.sleep(for: .seconds(1.2))
        }, until: { model.isSearching }) {
            #expect(rendered(NavigationStack { InventoryScreen(model: model, models: models) }))
        }
    }

    @Test func editorRendersBusyAndErrorStates() async throws {
        let (server, _, model) = await loaded()
        let editor = InventoryEditorModel(item: try #require(model.displayItem(id: "black beans")), list: model)
        var batch = try #require(editor.batches.first)
        editor.setQuantity(batch.quantity + 1, for: batch)
        await whileRunning(server, { await editor.save(batch) }, until: { editor.busy != nil }) {
            #expect(rendered(InventoryItemEditor(model: editor, style: .sheet, onClose: {})))
        }
        batch = try #require(editor.batches.first)
        await whileRunning(server, { await editor.togglePrepared(batch, quantity: 1) }, until: { editor.busy != nil }) {
            #expect(rendered(InventoryItemEditor(model: editor, style: .pane, onClose: {})))
        }
        batch = try #require(editor.batches.last)
        await whileRunning(server, { await editor.delete(batch, quantity: 1) }, until: { editor.busy != nil }) {
            #expect(rendered(InventoryItemEditor(model: editor, style: .sheet, onClose: {})))
        }
        server.failing = ["evershelf.delete_inventory"]
        await editor.delete(try #require(editor.batches.first))
        #expect(editor.error != nil)
        #expect(rendered(InventoryItemEditor(model: editor, style: .sheet, onClose: {})))
    }

    // MARK: - Scan Item states

    @Test func scanRendersProcessingAndLookupMisses() async {
        let server = EverShelfFixtureServer.sample()
        let scan = ScanItemModel(space: .pantry, client: EverShelfClient(caller: server))
        let camera = ScanCameraController(source: .simulated)
        await whileRunning(server, { await scan.didDetectBarcode("0123456789012") }, until: { scan.isProcessing }) {
            #expect(rendered(ScanItemSheet(model: scan, camera: camera, onAdded: {})))
        }
        scan.scanBarcodeAgain()
        await scan.didDetectBarcode("9999999999999")
        #expect(scan.statusMessage != nil)
        #expect(rendered(ScanItemSheet(model: scan, camera: camera, onAdded: {})))
        server.failing = ["evershelf.resolve_barcode"]
        scan.scanBarcodeAgain()
        await scan.didDetectBarcode("1111111111111")
        #expect(scan.statusIsError)
        #expect(rendered(ScanItemSheet(model: scan, camera: camera, onAdded: {})))
    }

    @Test func scanRendersTheExpiryPageWithACamera() async {
        let server = EverShelfFixtureServer.sample()
        let scan = ScanItemModel(space: .pantry, client: EverShelfClient(caller: server))
        let camera = ScanCameraController(source: .simulated)
        scan.enterNameManually()
        scan.setName("Oat Milk")
        scan.goToExpiryStep()
        await camera.sync(with: scan)
        #expect(scan.canReadExpiry)
        #expect(rendered(ScanItemSheet(model: scan, camera: camera, onAdded: {})))
        server.expiryReading = .object(["success": .bool(false)])
        await camera.captureExpiry(for: scan)
        #expect(scan.statusMessage != nil)
        #expect(rendered(ScanItemSheet(model: scan, camera: camera, onAdded: {})))
    }

    @Test func scanRendersAddingAddedAndFailed() async {
        let server = EverShelfFixtureServer.sample()
        let scan = ScanItemModel(space: .fridge, client: EverShelfClient(caller: server))
        let camera = ScanCameraController(source: .simulated)
        scan.enterNameManually()
        scan.setName("Oat Milk")
        scan.goToExpiryStep()
        scan.goToReviewStep()
        server.failing = ["evershelf.add_scanned_item"]
        await scan.add()
        #expect(scan.addError != nil)
        #expect(rendered(ScanItemSheet(model: scan, camera: camera, onAdded: {})))
        server.failing = []
        await whileRunning(server, { await scan.add() }, until: { scan.step == .adding && scan.addStatus == .adding }) {
            #expect(rendered(ScanItemSheet(model: scan, camera: camera, onAdded: {})))
        }
        #expect(scan.addStatus == .added)
        #expect(rendered(ScanItemSheet(model: scan, camera: camera, onAdded: {})))
    }
}
