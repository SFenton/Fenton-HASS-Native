import HassCore
import HassDesign
import SwiftUI

/// Add Item (web `ScanItemCameraSheet`): scan or type the product, read or pick the expiration date, review,
/// then add through `evershelf.add_scanned_item`. `onAdded` runs once after a successful add.
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
            .navigationTitle("Add Item")
            .inlineNavigationTitle()
            .toolbar { toolbar }
        }
        // The app accent reads 2.5:1 as button text on the sheet; the floating actions' teal reads 5.8:1.
        .tint(FloatingActionBar.tint)
        .presentationDetents([.large])
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

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if model.step == .expiry || model.step == .review {
                Button {
                    model.goBack()
                } label: {
                    Label("Back", systemImage: "chevron.backward").labelStyle(.titleAndIcon)
                }
                .accessibilityLabel(model.step == .expiry ? "Back to barcode scan" : "Back to expiration date")
                .accessibilityIdentifier("scan.back")
            } else {
                Button("Cancel") { dismiss() }
                    .disabled(model.addStatus == .adding)
                    .accessibilityIdentifier("scan.cancel")
            }
        }
    }

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                Text(model.subtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .accessibilityIdentifier("scan.subtitle")
                if !model.instructions.isEmpty, !model.isProcessing {
                    Text(model.instructions)
                        .foregroundStyle(HassTokens.Ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .listRowBackground(Color.clear)
    }

    /// The step has buttons to show (not while processing or adding).
    private var showsFooter: Bool {
        !model.isProcessing && !(model.step == .adding && model.addStatus != .added)
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

    private var footerButtons: some View {
        VStack(spacing: HassTokens.Spacing.s) {
            switch model.step {
            case .barcode:
                footerButton(model.barcodeForwardTitle, prominent: model.hasBarcodeValue, id: "scan.forward") { model.goToExpiryStep() }
                    .disabled(model.barcodeForwardDisabled)
            case .expiry:
                if model.canReadExpiry {
                    footerButton(model.readExpiryTitle, prominent: true, id: "scan.readExpiry") {
                        Task { await camera.captureExpiry(for: model) }
                    }
                }
                footerButton(model.expiryForwardTitle, prominent: model.hasExpiryValue, id: "scan.forward") { model.goToReviewStep() }
                    .disabled(model.expiryForwardDisabled)
            case .review:
                footerButton("Add", prominent: true, id: "scan.add") { Task { await model.add() } }
                    .disabled(!model.canAdd)
            case .adding:
                footerButton("Done", prominent: true, id: "scan.done") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func footerButton(_ title: String, prominent: Bool, id: String, action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityIdentifier(id)
        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            // Tinted with ink: the teal label on its own teal fill read 4.3:1, and the audit judges a bordered
            // button by its tint even when the label is restyled (iPad, 2026-10-12).
            button.buttonStyle(.bordered).tint(HassTokens.Ink.primary)
        }
    }

    // MARK: - Pages

    private var processing: some View {
        Section {
            HStack(spacing: HassTokens.Spacing.m) {
                ProgressView()
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
            Section {
                viewfinder(symbol: "barcode.viewfinder", label: "Live item scan camera feed")
                Button("Manually Enter Name") { model.enterNameManually() }
                    .accessibilityIdentifier("scan.manualName")
            }
        } else {
            statusSection
            Section("What item are you adding?") {
                TextField("Product name", text: nameBinding)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Product name")
                    .accessibilityIdentifier("scan.name")
                Button(model.scanBarcodeTitle) { model.scanBarcodeAgain() }
                    .accessibilityIdentifier("scan.scanAgain")
            }
        }
    }

    @ViewBuilder
    private var expiryPage: some View {
        if !model.expiryCameraHidden {
            Section {
                viewfinder(symbol: "camera", label: "Live expiration date camera feed")
                Button("Manually Enter Expiration Date") { model.enterExpiryManually() }
                    .accessibilityIdentifier("scan.manualExpiry")
            }
        } else {
            statusSection
            Section("When does it expire?") {
                expiryField
            }
            Section("Quick Expiration Dates") {
                ForEach(ScanItemModel.QuickExpiry.allCases) { quick in
                    FilterOptionRow(title: quick.title, isSelected: model.selectedQuickExpiry == quick) { model.selectQuickExpiry(quick) }
                        .accessibilityIdentifier("scan.quick.\(quick.rawValue)")
                }
            }
            Section {
                Button(model.readExpiryTitle) { model.readExpiryAgain() }
                    .disabled(camera.source == .unavailable)
                    .accessibilityIdentifier("scan.readAgain")
            }
        }
    }

    @ViewBuilder
    private var reviewPage: some View {
        Section("What item are you adding?") {
            TextField("Product name", text: nameBinding)
                .autocorrectionDisabled()
                .accessibilityLabel("Product name")
                .accessibilityIdentifier("scan.name")
        }
        Section {
            TextField("Quantity", text: quantityBinding)
                .numericEntryField()
                .onSubmit { _ = model.validateQuantity() }
                .accessibilityLabel("Quantity")
                .accessibilityIdentifier("scan.quantity")
        } header: {
            Text("How many are you adding?")
        } footer: {
            if let error = model.quantityError {
                Text(error)
                    .foregroundStyle(InventoryTone.color(.expired))
                    .accessibilityIdentifier("scan.quantityError")
            }
        }
        Section {
            ForEach(StorageLocation.allCases, id: \.self) { location in
                FilterOptionRow(title: location.title, isSelected: model.location == location) { model.selectLocation(location) }
                    .accessibilityIdentifier("scan.location.\(location.rawValue)")
            }
        } header: {
            Text("Where should it be stored?")
        } footer: {
            Text(model.locationHint).accessibilityIdentifier("scan.locationHint")
        }
        Section("When does it expire?") {
            expiryField
        }
        Section("Prepared Food") {
            Toggle(isOn: Binding(get: { model.preparedFood }, set: { _ in model.togglePreparedFood() })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prepared Food Item")
                    Text("Indicates this is a prepared food item and does not need classification.")
                        .font(.footnote)
                        .foregroundStyle(HassTokens.Ink.secondary)
                }
            }
            .accessibilityIdentifier("scan.prepared")
        }
        if let error = model.addError {
            Section {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(InventoryTone.color(.expired))
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
                    ProgressView()
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
                Label(message, systemImage: model.statusIsError ? "exclamationmark.circle.fill" : (model.step == .expiry ? "calendar" : "barcode"))
                    .foregroundStyle(model.statusIsError ? InventoryTone.color(.expired) : HassTokens.Ink.primary)
                    .accessibilityIdentifier("scan.status")
            }
        }
    }

    /// Optional date: a toggle plus a picker, as the web's empty-able date input.
    @ViewBuilder
    private var expiryField: some View {
        Toggle("Expiration Date", isOn: Binding(
            get: { !model.expiryDate.isEmpty },
            set: { model.setExpiryDate($0 ? model.calendar.isoString(model.calendar.today) : "") }
        ))
        .accessibilityIdentifier("scan.hasExpiry")
        if !model.expiryDate.isEmpty {
            DatePicker("Expires", selection: Binding(
                get: { model.calendar.date(fromISO: model.expiryDate) ?? model.calendar.today },
                set: { model.setExpiryDate(model.calendar.isoString($0)) }
            ), displayedComponents: .date)
            .accessibilityLabel("Expiration date")
            .accessibilityIdentifier("scan.expiry")
        }
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
                        ProgressView().tint(.white)
                    }
                    Text(cameraStatusText).multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .padding()
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("scan.cameraStatus")
            }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // Capped on wide sheets (iPad): full width, the 4:3 feed pushed the manual-entry button under the
        // pinned footer.
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .listRowInsets(EdgeInsets())
        .accessibilityIdentifier("scan.camera")
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
}
