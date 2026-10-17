#if DEBUG
import HassDesign
import SwiftUI

/// Gallery page for modal sizing and chrome (`.agents/design/direction-g.md`, Sheets; pattern `modal-sheet.md`): a short
/// sheet that opens at its content's height, a tall one that scrolls at large, a sheet with the section tab bar
/// (full height, icons on iPhone), an edit sheet whose confirm check is disabled until a change, and the Sort and
/// Filter sheets (blue Reset row, no translucent header). Launch with `FENTON_GALLERY=modal-sizing`.
struct ModalSizingGallery: View {
    enum Kind: String, Identifiable {
        case short, tall, tabs, edit, sort, filter
        var id: String { rawValue }
    }

    @State private var open: Kind? = Kind(rawValue: UserDefaults.standard.string(forKey: "modalSizingOpen") ?? "")

    var body: some View {
        ScrollView {
            VStack(spacing: HassTokens.Spacing.m) {
                button("Short Sheet", .short)
                button("Tall Sheet", .tall)
                button("Tab Sheet", .tabs)
                button("Edit Sheet", .edit)
                button("Sort Sheet", .sort)
                button("Filter Sheet", .filter)
            }
            .padding(HassTokens.Spacing.l)
        }
        .navigationTitle("Modal Sizing")
        .sheet(item: $open) { kind in
            switch kind {
            case .short: ShortSheet().hassSheet(.form)
            case .tall: TallSheet().hassSheet(.form)
            case .tabs: TabSheet().hassSheet(.page, height: .full)
            case .edit: EditSheet().hassSheet(.form)
            case .sort: SortSheet()
            case .filter: FilterDemoSheet()
            }
        }
    }

    private func button(_ title: String, _ kind: Kind) -> some View {
        PrimaryButton(title) { open = kind }
            .accessibilityIdentifier("sizing.open.\(kind.rawValue)")
    }
}

/// Three rows: opens at their height, not at large.
private struct ShortSheet: View {
    var body: some View {
        HassModal("Lighting Mode", closeIdentifier: "sizing.close") {
            ScrollView {
                ModuleList {
                    ModuleRow("Warm", symbol: "sun.max")
                    ModuleRow("Cool", symbol: "snowflake")
                    ModuleRow("Party", symbol: "party.popper")
                }
                .padding(HassTokens.Spacing.l)
            }
            .accessibilityIdentifier("sizing.short.scroll")
        }
    }
}

/// More rows than the screen holds: reaches large and scrolls.
private struct TallSheet: View {
    var body: some View {
        HassModal("All Lights", closeIdentifier: "sizing.close") {
            ScrollView {
                ModuleList {
                    ForEach(1...40, id: \.self) { index in
                        ModuleRow("Light \(index)", symbol: "lightbulb")
                    }
                }
                .padding(HassTokens.Spacing.l)
            }
            .accessibilityIdentifier("sizing.tall.scroll")
        }
    }
}

/// A modal with a section tab bar, which always opens at full height.
private struct TabSheet: View {
    enum Tab: String, CaseIterable, Identifiable {
        case controls = "Controls", apps = "Apps", info = "Info"
        var id: Self { self }
        var symbol: String {
            switch self {
            case .controls: "appletvremote.gen4"
            case .apps: "play.rectangle"
            case .info: "info.circle"
            }
        }
    }

    @State private var tab = Tab.controls

    var body: some View {
        HassModal("Living Room TV", closeIdentifier: "sizing.close") {
            ScrollView {
                Text(tab.rawValue)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .padding(HassTokens.Spacing.l)
            }
            .accessibilityIdentifier("sizing.tabs.scroll")
            .modalTabBar(Tab.allCases, label: "TV sections", title: \.rawValue, symbol: \.symbol, selection: $tab,
                         identifier: "sizing.tabs")
        }
    }
}

/// An edit sheet: the confirm check shows but is disabled until the draft changes.
private struct EditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Replace the furnace filter"
    private let original = "Replace the furnace filter"

    var body: some View {
        NavigationStack {
            Form {
                TextField("Task Name", text: $name)
                    .accessibilityIdentifier("sizing.edit.name")
            }
            .modalChrome()
            .navigationTitle("Edit Task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                SheetCancelItem(identifier: "sizing.edit.cancel") { dismiss() }
                SheetConfirmItem("Save", isEnabled: SheetEditState.canConfirm(isValid: !name.isEmpty, hasChanges: name != original),
                                 identifier: "sizing.edit.save") { dismiss() }
            }
        }
        .followsSystemAppearance()
    }
}

private struct SortSheet: View {
    @State private var draft = 0

    var body: some View {
        FilterSheet(title: "Sort Rows", canApply: draft != 0, canReset: draft != 0, onApply: {}, onReset: { draft = 0 }) {
            FilterSection("Sort By") {
                ForEach(0..<3, id: \.self) { index in
                    FilterOptionRow(title: "Option \(index + 1)", isSelected: draft == index) { draft = index }
                        .accessibilityIdentifier("sizing.sort.\(index)")
                }
            }
        }
    }
}

/// A Filter sheet that opens with a change already made, so the Reset row is on screen.
private struct FilterDemoSheet: View {
    @State private var expiringOnly = true
    @State private var minimum = 40.0

    var body: some View {
        FilterSheet(title: "Filter Recipes", subtitle: expiringOnly ? "1 Filter On" : nil, canApply: expiringOnly,
                    canReset: expiringOnly || minimum != 0, onApply: {}, onReset: { expiringOnly = false; minimum = 0 }) {
            Section {
                Toggle("Expiring Ingredients Only", isOn: $expiringOnly)
                    .accessibilityIdentifier("sizing.filter.expiring")
                Slider(value: $minimum, in: 0...100)
                    .accessibilityLabel("Minimum Ingredients Available")
            } header: {
                Text("Ingredient Coverage")
            }
            // Enough rows that the form scrolls: the header must stay clear of a material while rows pass under it.
            Section {
                ForEach(1...14, id: \.self) { index in
                    Toggle("Category \(index)", isOn: .constant(false))
                }
            } header: {
                Text("Categories")
            }
        }
    }
}
#endif
