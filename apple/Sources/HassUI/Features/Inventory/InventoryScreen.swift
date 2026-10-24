import HassCore
import HassDesign
import SwiftUI

/// An inventory page: All Food, Pantry, Fridge, Freezer, Spice Rack or Cabinet
/// (web `EverShelfInventoryPanel`; spec `.agents/pages/inventory/spec.md`).
///
/// Rows come from `evershelf.list_inventory`, on one dense module under the large title and a "41 Items • 3 Expiring
/// Soon" line (direction G mockup n6-inventory). Search, Sort, Filter and Scan Item form the page's bottom toolbar.
/// Rows open the item editor: as a sheet, or in the trailing half where the window may split (iPad landscape,
/// unfolded iPhone Duo landscape).
struct InventoryScreen: View {
    @Bindable var model: InventoryListModel
    var models: InventoryModels
    /// A sheet or editor to open once rows load (debug gallery and journeys).
    var launch: InventoryLaunch?

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentation: InventoryPresentation
    @State private var searchExpanded = false
    /// The list column's width, to keep its rows to a readable measure on wide windows.
    @State private var listWidth: CGFloat = 0

    /// The widest the rows run (HIG Layout: readable content width). On an iPad in portrait the list is the whole window
    /// and its rows put the name and the cart a thousand points apart; the margins center a 720 pt measure instead.
    static let readableWidth: CGFloat = 720

    /// The list's side margin for a column `width` wide: the page margin while the column is narrower than the readable
    /// measure, else whatever centres the measure. (`contentMargins` replaces the list's own inset, so a narrow column must
    /// keep the page margin or its modules run edge to edge.)
    static func sideMargin(forWidth width: CGFloat) -> CGFloat {
        max(HassTokens.Spacing.l, (width - readableWidth) / 2)
    }

    /// - Parameter presentation: what the page starts out presenting (tests and previews).
    init(model: InventoryListModel, models: InventoryModels, launch: InventoryLaunch? = nil, presentation: InventoryPresentation = InventoryPresentation()) {
        self.model = model
        self.models = models
        self.launch = launch
        _presentation = State(initialValue: presentation)
    }

    private var space: InventorySpace { model.space }
    private var editing: InventoryEditorModel? { presentation.editing }
    private var canSplit: Bool { presentation.canSplit }

