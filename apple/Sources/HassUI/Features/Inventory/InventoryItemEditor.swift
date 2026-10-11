import HassCore
import HassDesign
import SwiftUI

/// The item editor (web `InventoryItemDetailsModal`): one section per batch with quantity, expiration date,
/// prepared food and delete, each saved on its own.
///
/// `.sheet` presents it modally (iPhone, folded and portrait layouts); `.pane` draws it in the trailing half of
/// a split window with a Close button instead of Done. Saves and deletes block closing until they finish.
struct InventoryItemEditor: View {
    enum Style { case sheet, pane }

    @Bindable var model: InventoryEditorModel
    var style: Style
    var onClose: () -> Void

    @State private var prompt: EditorPrompt?
    @State private var promptText = ""

    var body: some View {
        Group {
            switch style {
            case .sheet:
                NavigationStack { form }
                    .presentationDetents([.large])
                    .presentationDragIndicator(model.dismissalBlocked ? .hidden : .visible)
                    .interactiveDismissDisabled(model.dismissalBlocked)
            case .pane:
                NavigationStack { form }
                    .overlay(alignment: .leading) { Divider().ignoresSafeArea() }
            }
        }
        .onChange(of: model.isFinished) { _, finished in if finished { onClose() } }
        .alert(prompt?.title ?? "", isPresented: promptShown, presenting: prompt) { prompt in
            TextField("Quantity", text: $promptText)
                .numericEntryField()
                .accessibilityIdentifier("inventory.editor.prompt.field")
            Button("Cancel", role: .cancel) {}
            Button(prompt.confirmTitle) { submit(prompt) }
        } message: { prompt in
            Text(prompt.message)
        }
    }

    private var form: some View {
        Form {
            if let error = model.error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(InventoryTone.color(.expired))
                        .accessibilityIdentifier("inventory.editor.error")
                }
            }
            ForEach(model.batches) { batch in
                BatchSection(model: model, batch: batch) { prompt = $0; promptText = "1" }
            }
        }
        .navigationTitle(model.title)
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(style == .pane ? "Close" : "Done", action: onClose)
                    .disabled(model.dismissalBlocked)
                    .accessibilityIdentifier("inventory.editor.close")
            }
        }
        .accessibilityIdentifier("inventory.editor")
    }

    // MARK: - Prompts

    private var promptShown: Binding<Bool> {
        Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })
    }

    private func submit(_ prompt: EditorPrompt) {
        let batch = prompt.batch
        guard let quantity = InventoryFormat.parseQuantity(promptText), quantity >= 1, quantity <= batch.quantity else {
            model.reportInvalidQuantity(max: batch.quantity)
            return
        }
        switch prompt {
        case .delete: Task { await model.delete(batch, quantity: quantity) }
        case .prepared: Task { await model.togglePrepared(batch, quantity: quantity) }
        }
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
}

/// One batch: heading, location, quantity stepper, expiration date, prepared toggle, hint, Reset and Save.
private struct BatchSection: View {
    @Bindable var model: InventoryEditorModel
    var batch: InventoryBatch
    var ask: (EditorPrompt) -> Void

    var body: some View {
        let qualifier = model.qualifier(batch)
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
                        ProgressView().accessibilityLabel("Updating prepared food")
                    }
                }
            }
            .disabled(disabled)
            .accessibilityLabel("Prepared food, \(qualifier)")
            .accessibilityIdentifier("inventory.editor.prepared")

            if let hint = model.hint(batch) {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .accessibilityIdentifier("inventory.editor.hint")
            }

            if model.hasChanges(batch) {
                HStack {
                    Button("Reset") { model.reset(batch) }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Reset \(qualifier)")
                        .accessibilityIdentifier("inventory.editor.reset")
                    Spacer()
                    Button {
                        Task { await model.save(batch) }
                    } label: {
                        if case .save(batch.key) = model.busy {
                            ProgressView()
                        } else {
                            Text("Save").bold()
                        }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(model.busy == .save(batch.key) ? "Saving \(qualifier)" : "Save \(qualifier)")
                    .accessibilityIdentifier("inventory.editor.save")
                }
                .disabled(disabled)
                .frame(minHeight: HassTokens.minTarget)
            }

            Button(role: .destructive) {
                if batch.quantity > 1 {
                    ask(.delete(batch, qualifier: qualifier))
                } else {
                    Task { await model.delete(batch) }
                }
            } label: {
                HStack {
                    Label("Delete", systemImage: "trash")
                    if case .delete(batch.key) = model.busy {
                        Spacer()
                        ProgressView()
                    }
                }
                .foregroundStyle(InventoryTone.color(.expired))
            }
            .disabled(disabled)
            .accessibilityLabel(model.busy == .delete(batch.key) ? "Deleting \(qualifier)" : "Delete \(qualifier)")
            .accessibilityIdentifier("inventory.editor.delete")
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.heading(batch))
                    .font(.headline)
                    .foregroundStyle(HassTokens.Ink.primary)
                    .textCase(nil)
                    .accessibilityAddTraits(.isHeader)
                Text(model.locationLine(batch))
                    .font(.subheadline)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .textCase(nil)
            }
            .accessibilityElement(children: .combine)
        }
        .accessibilityIdentifier("inventory.editor.batch")
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
                if batch.quantity > 1 {
                    ask(.prepared(batch, qualifier: model.qualifier(batch)))
                } else {
                    Task { await model.togglePrepared(batch) }
                }
            }
        )
    }
}
