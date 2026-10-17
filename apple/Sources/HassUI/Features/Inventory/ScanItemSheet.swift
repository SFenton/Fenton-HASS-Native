import HassCore
import HassDesign
import SwiftUI

/// Add Item (web `ScanItemCameraSheet`; direction G mockups n6-scan-item and n6-scan-review): scan or type the product,
/// read or pick the expiration date, review, then add through `evershelf.add_scanned_item`. `onAdded` runs once after
/// a successful add.
///
/// A multi-step create sheet (direction G, Sheets): circle x Cancel on the first step, a Back circle on later steps,
/// and on the review step the filled check adds the item. The step's subtitle ("Scan Barcode · Step 1 of 3") sits
/// under the title on iOS 26 and heads the form before.
struct ScanItemSheet: View {
    @Bindable var model: ScanItemModel
    var onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var camera: ScanCameraController
    @State private var reportedAdd = false

    init(model: ScanItemModel, camera: ScanCameraController = ScanCameraController(), onAdded: @escaping () -> Void) {
        self.model = model
        self.onAdded = onAdded
        _camera = State(initialValue: camera)
    }

    var body: some View {
        NavigationStack {
            // The form and the step's buttons are stacked, not overlaid: as a bottom safe-area inset the buttons
            // covered the form's last row at its maximum scroll on short screens (unfolded Duo landscape, iPad
            // landscape), so Manually Enter Name could not be reached.
            VStack(spacing: 0) {
                Form {
                    header
                    if model.isProcessing {
                        processing
                    } else {
                        switch model.step {
                        case .barcode: barcodePage
                        case .expiry: expiryPage
                        case .review: reviewPage
                        case .adding: addingPage
                        }
                    }
                    // At accessibility sizes the step's buttons scroll with the form: pinned, they took about 40% of
                    // the iPhone screen and left the form a short window.
                    if typeSize.isAccessibilitySize, showsFooter {
                        Section { footerButtons }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }
                }
                // On the form itself: on the stack it would replace the footer buttons' identifiers.
                .accessibilityIdentifier("scan.\(model.step.rawValue)")
                if !typeSize.isAccessibilitySize { footer }
            }
            .modalChrome()
            .navigationTitle("Add Item")
            .inlineNavigationTitle()
            .sheetSubtitle(model.subtitle)
            .toolbar { toolbar }
        }
        .hassSheet(.form, height: .full) // Live camera scanner
        .presentationBackground(Self.surface)
        .interactiveDismissDisabled(model.addStatus == .adding)
        .task(id: CameraKey(step: model.step, wanted: model.wantedCamera)) { await camera.sync(with: model) }
        .onDisappear { camera.stop() }
        .onChange(of: model.addStatus) { _, status in
            if status == .added, !reportedAdd {
                reportedAdd = true
                onAdded()
            }
        }
    }

    /// Opaque sheet and footer surface: on the iPad form sheet's glass and the footer's bar material the audit
    /// failed dark labels ("Skip Barcode", "Manually Enter Name") that read well on screen (2026-10-12).
    static var surface: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    private struct CameraKey: Hashable {
        var step: ScanItemModel.Step
        var wanted: ScanItemModel.Step?
    }

    // MARK: - Chrome

