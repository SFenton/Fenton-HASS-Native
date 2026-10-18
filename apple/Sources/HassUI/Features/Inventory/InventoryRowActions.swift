import HassCore
import SwiftUI

extension View {
    /// What an ``InventoryRow`` asks for: the item editor as a sheet (while the window can't split), the quantity prompt for
    /// Add to Groceries and a partial delete, and the confirmation before deleting a single unit. One implementation for
    /// the inventory pages and the Summary sheet's Expired Food tab.
    /// - Parameters:
    ///   - presentation: Which of them is up.
    ///   - model: The page model the row actions run against.
    func inventoryRowActions(_ presentation: InventoryPresentation, model: InventoryListModel) -> some View {
        modifier(InventoryRowActions(presentation: presentation, model: model))
    }
}

/// Implementation of ``SwiftUICore/View/inventoryRowActions(_:model:)``.
private struct InventoryRowActions: ViewModifier {
    @Bindable var presentation: InventoryPresentation
    var model: InventoryListModel

    func body(content: Content) -> some View {
        content
            .sheet(item: $presentation.sheetEditor) { editor in
                InventoryItemEditor(model: editor, style: .sheet) { presentation.editing = nil }
            }
            .alert(presentation.prompt?.title ?? "", isPresented: promptShown, presenting: presentation.prompt) { prompt in
                TextField("Quantity", text: $presentation.promptText)
                    .numericEntryField()
                    .accessibilityIdentifier("inventory.prompt.field")
                Button("Cancel", role: .cancel) {}
                Button(prompt.confirmTitle) { Task { await presentation.submit(prompt, in: model) } }
            } message: { prompt in
                Text(prompt.message)
            }
            .confirmationDialog(
                presentation.confirmDelete.map { "Delete \($0.name) from the \(model.space.phrase)?" } ?? "",
                isPresented: Binding(get: { presentation.confirmDelete != nil }, set: { if !$0 { presentation.confirmDelete = nil } }),
                titleVisibility: .visible,
                presenting: presentation.confirmDelete
            ) { item in
                Button("Delete", role: .destructive) { Task { await model.delete(item) } }
            }
    }

    private var promptShown: Binding<Bool> {
        Binding(get: { presentation.prompt != nil }, set: { if !$0 { presentation.prompt = nil } })
    }
}
