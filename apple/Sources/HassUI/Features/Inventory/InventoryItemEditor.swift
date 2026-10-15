import HassCore
import HassDesign
import SwiftUI

/// The item editor (web `InventoryItemDetailsModal`; direction G mockup n6-item-editor): one group per batch with
/// quantity, expiration date, prepared food and delete, under a header naming its expiry and place.
///
/// `.sheet` is an edit sheet (direction G, Sheets): circle x Cancel drops the drafts, the filled check saves every
/// changed batch, and Reset Changes is a list row. `.pane` draws it in the trailing half of a split window with its own
/// header, Close, and Save Changes as a list row. Prepared food and delete still apply at once, as on the web. Saves
/// and deletes block closing until they finish.
struct InventoryItemEditor: View {
    enum Style { case sheet, pane }

    @Bindable var model: InventoryEditorModel
    var style: Style
    var onClose: () -> Void

    @State private var prompt: EditorPrompt?
    @State private var promptText = ""
    /// Save is walking the changed batches; the editor closes when it finishes, not after the first batch.
    @State private var isSavingAll = false

    var body: some View {
        Group {
            switch style {
            case .sheet:
                NavigationStack {
                    form
                        .modalChrome()
                        .navigationTitle(model.title)
                        .inlineNavigationTitle()
                        // "Quantity 3 · In the pantry" (iOS 26; the title alone before).
                        .sheetSubtitle(model.summary)
                        .toolbar {
                            SheetCancelItem(identifier: "inventory.editor.close", isEnabled: !model.dismissalBlocked && !isSavingAll) { onClose() }
                            SheetConfirmItem("Save", isEnabled: canSave, isBusy: isSaving, busyTitle: "Saving",
                                             identifier: "inventory.editor.save") { saveAll() }
                        }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(model.dismissalBlocked ? .hidden : .visible)
                .interactiveDismissDisabled(model.dismissalBlocked || isSavingAll)
            case .pane:
                // Its own header rather than a nested NavigationStack, which took over the window's navigation
                // bar (the page title disappeared and Close moved to the window's bar).
                VStack(spacing: 0) {
                    HStack(spacing: HassTokens.Spacing.m) {
                        Text(model.title)
                            .font(.headline)
                            .foregroundStyle(HassTokens.Ink.primary)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 0)
                        SheetCloseButton(identifier: "inventory.editor.close", action: onClose)
                            .disabled(model.dismissalBlocked || isSavingAll)
                    }
                    .padding(.horizontal, HassTokens.Spacing.l)
                    .frame(minHeight: 56)
                    Divider()
                    form
                }
                .overlay(alignment: .leading) { Divider().ignoresSafeArea() }
            }
        }
        .onChange(of: model.isFinished) { _, finished in if finished, !isSavingAll { onClose() } }
        .alert(prompt?.title ?? "", isPresented: promptShown, presenting: prompt) { prompt in
            TextField("Quantity", text: $promptText)
                .numericEntryField()
                .accessibilityIdentifier("inventory.editor.prompt.field")
            Button("Cancel", role: .cancel) {}
            Button(prompt.confirmTitle) { Task { await prompt.submit(promptText, to: model) } }
        } message: { prompt in
            Text(prompt.message)
        }
    }

    private var form: some View {
        Form {
            if let error = model.error {
                Section {
                    InlineAlert(error, severity: .error)
                        .accessibilityIdentifier("inventory.editor.error")
                }
            }
            ForEach(model.batches) { batch in
                BatchSection(model: model, batch: batch, showsPreparedNote: batch.id == model.batches.first?.id) {
                    prompt = $0
                    promptText = "1"
                }
            }
            if !model.changedBatches.isEmpty {
                ChangesSection(model: model, showsSave: style == .pane, isSaving: isSaving, canSave: canSave) { saveAll() }
            }
        }
        .accessibilityIdentifier("inventory.editor")
    }

    // MARK: - Save

    /// Some batch has a draft and nothing is in flight.
    private var canSave: Bool { !model.changedBatches.isEmpty && model.busy == nil && !isSavingAll }

    private var isSaving: Bool {
        if isSavingAll { return true }
        if case .save = model.busy { return true }
        return false
    }

    private func saveAll() {
        isSavingAll = true
        Task {
            await model.saveChanges()
            isSavingAll = false
            if model.isFinished, model.error == nil { onClose() }
        }
    }

    // MARK: - Prompts

    private var promptShown: Binding<Bool> {
        Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })
    }
}

extension InventoryEditorModel {
    /// The item name plus the batch's qualifier (`Black Beans expiring 10/14/2026`), as the web's
    /// `${title}${qualifier}` in control labels and prompts.
    func batchName(_ batch: InventoryBatch) -> String {
        title + qualifier(batch)
    }

