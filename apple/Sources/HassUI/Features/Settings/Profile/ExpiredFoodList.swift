import HassCore
import HassDesign
import SwiftUI

/// The expired rows, from the All Food model, with the Food page's actions.
struct ExpiredFoodList: View {
    @Bindable var model: InventoryListModel
    /// The sensor's state, so the rows reload when the house says something expired or was cleared.
    var sensor: EntityState?
    @State private var presentation = InventoryPresentation()

    /// Expired cards, soonest expiry first (the web locks the shared controls to this filter and sort).
    private var items: [InventoryDisplayItem] {
        InventoryCatalog.visible(model.displayItems, sort: .expiry, direction: .ascending, filter: .expired, calendar: model.calendar)
    }

    var body: some View {
        let items = items
        List {
            PageSectionHeader(SummaryTab.expiredFood.title)
                .modifier(TodoPlainRow(top: HassTokens.Spacing.m, bottom: HassTokens.Spacing.s))
            if model.phase == .loading {
                ArcSpinner(.compact, label: "Loading Expired Food")
                    .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
                    .modifier(TodoPlainRow(top: 0, bottom: 0))
            } else if let error = model.loadError {
                InlineAlert(error)
                    .modifier(TodoPlainRow(top: 0, bottom: HassTokens.Spacing.s))
                    .accessibilityIdentifier("summary.expired-food.error")
            } else if items.isEmpty {
                SummaryEmptyState(copy: ProfileSummary.noExpiredFood, symbol: "checkmark.circle", identifier: "summary.empty.expired-food")
                .modifier(TodoPlainRow(top: HassTokens.Spacing.m, bottom: 0))
            } else {
                ForEach(items) { item in
                    InventoryRow(
                        item: item,
                        model: model,
                        isFirst: item.id == items.first?.id,
                        isLast: item.id == items.last?.id,
                        onEdit: { presentation.open(item, in: model) },
                        onShop: { presentation.ask(.shopping(item)) },
                        onDelete: { presentation.requestDelete(item, in: model) }
                    )
                }
            }
        }
        .groupedListStyle()
        .compactListSections()
        // G rows: 64 pt with a subtitle (mockup `.row.n6-inv`), as on the Food page.
        .environment(\.defaultMinListRowHeight, 64)
        .accessibilityIdentifier("summary.expired-food")
        .inventoryRowActions(presentation, model: model)
        .refreshable { _ = try? await model.refresh() }
        .task(id: sensor) { await model.load() }
    }
}
