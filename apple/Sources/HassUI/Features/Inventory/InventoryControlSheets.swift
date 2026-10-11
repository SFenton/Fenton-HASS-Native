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
            Section("Sort By") {
                ForEach(InventorySortMode.allCases) { option in
                    FilterOptionRow(title: option.title, subtitle: option.subtitle, isSelected: mode == option) { mode = option }
                        .accessibilityIdentifier("inventory.sort.\(option.rawValue)")
                }
            }
            Section {
                Picker("Sort Direction", selection: $direction) {
                    ForEach(InventorySortDirection.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("inventory.sort.direction")
            } header: {
                Text("Sort Direction")
            } footer: {
                // Ink rather than the system footer gray, which reads 3.2:1; wraps at large text sizes.
                Text(direction.hint)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Filter Inventory (web `InventoryFilterSheet`) on the shared ``FilterSheet``.
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
            canApply: mode != model.filterMode,
            canReset: mode != .all,
            onApply: { model.filterMode = mode },
            onReset: { mode = .all }
        ) {
            Section("Filter Items") {
                ForEach(InventoryFilterMode.allCases) { option in
                    FilterOptionRow(title: option.title, subtitle: option.subtitle, isSelected: mode == option) { mode = option }
                        .accessibilityIdentifier("inventory.filter.\(option.rawValue)")
                }
            }
        }
    }
}