    /// The sheet's subtitle (mockup n6-item-editor): `Quantity 3 · In the Pantry`, without the place when the batches
    /// sit in different places.
    var summary: String {
        let quantity = "Quantity \(InventoryFormat.quantity(batches.reduce(0) { $0 + $1.quantity }))"
        let places = Set(batches.map(\.locationPhrase))
        guard places.count == 1, let place = places.first else { return quantity }
        return "\(quantity) · In the \(place.capitalized)"
    }

    /// A batch's group header: `Expires Jun 9, 2027 · In the Pantry` with several batches, the place alone with one
    /// (the sheet title already names the item).
    func header(_ batch: InventoryBatch) -> String {
        multipleBatches ? "\(heading(batch)) · \(locationLine(batch))" : locationLine(batch)
    }

    /// Batches with a quantity or expiry draft.
    var changedBatches: [InventoryBatch] { batches.filter(hasChanges) }

    /// Saves every changed batch in turn (the edit sheet's one Save), stopping at the first error. Each batch runs the
    /// same calls its own Save made before direction G; ``isFinished`` is set by the first that succeeds.
    func saveChanges() async {
        for batch in changedBatches {
            await save(batch)
            if error != nil { return }
        }
    }

    /// Under the editor's first group and the Add Item review's details (mockups n6-item-editor, n6-scan-review).
    static let preparedFoodNote = "Prepared Food marks an item that does not need classification."

    /// Puts every batch's drafts back (Reset Changes).
    func resetChanges() {
        for batch in changedBatches { reset(batch) }
    }
}

/// How many of a batch a delete or prepared-food change applies to.
enum EditorPrompt: Identifiable {
    case delete(InventoryBatch, qualifier: String)
    case prepared(InventoryBatch, qualifier: String)

    var batch: InventoryBatch {
        switch self {
        case let .delete(batch, _), let .prepared(batch, _): batch
        }
    }

    var id: String {
        switch self {
        case let .delete(batch, _): "delete-\(batch.key)"
        case let .prepared(batch, _): "prepared-\(batch.key)"
        }
    }

    var title: String {
        switch self {
        case let .delete(_, qualifier): "Delete \(qualifier)"
        case let .prepared(batch, qualifier): batch.preparedFood ? "Unmark \(qualifier) as Prepared" : "Mark \(qualifier) as Prepared"
        }
    }

    var message: String {
        let max = InventoryFormat.quantity(batch.quantity)
        switch self {
        case .delete: return "Choose how many to delete. Enter a number from 1 to \(max)."
        case .prepared: return "Choose how many to change. Enter a number from 1 to \(max)."
        }
    }

    var confirmTitle: String {
        switch self {
        case .delete: "Delete"
        case .prepared: "Change"
        }
    }

    /// Applies the prompt to the entered quantity (1 to the batch's quantity), or reports it as invalid.
    @MainActor
    func submit(_ text: String, to model: InventoryEditorModel) async {
        guard let quantity = InventoryFormat.parseQuantity(text), quantity >= 1, quantity <= batch.quantity else {
            model.reportInvalidQuantity(max: batch.quantity)
            return
        }
        switch self {
        case .delete: await model.delete(batch, quantity: quantity)
        case .prepared: await model.togglePrepared(batch, quantity: quantity)
        }
    }

    /// Delete on a batch: the prompt asking how many when it holds more than one; otherwise deletes it and
    /// returns `nil`.
    @MainActor
    static func delete(_ batch: InventoryBatch, in model: InventoryEditorModel) async -> EditorPrompt? {
        guard batch.quantity <= 1 else { return .delete(batch, qualifier: model.batchName(batch)) }
        await model.delete(batch)
        return nil
    }

    /// Prepared food flipped on a batch: the prompt asking how many when it holds more than one; otherwise
    /// flips it and returns `nil`.
    @MainActor
    static func prepared(_ batch: InventoryBatch, in model: InventoryEditorModel) async -> EditorPrompt? {
        guard batch.quantity <= 1 else { return .prepared(batch, qualifier: model.batchName(batch)) }
        await model.togglePrepared(batch)
        return nil
    }
}

/// One batch (mockup n6-item-editor): a header with its expiry and place, then Quantity, Expiration Date, Expires,
/// Prepared Food and a red Delete row; the footer carries what saving would change.
private struct BatchSection: View {
    @Bindable var model: InventoryEditorModel
    var batch: InventoryBatch
    /// The first group explains Prepared Food in its footer.
    var showsPreparedNote: Bool
    var ask: (EditorPrompt) -> Void