    var body: some View {
        HStack(spacing: 0) {
            // The page identifier and the floating actions belong to the list column: on the whole row the
            // identifier replaced the editor pane's identifiers, and the bar covered the pane.
            // The page waits for its first rows like the web (`EverShelfInventoryPanel.tsx:2013`): the spinner fades in, stays,
            // fades out and the list fades in. The floating actions are inside, so they arrive with the rows.
            ContentGate(
                page: "Inventory · \(space.rawValue)", isReady: model.phase == .content, timing: .page, reloadTiming: .results,
                label: "Loading \(space.title)"
            ) {
                list
                    .frame(maxWidth: .infinity)
                    .scrollTelemetry("Inventory · \(space.rawValue)")
                    .accessibilityIdentifier("inventory.\(space.rawValue)")
                    .floatingActionBar(showsFloatingActions ? floatingActions : [], search: showsFloatingActions ? floatingSearch : nil)
            }
            .frame(maxWidth: .infinity)
            if canSplit, let editing {
                InventoryItemEditor(model: editing, style: .pane) { presentation.editing = nil }
                    .frame(maxWidth: .infinity)
                    .background(.background)
                    .id(editing.itemId)
                    // Reduce Motion: the pane fades in instead of sliding (HIG Motion).
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing))
            }
        }
        .onGeometryChange(for: CGSize.self, of: \.size) { updateSplit($0) }
        .navigationTitle(space.title)
        .task {
            await model.load()
            presentation.open(launch, in: model)
        }
        .sheet(item: $presentation.sheet) { sheet in
            InventorySheetContent(sheet: sheet, model: model, models: models)
        }
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
            presentation.confirmDelete.map { "Delete \($0.name) from the \(space.phrase)?" } ?? "",
            isPresented: Bindable(presentation).confirmDelete.isPresent(),
            titleVisibility: .visible,
            presenting: presentation.confirmDelete
        ) { item in
            Button("Delete", role: .destructive) { Task { await model.delete(item) } }
        }
        .motionSafeAnimation(MotionTokens.standard, reduced: MotionTokens.quick, value: canSplit && editing != nil)
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if model.phase == .loading {
            // The gate's spinner stands in until the rows arrive.
            Color.clear
        } else if let empty = model.emptyState {
            // Centred on the page (mockup n6-inventory-empty), and still scrolling once AX sizes make it taller.
            GeometryReader { geometry in
                ScrollView {
                    InventoryEmptyState(title: empty.title, description: empty.description, isError: model.loadError != nil) {
                        Task { _ = try? await model.refresh() }
                    }
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .refreshable { _ = try? await model.refresh() }
            }
        } else {
            // G: ModuleList. A `List` rather than a stack on a module: rows keep their swipe actions (delete, add to
            // groceries), which need a `List` before iOS 27. Each row draws its share of its section's dense module.
            List {
                if let summary = model.pageSummary { summaryRow(summary) }
                ForEach(InventorySections.make(model.visibleItems, sort: model.sortMode, calendar: model.calendar)) { section in
                    sectionView(section)
                }
            }
            .groupedListStyle()
            // Tight between the summary line and the first module; the section headers carry their own space.
            .compactListSections()
            .contentMargins(.horizontal, Self.sideMargin(forWidth: listWidth), for: .scrollContent)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { listWidth = $0 }
            // G rows: 64 pt with a subtitle (mockup `.row.n6-inv`).
            .environment(\.defaultMinListRowHeight, 64)
            .overlay(alignment: .top) {
                if model.isSearching {
                    ArcSpinner(.compact, label: "Searching inventory")
                        .padding(HassTokens.Spacing.s)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, HassTokens.Spacing.s)
                        .accessibilityIdentifier("inventory.searching")
                }
            }
            .refreshable { _ = try? await model.refresh() }
        }
    }

    /// "41 Items • 3 Expiring Soon" under the large title (mockup n6-inventory), aligned with the rows' text.
    private func summaryRow(_ summary: String) -> some View {
        Section {
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(HassTokens.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: HassTokens.Spacing.l, bottom: 0, trailing: HassTokens.Spacing.l))
                .accessibilityIdentifier("inventory.summary")
        }
    }

    /// One group of rows, under its status header when the page is sorted by expiration (a page sorted by title is one list).
    private func sectionView(_ section: InventorySection) -> some View {
        Section {
            ForEach(section.items) { item in
                InventoryRow(
                    item: item,
                    model: model,
                    selected: canSplit && editing?.itemId == item.id,
                    isFirst: item.id == section.items.first?.id,
                    isLast: item.id == section.items.last?.id,
                    onEdit: { presentation.open(item, in: model) },
                    onShop: { presentation.ask(.shopping(item)) },
                    onDelete: { presentation.requestDelete(item, in: model) }
                )
            }
        } header: {
            if let title = section.title { sectionHeader(title, count: section.items.count, id: section.id) }
        }
    }

    private func sectionHeader(_ title: String, count: Int, id: String) -> some View {
        PageSectionHeader(title, detail: String(count))
            .textCase(nil)
            .accessibilityIdentifier("inventory.section.\(id)")
    }

    // MARK: - Floating actions

    /// Sort and Filter (filled while applied) once there is something to sort, then Scan Item: a titled glass capsule
    /// on an empty page (mockup n6-inventory-empty), a glass circle beside the others (web
    /// `EverShelfInventoryFloatingActions` + the scan FAB).
    private var floatingActions: [FloatingAction] {
        let hasControls = !model.items.isEmpty || model.searchActive
        var actions: [FloatingAction] = []
        if hasControls {
            actions.append(FloatingAction(id: "inventory.sort", title: "Sort", symbol: "arrow.up.arrow.down", showsTitle: false, isActive: model.sortActive) { presentation.sheet = .sort })
            actions.append(FloatingAction(id: "inventory.filter", title: "Filter", symbol: "line.3.horizontal.decrease", showsTitle: false, isActive: model.filterActive) { presentation.sheet = .filter })
        }
        actions.append(FloatingAction(id: "inventory.scan", title: "Scan Item", symbol: "barcode.viewfinder", showsTitle: !hasControls, isProminent: false) { presentation.sheet = .scan })
        return actions
    }

    /// Floating actions show once rows load, and hide while a sheet is up: beside an iPad form sheet they were
    /// drawn above its dimming and stayed reachable under the modal.
    private var showsFloatingActions: Bool {
        model.phase == .content && presentation.sheet == nil && presentation.sheetEditor == nil
    }

    /// The search FAB, once the page has loaded rows (or a search is running).
    private var floatingSearch: FloatingSearch? {
        guard model.phase == .content, !model.items.isEmpty || model.searchActive else { return nil }
        return FloatingSearch(text: $model.searchQuery, isExpanded: $searchExpanded, prompt: "Search items")
    }

    // MARK: - Presentation

    private var promptShown: Binding<Bool> {
        Bindable(presentation).prompt.isPresent()
    }

    private func updateSplit(_ size: CGSize) {
        presentation.updateSplit(size, isRegularWidth: sizeClass == .regular)
    }
}

/// The content of a page's Sort, Filter or Scan Item sheet.
struct InventorySheetContent: View {
    var sheet: InventorySheet
    var model: InventoryListModel
    var models: InventoryModels

    var body: some View {
        switch sheet {
        case .sort: InventorySortSheet(model: model)
        case .filter: InventoryFilterSheet(model: model)
        case .scan:
            ScanItemSheet(model: ScanItemModel(space: model.space, client: models.everShelf)) {
                Task { await models.refreshLoaded() }
            }
        }
    }
}

extension InventoryEditorModel: @MainActor Identifiable {
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

    /// Tight space between list sections (iOS; the macOS host that runs hosted tests has no such control).
    func compactListSections() -> some View {
        #if os(iOS)
        listSectionSpacing(.compact)
        #else
        self
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
