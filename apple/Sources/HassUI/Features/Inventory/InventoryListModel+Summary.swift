import HassCore

extension InventoryListModel {
    /// The line under the page's large title, "41 Items • 3 Expiring Soon" (mockup n6-inventory), in the Food hub's
    /// wording (``FoodConfig/summary(items:expiring:)``): the page's cards and those whose soonest batch expires within
    /// the week. `nil` until rows load, on an empty page, and while searching (the rows are then search results).
    var pageSummary: String? {
        guard phase == .content, loadError == nil, !searchActive else { return nil }
        let cards = displayItems
        guard !cards.isEmpty else { return nil }
        let expiring = cards.filter { card in
            InventoryCatalog.expiryInfo(card.soonestExpiry(calendar), calendar: calendar).tone == .soon
        }.count
        return FoodConfig.summary(items: cards.count, expiring: expiring)
    }

    /// "4 of 41 Items": the cards `filter` would show, under the Filter sheet's title (mockup n6-inventory-filter).
    func filterSummary(_ filter: InventoryFilterMode) -> String {
        let cards = displayItems
        let shown = InventoryCatalog.visible(cards, sort: sortMode, direction: sortDirection, filter: filter, calendar: calendar).count
        return "\(shown) of \(cards.count) \(cards.count == 1 ? "Item" : "Items")"
    }
}
