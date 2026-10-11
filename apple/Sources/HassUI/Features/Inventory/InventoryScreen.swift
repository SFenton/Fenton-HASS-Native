import HassCore
import HassDesign
import SwiftUI

/// An inventory page: All Food, Pantry, Fridge, Freezer, Spice Rack or Cabinet
/// (web `EverShelfInventoryPanel`; spec `.agents/pages/inventory/spec.md`).
///
/// Rows come from `evershelf.list_inventory`. Search sits in the navigation bar; Sort, Filter and Scan Item
/// float at the bottom like the web's floating actions. Multi-batch items open the item editor: as a sheet,
/// or in the trailing half where the window may split (iPad landscape, unfolded iPhone Duo landscape).
struct InventoryScreen: View {
    @Bindable var model: InventoryListModel
    var models: InventoryModels
    /// A sheet or editor to open once rows load (debug gallery and journeys).
    var launch: InventoryLaunch?

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var editing: InventoryEditorModel?
    @State private var sheet: InventorySheet?
    @State private var prompt: InventoryPrompt?
    @State private var promptText = ""
    @State private var confirmDelete: InventoryDisplayItem?
    @State private var canSplit = false
    @State private var searchExpanded = false

    private var space: InventorySpace { model.space }

    var body: some View {
        HStack(spacing: 0) {
            list
                .frame(maxWidth: .infinity)
            if canSplit, let editing {
                InventoryItemEditor(model: editing, style: .pane) { self.editing = nil }
                    .frame(maxWidth: .infinity)
                    .background(.background)
                    .id(editing.itemId)
                    .transition(.move(edge: .trailing))
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { updateSplit(geometry.size) }
                    .onChange(of: geometry.size) { _, size in updateSplit(size) }
            }
        }
        .navigationTitle(space.title)
        .accessibilityIdentifier("inventory.\(space.rawValue)")
        .floatingActionBar(model.phase == .content ? floatingActions : [], search: floatingSearch)
        .task {
            await model.load()
            open(launch)
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .sort: InventorySortSheet(model: model)
            case .filter: InventoryFilterSheet(model: model)
            case .scan:
                ScanItemSheet(model: ScanItemModel(space: space, client: models.everShelf)) {
                    Task { await models.refreshLoaded() }
                }
            }
        }
        .sheet(item: editorSheet) { editor in
            InventoryItemEditor(model: editor, style: .sheet) { editing = nil }
        }
        .alert(prompt?.title ?? "", isPresented: promptShown, presenting: prompt) { prompt in
            TextField("Quantity", text: $promptText)
                .numericEntryField()
                .accessibilityIdentifier("inventory.prompt.field")
            Button("Cancel", role: .cancel) {}
            Button(prompt.confirmTitle) { submit(prompt) }
        } message: { prompt in
            Text(prompt.message)
        }
        .confirmationDialog(
            confirmDelete.map { "Delete \($0.name) from the \(space.phrase)?" } ?? "",
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible,
            presenting: confirmDelete
        ) { item in
            Button("Delete", role: .destructive) { Task { await model.delete(item) } }
        }
        .animation(.default, value: canSplit && editing != nil)
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if model.phase == .loading {
            ProgressView("Loading \(space.title)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("inventory.loading")
        } else {
            List {
                if let empty = model.emptyState {
                    ContentUnavailableView {
                        Label(empty.title, systemImage: model.loadError == nil ? "basket" : "exclamationmark.triangle")
                    } description: {
                        Text(empty.description)
                    } actions: {
                        if model.loadError != nil {
                            Button("Try Again") { Task { try? await model.refresh() } }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("inventory.empty")
                }
                ForEach(model.visibleItems) { item in
                    InventoryRow(
                        item: item,
                        model: model,
                        selected: canSplit && editing?.itemId == item.id,
                        onEdit: { open(item) },
                        onShop: { ask(.shopping(item)) },
                        onDelete: { delete(item) }
                    )
                }
            }
            .groupedListStyle()
            .overlay(alignment: .top) {
                if model.isSearching {
                    ProgressView()
                        .padding(HassTokens.Spacing.s)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, HassTokens.Spacing.s)
                        .accessibilityLabel("Searching inventory")
                        .accessibilityIdentifier("inventory.searching")
                }
            }
            .refreshable { try? await model.refresh() }
        }
    }

    // MARK: - Floating actions

    /// Sort and Filter (brown while applied) once there is something to sort, then Scan Item: labeled on an
    /// empty page, icon-only beside the others (web `EverShelfInventoryFloatingActions` + the scan FAB).
    private var floatingActions: [FloatingAction] {
        let hasControls = !model.items.isEmpty || model.searchActive
        var actions: [FloatingAction] = []
        if hasControls {
            actions.append(FloatingAction(id: "inventory.sort", title: "Sort", symbol: "arrow.up.arrow.down", showsTitle: false, isActive: model.sortActive) { sheet = .sort })
            actions.append(FloatingAction(id: "inventory.filter", title: "Filter", symbol: "line.3.horizontal.decrease", showsTitle: false, isActive: model.filterActive) { sheet = .filter })
        }
        actions.append(FloatingAction(id: "inventory.scan", title: "Scan Item", symbol: "barcode.viewfinder", showsTitle: !hasControls) { sheet = .scan })
        return actions
    }

    /// The search FAB, once the page has loaded rows (or a search is running).
    private var floatingSearch: FloatingSearch? {
        guard model.phase == .content, !model.items.isEmpty || model.searchActive else { return nil }
        return FloatingSearch(text: $model.searchQuery, isExpanded: $searchExpanded, prompt: "Search items")
    }

    // MARK: - Actions

    private func open(_ launch: InventoryLaunch?) {
        switch launch {
        case let .sheet(next): sheet = next
        case let .editor(name): if let item = model.displayItem(id: name.lowercased()) { open(item) }
        case nil: break
        }
    }

    private func open(_ item: InventoryDisplayItem) {
        editing = InventoryEditorModel(item: item, list: model)
    }

    private func delete(_ item: InventoryDisplayItem) {
        guard let rows = model.deletableRows(of: item) else { return }
        let stocked = rows.reduce(0) { $0 + $1.quantity }
        if stocked > 1 {
            ask(.delete(item, stocked))
        } else {
            confirmDelete = item
        }
    }

    private func ask(_ next: InventoryPrompt) {
        promptText = "1"
        prompt = next
    }

    private func submit(_ prompt: InventoryPrompt) {
        switch prompt {
        case let .shopping(item):
            guard let quantity = InventoryFormat.parseQuantity(promptText), quantity >= 1 else { return }
            Task { await model.addToShopping(item, quantity: quantity) }
        case let .delete(item, stocked):
            guard let quantity = InventoryFormat.parseQuantity(promptText), quantity >= 1, quantity <= stocked else {
                model.setRowError("Enter a number from 1 to \(InventoryFormat.quantity(stocked)).", for: item.id)
                return
            }
            Task { await model.delete(item, quantity: quantity) }
        }
    }

    private var promptShown: Binding<Bool> {
        Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })
    }

    // MARK: - Split

    private func updateSplit(_ size: CGSize) {
        let allowed = SplitPolicy.allowsSplit(size: size, isRegularWidth: sizeClass == .regular)
        if allowed != canSplit { canSplit = allowed }
    }

    /// The editor as a sheet, only while the window can't split.
    private var editorSheet: Binding<InventoryEditorModel?> {
        Binding(get: { canSplit ? nil : editing }, set: { if $0 == nil, !canSplit { editing = nil } })
    }
}

