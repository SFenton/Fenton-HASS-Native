#if DEBUG
import HassDesign
import SwiftUI

/// Gallery page for ``FloatingActionBar`` and ``FilterSheet``: a scrolling list under a bar with a labeled
/// action, an expandable search and icon-only Sort and Filter actions that open filter sheets.
struct FloatingActionsGallery: View {
    enum Sort: String, CaseIterable { case available = "Ingredients Available", expiring = "Expiring Soon", alphabetical = "Alphabetical" }

    @State private var query = ""
    @State private var searching = false
    @State private var sort: Sort = .available
    @State private var draftSort: Sort = .available
    @State private var minimum = 0.0
    @State private var draftMinimum = 0.0
    @State private var sheet: GallerySheet?

    enum GallerySheet: String, Identifiable {
        case sort, filter
        var id: String { rawValue }
    }
    @State private var lastAction = "none"

    private let items = (1...30).map { "Row \($0)" }

    var body: some View {
        List {
            Section {
                Text("Last action: \(lastAction)")
                    .font(.caption.monospaced())
                    .foregroundStyle(HassTokens.Ink.primary)
                    .accessibilityIdentifier("gallery.lastCall")
            }
            ForEach(items.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }, id: \.self) { Text($0) }
        }
        .navigationTitle("Floating Actions")
        .floatingActionBar([
            FloatingAction(id: "sort", title: "Sort", symbol: "arrow.up.arrow.down", showsTitle: false, isActive: sort != .available) {
                draftSort = sort
                sheet = .sort
            },
            FloatingAction(id: "filter", title: "Filter", symbol: "slider.horizontal.3", showsTitle: false, isActive: minimum > 0) {
                draftMinimum = minimum
                sheet = .filter
            },
            FloatingAction(id: "add", title: "Add Task", symbol: "plus") { lastAction = "add" },
        ], search: FloatingSearch(text: $query, isExpanded: $searching, prompt: "Search rows"))
        .sheet(item: $sheet) { sheet in
            if sheet == .sort {
                FilterSheet(title: "Sort Rows", canApply: draftSort != sort, canReset: draftSort != .available,
                            onApply: { sort = draftSort; lastAction = "sort \(sort.rawValue)" }, onReset: { draftSort = .available }) {
                    FilterSection("Sort By") {
                        ForEach(Sort.allCases, id: \.self) { option in
                            FilterOptionRow(title: option.rawValue, subtitle: "Sort by \(option.rawValue.lowercased()).", isSelected: draftSort == option) {
                                draftSort = option
                            }
                            .accessibilityIdentifier("gallery.sort.\(option)")
                        }
                    }
                }
            } else {
                FilterSheet(title: "Filter Rows", canApply: draftMinimum != minimum, canReset: draftMinimum != 0,
                            onApply: { minimum = draftMinimum; lastAction = "filter \(Int(minimum))" }, onReset: { draftMinimum = 0 }) {
                    FilterSection("Minimum Ingredients Available") {
                        Slider(value: $draftMinimum, in: 0...100, step: 5) { Text("Minimum Ingredients Available") }
                            .accessibilityValue("\(Int(draftMinimum)) percent")
                            .accessibilityIdentifier("gallery.filter.minimum")
                    }
                }
            }
        }
    }
}
#endif
