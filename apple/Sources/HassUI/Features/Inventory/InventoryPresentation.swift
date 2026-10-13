import CoreGraphics
import HassCore
import HassDesign
import Observation

/// What an inventory page presents over its rows: the item editor, a sheet, a quantity prompt or a delete
/// confirmation, and whether the window may split. ``InventoryScreen`` owns one; keeping the decisions here
/// lets them be unit-tested without a window.
@MainActor
@Observable
final class InventoryPresentation {
    /// The open item editor (a sheet, or the trailing pane while ``canSplit``).
    var editing: InventoryEditorModel?
    /// The open Sort, Filter or Scan Item sheet.
    var sheet: InventorySheet?
    /// The open quantity prompt.
    var prompt: InventoryPrompt?
    /// The prompt's text field.
    var promptText = ""
    /// The single-unit item awaiting delete confirmation.
    var confirmDelete: InventoryDisplayItem?
    /// Whether the window may show the editor beside the list (``SplitPolicy``).
    var canSplit: Bool

    init(canSplit: Bool = false) {
        self.canSplit = canSplit
    }

    // MARK: - Opening

    /// Opens a launch request (debug gallery and journeys) once rows have loaded.
    func open(_ launch: InventoryLaunch?, in model: InventoryListModel) {
        switch launch {
        case let .sheet(next): sheet = next
        case let .editor(name): if let item = model.displayItem(id: name.lowercased()) { open(item, in: model) }
        case nil: break
        }
    }

    /// Opens the item editor for a row.
    func open(_ item: InventoryDisplayItem, in model: InventoryListModel) {
        editing = InventoryEditorModel(item: item, list: model)
    }

    /// The editor while it shows as a sheet: only while the window can't split. Clearing it closes the editor.
    var sheetEditor: InventoryEditorModel? {
        get { canSplit ? nil : editing }
        set { if newValue == nil, !canSplit { editing = nil } }
    }

    // MARK: - Prompts

    /// Delete on a row: asks how many when more than one is stocked, otherwise asks to confirm.
    func requestDelete(_ item: InventoryDisplayItem, in model: InventoryListModel) {
        guard let rows = model.deletableRows(of: item) else { return }
        let stocked = rows.reduce(0) { $0 + $1.quantity }
        if stocked > 1 {
            ask(.delete(item, stocked))
        } else {
            confirmDelete = item
        }
    }

    /// Opens a quantity prompt prefilled with 1.
    func ask(_ next: InventoryPrompt) {
        promptText = "1"
        prompt = next
    }

    /// Runs a prompt's action with the entered quantity. An invalid delete quantity shows on the row; an
    /// invalid shopping quantity does nothing, as on the web.
    func submit(_ prompt: InventoryPrompt, in model: InventoryListModel) async {
        switch prompt {
        case let .shopping(item):
            guard let quantity = InventoryFormat.parseQuantity(promptText), quantity >= 1 else { return }
            await model.addToShopping(item, quantity: quantity)
        case let .delete(item, stocked):
            guard let quantity = InventoryFormat.parseQuantity(promptText), quantity >= 1, quantity <= stocked else {
                model.setRowError("Enter a number from 1 to \(InventoryFormat.quantity(stocked)).", for: item.id)
                return
            }
            await model.delete(item, quantity: quantity)
        }
    }

    // MARK: - Split

    /// Re-evaluates ``canSplit`` for the page's size.
    func updateSplit(_ size: CGSize, isRegularWidth: Bool) {
        let allowed = SplitPolicy.allowsSplit(size: size, isRegularWidth: isRegularWidth)
        if allowed != canSplit { canSplit = allowed }
    }
}
