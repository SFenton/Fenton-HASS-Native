import HassCore
import HassDesign
import SwiftUI

/// Sort Inventory (web `InventorySortSheet`) on the shared ``FilterSheet``: Apply commits the draft and
/// Reset puts it back to Title, Ascending.
struct InventorySortSheet: View {
    var model: InventoryListModel
    @State private var mode: InventorySortMode
    @State private var direction: InventorySortDirection

    init(model: InventoryListModel) {
        self.model = model
        _mode = State(initialValue: model.sortMode)
        _direction = State(initialValue: model.sortDirection)
    }

    var body: some View {
        FilterSheet(
            title: "Sort Inventory",
            canApply: mode != model.sortMode || direction != model.sortDirection,
            canReset: mode != .title || direction != .ascending,
            onApply: {
                model.sortMode = mode
                model.sortDirection = direction
            },
            onReset: {
                mode = .title
                direction = .ascending
            }
        ) {
            FilterSection("Sort By") {
                ForEach(InventorySortMode.allCases) { option in
                    FilterOptionRow(title: option.title, subtitle: option.subtitle, isSelected: mode == option) { mode = option }
                        .accessibilityIdentifier("inventory.sort.\(option.rawValue)")
                }
            }
            // Option rows rather than a segmented control and footnote: both were reported clipped at large
            // text sizes; rows wrap like Sort By above.
            FilterSection("Sort Direction") {
                ForEach(InventorySortDirection.allCases) { option in
                    FilterOptionRow(title: option.title, subtitle: option.hint, isSelected: direction == option) { direction = option }
                        .accessibilityIdentifier("inventory.sort.direction.\(option.rawValue)")
                }
            }
        }
    }
}

/// Filter Inventory (web `InventoryFilterSheet`; mockup n6-inventory-filter) on the shared ``FilterSheet``: a "Show"
/// checkmark list of the filters, each with what it keeps, and how many cards the chosen one shows under the title.
struct InventoryFilterSheet: View {
    var model: InventoryListModel
    @State private var mode: InventoryFilterMode

    init(model: InventoryListModel) {
        self.model = model
        _mode = State(initialValue: model.filterMode)
    }

    var body: some View {
        FilterSheet(
            title: "Filter Inventory",
            subtitle: model.filterSummary(mode),
            canApply: mode != model.filterMode,
            canReset: mode != .all,
            onApply: { model.filterMode = mode },
            onReset: { mode = .all }
        ) {
            // "Show" rather than the web's "Filter Items", which repeated the sheet title. FilterSection's header wraps at
            // AX sizes (the old custom header was reported clipped).
            FilterSection("Show") {
                ForEach(InventoryFilterMode.allCases) { option in
                    FilterOptionRow(title: option.title, subtitle: option.subtitle, isSelected: mode == option) { mode = option }
                        .accessibilityIdentifier("inventory.filter.\(option.rawValue)")
                }
            }
        }
    }
}
