import HassCore
import HassDesign
import SwiftUI

/// The item editor (web `InventoryItemDetailsModal`): one section per batch with quantity, expiration date,
/// prepared food and delete, each saved on its own.
///
/// `.sheet` presents it modally (iPhone, folded and portrait layouts); `.pane` draws it in the trailing half of
/// a split window with its own header and Close button. Saves and deletes block closing until they finish.
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
                NavigationStack {
                    form
                        .modalChrome()
                        .navigationTitle(model.title)
                        .inlineNavigationTitle()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { closeButton }
                        }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(model.dismissalBlocked ? .hidden : .visible)
                .interactiveDismissDisabled(model.dismissalBlocked)
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
                        closeButton
                    }
                    .padding(.horizontal, HassTokens.Spacing.l)
                    .frame(minHeight: 56)
                    Divider()
                    form
                }
                .overlay(alignment: .leading) { Divider().ignoresSafeArea() }
            }
        }
        // The app accent reads 2.5:1 as button text (Reset, Save); the floating actions' teal reads 5.8:1.
        .tint(FloatingActionBar.tint)
        .onChange(of: model.isFinished) { _, finished in if finished { onClose() } }
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
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(InventoryTone.color(.expired))
                        .accessibilityIdentifier("inventory.editor.error")
                }
            }
            ForEach(model.batches) { batch in
                BatchSection(model: model, batch: batch) { prompt = $0; promptText = "1" }
            }
        }
        .accessibilityIdentifier("inventory.editor")
    }

    private var closeButton: some View {
        SheetCloseButton(identifier: "inventory.editor.close", action: onClose)
            .disabled(model.dismissalBlocked)
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

/// One batch: heading, location, quantity stepper, expiration date, prepared toggle, hint, Reset and Save.
private struct BatchSection: View {
    @Bindable var model: InventoryEditorModel
    var batch: InventoryBatch
    var ask: (EditorPrompt) -> Void

    var body: some View {
        let qualifier = model.batchName(batch)
        let disabled = model.isDisabled(batch)
        let quantity = model.quantity(batch)
        Section {
            // The batch's heading is the section's first row: as a custom section header the audit reported its
            // text clipped at large sizes.
            VStack(alignment: .leading, spacing: 2) {
                Text(model.heading(batch))
                    .font(.headline)
                    .foregroundStyle(HassTokens.Ink.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(model.locationLine(batch))
                    .font(.subheadline)
                    .foregroundStyle(HassTokens.Ink.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("inventory.editor.batch")

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
                Task { if let prompt = await EditorPrompt.delete(batch, in: model) { ask(prompt) } }
            } label: {
                // Icon and text rather than a Label: the Label's title was reported clipped at large sizes.
                HStack(spacing: HassTokens.Spacing.m) {
                    Image(systemName: "trash").accessibilityHidden(true)
                    Text("Delete").fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if case .delete(batch.key) = model.busy {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(InventoryTone.color(.expired))
            }
            .disabled(disabled)
            .accessibilityLabel(model.busy == .delete(batch.key) ? "Deleting \(qualifier)" : "Delete \(qualifier)")
            .accessibilityIdentifier("inventory.editor.delete")
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