    /// Cancel on the first step, Back on the later ones (direction G, Sheets: "Multi-step flows put Back leading on
    /// later steps"), Add as the filled check on review, and Close once the item is added.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if model.step == .barcode {
            SheetCancelItem(identifier: "scan.cancel") { dismiss() }
        }
        if model.step == .expiry || model.step == .review {
            ToolbarItem(placement: .navigation) {
                Button {
                    model.goBack()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel(model.step == .expiry ? "Back to Barcode Scan" : "Back to Expiration Date")
                .accessibilityIdentifier("scan.back")
            }
        }
        if model.step == .review {
            SheetConfirmItem("Add to \(model.location.title)", isEnabled: model.canAdd, identifier: "scan.add") {
                Task { await model.add() }
            }
        }
        if model.step == .adding, model.addStatus == .added {
            SheetCloseItem(identifier: "scan.done") { dismiss() }
        }
    }

    /// The step's instructions, led by its subtitle where the system can't draw one under the title.
    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                if !SheetSubtitle.isShown {
                    Text(model.subtitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HassTokens.Ink.secondary)
                        .accessibilityIdentifier("scan.subtitle")
                }
                if !model.instructions.isEmpty, !model.isProcessing {
                    Text(model.instructions)
                        .foregroundStyle(HassTokens.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .listRowBackground(Color.clear)
    }

    /// The step has buttons to show: the barcode and expiry steps, while nothing is processing. Review adds from the
    /// toolbar's check; the result closes from the toolbar.
    private var showsFooter: Bool {
        !model.isProcessing && (model.step == .barcode || model.step == .expiry)
    }

    @ViewBuilder
    private var footer: some View {
        if showsFooter {
            footerButtons
                .padding(.horizontal, HassTokens.Spacing.l)
                .padding(.vertical, HassTokens.Spacing.s)
                .background(Self.surface)
        }
    }

    /// One filled button at most (direction G, Controls: Primary buttons): the step's forward action once there is
    /// something to carry forward, else Read Expiration Date; the other is a grey capsule.
    private var footerButtons: some View {
        VStack(spacing: HassTokens.Spacing.s) {
            switch model.step {
            case .barcode:
                footerButton(model.barcodeForwardTitle, prominent: model.hasBarcodeValue, id: "scan.forward") { model.goToExpiryStep() }
                    .disabled(model.barcodeForwardDisabled)
            case .expiry:
                if model.canReadExpiry {
                    footerButton(model.readExpiryTitle, prominent: !model.hasExpiryValue, id: "scan.readExpiry") {
                        Task { await camera.captureExpiry(for: model) }
                    }
                }
                footerButton(model.expiryForwardTitle, prominent: model.hasExpiryValue, id: "scan.forward") { model.goToReviewStep() }
                    .disabled(model.expiryForwardDisabled)
            case .review, .adding:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func footerButton(_ title: String, prominent: Bool, id: String, action: @escaping () -> Void) -> some View {
        if prominent {
            PrimaryButton(title, action: action)
                .accessibilityIdentifier(id)
        } else {
            // A grey capsule (mockup `.n6-btn.sec`), tinted with ink: the audit judges a bordered button by its tint
            // even when the label is restyled (iPad, 2026-10-12).
            Button(action: action) {
                Text(title).font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(HassTokens.Ink.primary)
            .accessibilityIdentifier(id)
        }
    }

    // MARK: - Pages

    private var processing: some View {
        Section {
            HStack(spacing: HassTokens.Spacing.m) {
                ArcSpinner(.compact).accessibilityHidden(true)
                Text("Processing…").font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("scan.processing")
        }
    }

    @ViewBuilder
    private var barcodePage: some View {
        if !model.barcodeCameraHidden {
            cameraSection(symbol: "barcode.viewfinder", label: "Live item scan camera feed",
                          manualTitle: "Manually Enter Name", manualID: "scan.manualName") { model.enterNameManually() }
        } else {
            statusSection
            Section {
                productNameField
                Button(model.scanBarcodeTitle) { model.scanBarcodeAgain() }
                    .foregroundStyle(HassTokens.Ink.action)
                    .accessibilityIdentifier("scan.scanAgain")
            } header: { FormHeader("What item are you adding?").textCase(nil) }
        }
    }

    @ViewBuilder
    private var expiryPage: some View {
        if !model.expiryCameraHidden {
            cameraSection(symbol: "camera", label: "Live expiration date camera feed",
                          manualTitle: "Manually Enter Expiration Date", manualID: "scan.manualExpiry") { model.enterExpiryManually() }
        } else {
            statusSection
            Section {
                expiryField
            } header: { FormHeader("When does it expire?").textCase(nil) }
            Section {
                ForEach(ScanItemModel.QuickExpiry.allCases) { quick in
                    FilterOptionRow(title: quick.title, isSelected: model.selectedQuickExpiry == quick) { model.selectQuickExpiry(quick) }
                        .accessibilityIdentifier("scan.quick.\(quick.rawValue)")
                }
            } header: { FormHeader("Quick Expiration Dates").textCase(nil) }
            Section {
                Button(model.readExpiryTitle) { model.readExpiryAgain() }
                    .foregroundStyle(HassTokens.Ink.action)
                    .disabled(camera.source == .unavailable)
                    .accessibilityIdentifier("scan.readAgain")
            }
        }
    }

    /// Review (mockup n6-scan-review): the product, its details in one group, then where it goes.
    @ViewBuilder
    private var reviewPage: some View {
        Section {
            ScanProductHeader(name: model.name, barcode: model.detectedBarcode)
        }
        Section {
            productNameField
            quantityRow
            expiryField
            Toggle("Prepared Food", isOn: Binding(get: { model.preparedFood }, set: { _ in model.togglePreparedFood() }))
                .accessibilityIdentifier("scan.prepared")
        } header: {
            FormHeader("What item are you adding?").textCase(nil)
        } footer: {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                if let error = model.quantityError {
                    Text(error)
                        .foregroundStyle(HassTokens.Ink.error)
                        .accessibilityIdentifier("scan.quantityError")
                }
                FormFooter(InventoryEditorModel.preparedFoodNote)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        Section {
            ForEach(StorageLocation.allCases, id: \.self) { location in
                FilterOptionRow(title: location.title, isSelected: model.location == location) { model.selectLocation(location) }
                    .accessibilityIdentifier("scan.location.\(location.rawValue)")
            }
        } header: {
            FormHeader("Where should it be stored?").textCase(nil)
        } footer: {
            FormFooter(model.locationHint).accessibilityIdentifier("scan.locationHint")
        }
        if let error = model.addError {
            Section {
                InlineAlert(error, severity: .error)
                    .accessibilityIdentifier("scan.addError")
            }
        }
    }

    private var addingPage: some View {
        Section {
            VStack(spacing: HassTokens.Spacing.m) {
                if model.addStatus == .added {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(InventoryTone.success)
                        .accessibilityHidden(true)
                    Text("Added to \(model.location.title)").font(.headline)
                } else {
                    ArcSpinner(.compact).accessibilityHidden(true)
                    Text("Adding to \(model.location.title)…").font(.headline)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("scan.result")
        }
    }

    // MARK: - Parts

    @ViewBuilder
    private var statusSection: some View {
        if let message = model.statusMessage {
            Section {
                InlineAlert(message, severity: model.statusIsError ? .error : .warning)
                    .accessibilityIdentifier("scan.status")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    /// Name, as a labelled row with the value trailing (mockup n6-scan-review).
    private var productNameField: some View {
        LabeledContent("Name") {
            TextField("Product Name", text: nameBinding)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .accessibilityLabel("Product name")
                .accessibilityIdentifier("scan.name")
        }
    }

    /// How Many: the typed quantity (validated on Add, as on the web) with a stepper beside it.
    private var quantityRow: some View {
        HStack(spacing: HassTokens.Spacing.m) {
            Text("How Many")
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            TextField("Quantity", text: quantityBinding)
                .numericEntryField()
                .multilineTextAlignment(.trailing)
                .frame(minWidth: HassTokens.minTarget, maxWidth: 80)
                .onSubmit { _ = model.validateQuantity() }
                .accessibilityLabel("Quantity")
                .accessibilityIdentifier("scan.quantity")
            Stepper("How Many", value: quantityStepBinding, in: 1...Int(InventoryCatalog.maxQuantity))
                .labelsHidden()
                .accessibilityLabel("How Many")
                .accessibilityIdentifier("scan.quantity.stepper")
        }
    }

    /// Optional date: a toggle plus a picker, as the web's empty-able date input. "Read from the package" under Expires
    /// once the camera read it.
    @ViewBuilder
    private var expiryField: some View {
        Toggle("Expiration Date", isOn: Binding(
            get: { !model.expiryDate.isEmpty },
            set: { model.setExpiryDate($0 ? model.calendar.isoString(model.calendar.today) : "") }
        ))
        .accessibilityIdentifier("scan.hasExpiry")
        if !model.expiryDate.isEmpty {
            DatePicker(selection: Binding(
                get: { model.calendar.date(fromISO: model.expiryDate) ?? model.calendar.today },
                set: { model.setExpiryDate(model.calendar.isoString($0)) }
            ), displayedComponents: .date) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Expires")
                    if model.hasSuccessfulExpiryRead {
                        Text("Read from the package")
                            .font(.subheadline)
                            .foregroundStyle(HassTokens.Ink.secondary)
                    }
                }
            }
            .accessibilityLabel("Expiration date")
            .accessibilityIdentifier("scan.expiry")
        }
    }

    /// The camera card (26 pt corners, on the sheet ground) with its status pill, and manual entry under it in the
    /// action tint (mockup n6-scan-item).
    private func cameraSection(symbol: String, label: String, manualTitle: String, manualID: String,
                               manual: @escaping () -> Void) -> some View {
        Section {
            viewfinder(symbol: symbol, label: label)
            Button(action: manual) {
                Label(manualTitle, systemImage: "keyboard")
                    .foregroundStyle(HassTokens.Ink.action)
                    .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(manualID)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func viewfinder(symbol: String, label: String) -> some View {
        ZStack {
            Rectangle().fill(Color.black)
            switch camera.source {
            case .live:
                #if os(iOS)
                CameraPreview(session: camera.box.session)
                    .accessibilityLabel(label)
                #endif
            case .simulated:
                VStack(spacing: HassTokens.Spacing.m) {
                    Image(systemName: symbol).font(.system(size: 56)).foregroundStyle(.white.opacity(0.8))
                    Button(model.step == .barcode ? "Simulate Scan" : "Simulate Photo") {
                        Task { await camera.simulate(on: model) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HassTokens.Ink.actionFill)
                    .accessibilityIdentifier("scan.simulate")
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(label)
            case .unavailable:
                EmptyView()
            }
            if model.cameraStatus != .ready {
                VStack(spacing: HassTokens.Spacing.s) {
                    if case .failed = model.cameraStatus {
                        Image(systemName: "exclamationmark.circle").font(.system(size: 42))
                    } else {
                        ArcSpinner(.page).accessibilityHidden(true)
                    }
                    Text(cameraStatusText).multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .padding()
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("scan.cameraStatus")
            }
        }
        .overlay(alignment: .bottom) {
            if let status = cameraActivity {
                CameraStatusPill(text: status)
                    .padding(.bottom, HassTokens.Spacing.l)
                    .padding(.horizontal, HassTokens.Spacing.m)
            }
        }
        // Portrait like the mockup's 4:5 card; capped on wide sheets (iPad), where a full-width feed pushed the
        // manual-entry button under the pinned footer.
        .aspectRatio(4 / 5, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: HassTokens.Radius.module))
        .frame(maxWidth: 400)
        .frame(maxWidth: .infinity)
        .listRowInsets(EdgeInsets())
        .accessibilityIdentifier("scan.camera")
    }

    /// What the running camera is doing, for the pill over the feed: "Looking for a Barcode" while scanning, "Looking Up
    /// Product" while a barcode resolves, "Reading Expiration Date" while a photo is read.
    private var cameraActivity: String? {
        guard model.cameraStatus == .ready else { return nil }
        switch model.step {
        case .barcode:
            switch model.lookupStatus {
            case .resolving: return "Looking Up Product"
            case .idle, .scanning: return "Looking for a Barcode"
            default: return nil
            }
        case .expiry:
            return model.expiryStatus == .reading ? "Reading Expiration Date" : nil
        case .review, .adding:
            return nil
        }
    }

    private var cameraStatusText: String {
        if case let .failed(message) = model.cameraStatus { return message }
        return "Starting camera…"
    }

    // MARK: - Bindings

    private var nameBinding: Binding<String> {
        Binding(get: { model.name }, set: { model.setName($0) })
    }

    private var quantityBinding: Binding<String> {
        Binding(get: { model.quantityText }, set: { model.setQuantityText($0) })
    }

    /// The stepper's view of the typed quantity: its whole number within the stepper's range (1 when the text isn't a
    /// number); stepping writes the new number back as text.
    private var quantityStepBinding: Binding<Int> {
        Binding(
            get: {
                guard let value = Double(model.quantityText.trimmingCharacters(in: .whitespaces)), value.isFinite else { return 1 }
                return Int(min(max(value, 1), InventoryCatalog.maxQuantity))
            },
            set: { model.setQuantityText(String($0)) }
        )
    }
}