    var body: some View {
        let qualifier = model.batchName(batch)
        let disabled = model.isDisabled(batch)
        let quantity = model.quantity(batch)
        Section {
            Stepper(value: quantityBinding, in: model.minimumQuantity(batch)...InventoryCatalog.maxQuantity, step: 1) {
                LabeledContent("Quantity", value: InventoryFormat.quantity(quantity))
            }
            .disabled(disabled)
            .accessibilityLabel("Quantity of \(qualifier)")
            .accessibilityValue(InventoryFormat.quantity(quantity))
            .accessibilityIdentifier("inventory.editor.quantity")

            Toggle("Expiration Date", isOn: hasExpiryBinding)
                .disabled(disabled)
                .accessibilityLabel("Expiration date for \(qualifier)")
                .accessibilityIdentifier("inventory.editor.hasExpiry")
            if !model.expiry(batch).isEmpty {
                DatePicker("Expires", selection: expiryBinding, displayedComponents: .date)
                    .disabled(disabled)
                    .accessibilityLabel("Expires, \(qualifier)")
                    .accessibilityIdentifier("inventory.editor.expiry")
            }

            Toggle(isOn: preparedBinding) {
                HStack(spacing: HassTokens.Spacing.s) {
                    Text("Prepared Food")
                    if case .prepared(batch.key) = model.busy {
                        ArcSpinner(.inline, label: "Updating prepared food")
                    }
                }
            }
            .disabled(disabled)
            .accessibilityLabel("Prepared food, \(qualifier)")
            .accessibilityIdentifier("inventory.editor.prepared")

            Button(role: .destructive) {
                Task { if let prompt = await EditorPrompt.delete(batch, in: model) { ask(prompt) } }
            } label: {
                // Text and a trailing glyph rather than a Label: the Label's title was reported clipped at large sizes.
                HStack(spacing: HassTokens.Spacing.m) {
                    Text("Delete").fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if case .delete(batch.key) = model.busy {
                        ArcSpinner(.inline, label: "Deleting")
                    } else {
                        Image(systemName: "trash").accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
                .foregroundStyle(HassTokens.Ink.danger)
                .contentShape(Rectangle())
            }
            .disabled(disabled)
            .accessibilityLabel(model.busy == .delete(batch.key) ? "Deleting \(qualifier)" : "Delete \(qualifier)")
            .accessibilityIdentifier("inventory.editor.delete")
        } header: {
            FormHeader(model.header(batch))
                .textCase(nil)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("inventory.editor.batch")
        } footer: {
            let notes = [model.hint(batch), showsPreparedNote ? InventoryEditorModel.preparedFoodNote : nil].compactMap { $0 }
            if !notes.isEmpty {
                FormFooter(notes.joined(separator: "\n"))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(model.hint(batch) == nil ? "inventory.editor.note" : "inventory.editor.hint")
            }
        }
    }

    // MARK: - Bindings

    private var quantityBinding: Binding<Double> {
        Binding(get: { model.quantity(batch) }, set: { model.setQuantity($0, for: batch) })
    }

    private var hasExpiryBinding: Binding<Bool> {
        Binding(
            get: { !model.expiry(batch).isEmpty },
            set: { on in model.setExpiry(on ? model.calendar.isoString(model.calendar.today) : "", for: batch) }
        )
    }

    private var expiryBinding: Binding<Date> {
        Binding(
            get: { model.calendar.date(fromISO: model.expiry(batch)) ?? model.calendar.today },
            set: { model.setExpiry(model.calendar.isoString($0), for: batch) }
        )
    }

    /// Flipping prepared asks how many when the batch holds more than one.
    private var preparedBinding: Binding<Bool> {
        Binding(
            get: { batch.preparedFood },
            set: { _ in
                Task { if let prompt = await EditorPrompt.prepared(batch, in: model) { ask(prompt) } }
            }
        )
    }
}

/// Reset Changes, a list row in the action tint (direction G, Sheets: "Reset is a list row"), shown while any batch has a
/// draft; the split pane adds Save Changes, since it has no toolbar for the sheet's check.
private struct ChangesSection: View {
    var model: InventoryEditorModel
    var showsSave: Bool
    var isSaving: Bool
    var canSave: Bool
    var onSave: () -> Void

    var body: some View {
        Section {
            if showsSave {
                Button(action: onSave) {
                    HStack(spacing: HassTokens.Spacing.s) {
                        Text("Save Changes").bold().fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if isSaving { ArcSpinner(.inline, label: "Saving") }
                    }
                    .foregroundStyle(HassTokens.Ink.action)
                    .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .accessibilityLabel(isSaving ? "Saving \(model.title)" : "Save \(model.title)")
                .accessibilityIdentifier("inventory.editor.save")
            }
            Button { model.resetChanges() } label: {
                Text("Reset Changes")
                    .foregroundStyle(HassTokens.Ink.action)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.busy != nil || isSaving)
            .accessibilityLabel("Reset Changes to \(model.title)")
            .accessibilityIdentifier("inventory.editor.reset")
        }
    }
}