extension InventoryEditorModel: Identifiable {
    public var id: String { itemId }
}

/// Sheets an inventory page presents.
enum InventorySheet: String, Identifiable {
    case sort, filter, scan
    var id: String { rawValue }
}

/// What an inventory page opens at launch.
enum InventoryLaunch: Equatable {
    case sheet(InventorySheet)
    /// The item editor for the card with this name.
    case editor(String)

    /// `sort`, `filter`, `scan` or `editor:<name>`.
    init?(_ raw: String) {
        if raw.hasPrefix("editor:") {
            self = .editor(String(raw.dropFirst("editor:".count)))
        } else if let sheet = InventorySheet(rawValue: raw) {
            self = .sheet(sheet)
        } else {
            return nil
        }
    }
}

/// Quantity prompts (the web's `window.prompt`s, as alerts with a field).
enum InventoryPrompt: Identifiable {
    case shopping(InventoryDisplayItem)
    case delete(InventoryDisplayItem, Double)

    var id: String {
        switch self {
        case let .shopping(item): "shop-\(item.id)"
        case let .delete(item, _): "delete-\(item.id)"
        }
    }

    var title: String {
        switch self {
        case let .shopping(item): "Add \(item.name) to Groceries"
        case let .delete(item, _): "Delete \(item.name)"
        }
    }

    var message: String {
        switch self {
        case let .shopping(item): "Quantity of \(item.name) to add to the grocery cart."
        case let .delete(item, stocked): "Choose how many \(item.name) to delete. Enter a number from 1 to \(InventoryFormat.quantity(stocked))."
        }
    }

    var confirmTitle: String {
        switch self {
        case .shopping: "Add"
        case .delete: "Delete"
        }
    }
}

// MARK: - Platform shims

extension View {
    /// Inset grouped list on iOS; inset on macOS (hosted tests).
    func groupedListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }

    /// A decimal-number field.
    func numericEntryField() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }
}
