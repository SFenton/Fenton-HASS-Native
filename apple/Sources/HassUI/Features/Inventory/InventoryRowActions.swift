import HassCore
import SwiftUI

extension View {
    /// What an ``InventoryRow`` asks for: the item editor as a sheet (while the window can't split), the quantity prompt for
    /// Add to Groceries and a partial delete, and the confirmation before deleting a single unit. One implementation for
    /// the inventory pages and the Summary sheet's Expired Food tab.
    ///
    /// A method, not a `ViewModifier`: the presentation state is read while the calling page builds its body, as it was when
    /// these were written inline. As a modifier on the page's root it left the Food and Inventory galleries blank at tablet
    /// width (the split's geometry update re-ran the modifier while the page was settling).
    /// - Parameters:
    ///   - presentation: Which of them is up.
    ///   - model: The page model the row actions run against.
    func inventoryRowActions(_ presentation: InventoryPresentation, model: InventoryListModel) -> some View {
        let bindable = Bindable(presentation)
        let promptShown = Binding(get: { presentation.prompt != nil }, set: { if !$0 { presentation.prompt = nil } })
        let deleteShown = Binding(get: { presentation.confirmDelete != nil }, set: { if !$0 { presentation.confirmDelete = nil } })
        return sheet(item: bindable.sheetEditor) { editor in
            InventoryItemEditor(model: editor, style: .sheet) { presentation.editing = nil }
        }
        .alert(presentation.prompt?.title ?? "", isPresented: promptShown, presenting: presentation.prompt) { prompt in
            TextField("Quantity", text: bindable.promptText)
                .numericEntryField()
                .accessibilityIdentifier("inventory.prompt.field")
            Button("Cancel", role: .cancel) {}
            Button(prompt.confirmTitle) { Task { await presentation.submit(prompt, in: model) } }
        } message: { prompt in
            Text(prompt.message)
        }
        .confirmationDialog(
            presentation.confirmDelete.map { "Delete \($0.name) from the \(model.space.phrase)?" } ?? "",
            isPresented: deleteShown,
            titleVisibility: .visible,
            presenting: presentation.confirmDelete
        ) { item in
            Button("Delete", role: .destructive) { Task { await model.delete(item) } }
        }
    }
}
